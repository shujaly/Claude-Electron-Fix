param([switch]$Uninstall)

if ($env:OS -ne 'Windows_NT') {
    Write-Host 'Smooth Launch only works on Windows.' -ForegroundColor Red
    exit 1
}

# Get-AppxPackage is unreliable under PowerShell 7, so hand off to the built-in Windows PowerShell.
if ($PSVersionTable.PSEdition -eq 'Core') {
    $winPs = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    if ($Uninstall) { $argList += '-Uninstall' }
    & $winPs @argList
    exit $LASTEXITCODE
}

$root = Join-Path $env:LOCALAPPDATA 'SmoothLaunch'
$startMenu = [Environment]::GetFolderPath('Programs')
$apps = @('Claude')
$flag = '--disable-gpu-compositing'

function Write-Report([string[]]$Lines, [string]$LogPath) {
    Write-Host ''
    Write-Host '===== What Smooth Launch did =====' -ForegroundColor Cyan
    foreach ($l in $Lines) { Write-Host $l }
    if ($LogPath) {
        Set-Content -LiteralPath $LogPath -Value $Lines -Encoding UTF8
        Write-Host ''
        Write-Host "This summary was also saved to $LogPath" -ForegroundColor DarkGray
    }
    Write-Host ''
}

if ($Uninstall) {
    $removed = @()
    foreach ($a in $apps) {
        $lnk = Join-Path $startMenu "$a Smooth.lnk"
        if (Test-Path -LiteralPath $lnk) {
            Remove-Item -LiteralPath $lnk -Force
            $removed += "  $lnk"
        }
    }
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force
        $removed += "  $root  (launcher script, icons, install log)"
    }

    $lines = @('')
    if ($removed.Count) {
        $lines += 'Removed:'
        $lines += $removed
        $lines += ''
        $lines += 'Claude itself was not touched. Open it from its normal Start menu entry.'
        $lines += 'If you pinned "Claude Smooth" to the taskbar, unpin it too; the pin no longer works.'
        $lines += 'If Claude is open right now, it keeps running with the fix until you close it.'
    } else {
        $lines += 'Nothing to remove. Smooth Launch was not installed for this user.'
    }
    Write-Report $lines
    return
}

$launcherCode = @'
param(
    [Parameter(Mandatory)][ValidateSet('Claude')][string]$App,
    [switch]$ResolveOnly
)

$flag = '--disable-gpu-compositing'

$spec = @{
    Claude = @{
        Packages    = @('Claude')
        PackageExes = @('app\Claude.exe')
        Paths       = @(
            "$env:LOCALAPPDATA\AnthropicClaude\claude.exe",
            "$env:LOCALAPPDATA\Programs\Claude\Claude.exe",
            "$env:ProgramFiles\Claude\Claude.exe"
        )
        Name        = '^Claude$'
    }
}[$App]

function Found([string]$Path, [string]$Source, [string]$Aumid) {
    [pscustomobject]@{ Path = $Path; Source = $Source; Aumid = $Aumid }
}

function Get-Aumid($Pkg, [string]$Rel) {
    try {
        $entries = @((Get-AppxPackageManifest $Pkg).Package.Applications.Application)
        $entry = $entries | Where-Object { $_.Executable -eq $Rel } | Select-Object -First 1
        if (-not $entry) { $entry = $entries[0] }
        if ($entry.Id) { return "$($Pkg.PackageFamilyName)!$($entry.Id)" }
    } catch { }
}

function Resolve-App {
    foreach ($name in $spec.Packages) {
        $pkg = Get-AppxPackage -Name $name -ErrorAction SilentlyContinue |
            Sort-Object Version -Descending | Select-Object -First 1
        if (-not ($pkg -and $pkg.InstallLocation)) { continue }
        foreach ($rel in $spec.PackageExes) {
            $p = Join-Path $pkg.InstallLocation $rel
            if (Test-Path -LiteralPath $p) {
                return Found $p "Microsoft Store package $($pkg.Name) $($pkg.Version)" (Get-Aumid $pkg $rel)
            }
        }
    }

    foreach ($p in $spec.Paths) {
        if (Test-Path -LiteralPath $p) { return Found $p 'standard install folder' }
    }

    $keys = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($e in Get-ItemProperty $keys -ErrorAction SilentlyContinue) {
        if ($e.DisplayName -notmatch $spec.Name -or -not $e.DisplayIcon) { continue }
        $p = ($e.DisplayIcon -split ',')[0].Trim().Trim('"')
        if ($p -like '*.exe' -and (Test-Path -LiteralPath $p)) { return Found $p 'Windows installed-apps list' }
    }

    try { $shell = New-Object -ComObject WScript.Shell } catch { return }
    foreach ($dir in [Environment]::GetFolderPath('Programs'), [Environment]::GetFolderPath('CommonPrograms')) {
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter *.lnk -Recurse -ErrorAction SilentlyContinue) {
            if ($f.BaseName -notmatch $spec.Name) { continue }
            $lnk = $shell.CreateShortcut($f.FullName)
            $t = $lnk.TargetPath
            if (-not $t) { continue }
            # Squirrel-style installers point shortcuts at Update.exe --processStart <app>.exe
            if ((Split-Path $t -Leaf) -eq 'Update.exe' -and $lnk.Arguments -match '--processStart\s+"?([^"\s]+)') {
                $t = Join-Path (Split-Path $t) $Matches[1]
            }
            if ($t -like '*.exe' -and (Test-Path -LiteralPath $t)) { return Found $t "Start menu shortcut $($f.Name)" }
        }
    }
}

function Show-Error([string]$Message) {
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show($Message, "$App Smooth", 'OK', 'Warning') | Out-Null
    } catch { }
}

$found = Resolve-App
if ($ResolveOnly) { return $found }

if (-not $found) {
    Show-Error "Couldn't find $App on this PC. If it was uninstalled or moved, reinstall it, then run Install.cmd from Smooth Launch again."
    exit 1
}

$exe = $found.Path
$dir = Split-Path $exe
$name = Split-Path $exe -Leaf

try {
    $running = @(Get-CimInstance Win32_Process -Filter "Name='$name'" -ErrorAction Stop |
        Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($dir, [StringComparison]::OrdinalIgnoreCase) })
} catch { $running = @() }

# A running copy without the flag would swallow the new launch, so restart it.
if ($running.Count -and -not ($running | Where-Object { $_.CommandLine -like "*$flag*" })) {
    $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Milliseconds 1000
}

# Store apps must be started by Windows, not by path, or they lose their package identity
# and may refuse to run. Activation still passes the flag through.
function Start-StoreApp([string]$Aumid, [string]$Arguments) {
    if (-not ('SmoothActivator' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport, Guid("2e941141-7f97-4756-ba1d-9decde894a3d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IApplicationActivationManager {
    void ActivateApplication([MarshalAs(UnmanagedType.LPWStr)] string appUserModelId, [MarshalAs(UnmanagedType.LPWStr)] string arguments, int options, out uint processId);
}

[ComImport, Guid("45BA127D-10A8-46EA-8AB7-56EA9078943C")]
class ApplicationActivationManager { }

public static class SmoothActivator {
    public static uint Launch(string aumid, string arguments) {
        uint pid;
        ((IApplicationActivationManager)new ApplicationActivationManager()).ActivateApplication(aumid, arguments, 0, out pid);
        return pid;
    }
}
"@
    }
    [SmoothActivator]::Launch($Aumid, $Arguments) | Out-Null
}

if ($found.Aumid) {
    try {
        Start-StoreApp $found.Aumid $flag
        exit 0
    } catch {
        $activationError = $_.Exception.Message
    }
}

try {
    Start-Process -FilePath $exe -ArgumentList $flag -ErrorAction Stop
} catch {
    $why = $_.Exception.Message
    if ($activationError) { $why = "Starting it as a Store app failed: $activationError`nStarting it directly failed: $why" }
    Show-Error "Couldn't start $($App):`n$exe`n`n$why"
    exit 1
}
'@

New-Item -ItemType Directory -Force -Path $root | Out-Null
$launcher = Join-Path $root 'launch.ps1'
Set-Content -LiteralPath $launcher -Value $launcherCode -Encoding UTF8

$psExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`" -App"
# conhost --headless hides the PowerShell window completely; older builds get a brief flash instead.
$headless = [Environment]::OSVersion.Version.Build -ge 19041

try { Add-Type -AssemblyName System.Drawing } catch { }
$shell = New-Object -ComObject WScript.Shell

$appLines = @()
$files = @("  $launcher  (the script the shortcut runs)")
$notes = @()
$installed = @()

foreach ($a in $apps) {
    $found = & $launcher -App $a -ResolveOnly
    if (-not $found) {
        $appLines += ('{0,-7} skipped: not installed, or not in any location Smooth Launch knows about' -f $a)
        continue
    }

    $lnkPath = Join-Path $startMenu "$a Smooth.lnk"
    $verb = if (Test-Path -LiteralPath $lnkPath) { 'updated' } else { 'added' }

    $ico = Join-Path $root "$a.ico"
    try {
        $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($found.Path)
        $fs = [IO.File]::Create($ico)
        try { $icon.Save($fs) } finally { $fs.Close() }
        $iconLocation = "$ico,0"
        $files += "  $ico"
    } catch {
        $iconLocation = "$($found.Path),0"
        $notes += "- Couldn't copy the $a icon, so its shortcut borrows it from the app. It may go blank after $a updates; re-run Install.cmd to fix."
    }

    $lnk = $shell.CreateShortcut($lnkPath)
    if ($headless) {
        $lnk.TargetPath = Join-Path $env:WINDIR 'System32\conhost.exe'
        $lnk.Arguments = "--headless `"$psExe`" $psArgs $a"
    } else {
        $lnk.TargetPath = $psExe
        $lnk.Arguments = "$psArgs $a"
    }
    $lnk.WindowStyle = 7
    $lnk.IconLocation = $iconLocation
    $lnk.Description = "$a with GPU compositing disabled (Smooth Launch)"
    $lnk.Save()

    $files += "  $lnkPath"
    $installed += $a
    $appLines += ('{0,-7} {1} "{0} Smooth" to the Start menu' -f $a, $verb)
    $appLines += ('        opens:    {0} {1}' -f $found.Path, $flag)
    $appLines += ('        found in: {0}' -f $found.Source)
    if ($found.Aumid) {
        $appLines += ('        started:  by Windows as Store app {0}, so it keeps its package identity' -f $found.Aumid)
    }
}

$lines = @('')
$lines += $appLines
$lines += ''

if (-not $installed.Count) {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    $lines += 'Nothing was installed and nothing on this PC was changed.'
    $lines += 'If Claude IS installed, please open an issue on GitHub and include this output.'
    Write-Report $lines
    exit 1
}

if (-not $headless) {
    $notes += '- This version of Windows lacks the hidden-console option, so a PowerShell window flashes briefly when you open Claude Smooth. Harmless.'
}

$lines += 'Files written:'
$lines += $files
$lines += ''
$lines += 'Not changed: Claude''s own files, its original Start menu entry, the registry, and system settings. No admin rights were used.'
$lines += ''
$lines += 'Next:'
$lines += ('- Search "{0} Smooth" in the Start menu and open it.' -f $installed[0])
$lines += '- If Claude is already open normally, it will close and reopen with the fix. Anything unsaved in it may be lost.'
$lines += '- Optional: right-click "Claude Smooth" to pin it, and unpin the original so you don''t open the laggy one by habit.'
$lines += '- To undo everything: run Uninstall.cmd.'
if ($notes.Count) {
    $lines += ''
    $lines += 'Notes:'
    $lines += $notes
}

Write-Report $lines (Join-Path $root 'install-log.txt')
