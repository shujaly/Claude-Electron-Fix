# Smooth Launch

Fixes the choppy, stuttering mouse cursor on Windows when the **Claude** desktop app is open.

It adds **Claude Smooth** to the Start menu. It opens Claude with GPU compositing turned off, and it shows up in Windows search like any other app.

> **Only install this if you have the problem.** The fix moves some drawing work from your graphics card to your CPU. If your cursor is already smooth, you'd only be paying that cost for nothing.

## The problem

The Claude desktop app is built on Electron. On some Windows PCs, especially laptops with both integrated and dedicated graphics, Claude keeps redrawing its window even when nothing is happening. That competes with Windows' own window manager, which also draws your cursor, so the cursor stutters or jumps across the whole screen, not just inside Claude. It usually stops the moment you minimize Claude.

Launching Claude with `--disable-gpu-compositing` stops this. The Microsoft Store version of Claude ignores the usual ways of passing that option, so you can't just edit a shortcut. This tool works around that.

Related reports:
- [anthropics/claude-code#56805](https://github.com/anthropics/claude-code/issues/56805)
- [anthropics/claude-code#77857](https://github.com/anthropics/claude-code/issues/77857)
- [anthropics/claude-code#45127](https://github.com/anthropics/claude-code/issues/45127)

## Install

1. Click **Code > Download ZIP** at the top of this page, then extract the ZIP. Right-click it and choose **Extract All**. Don't run it from inside the ZIP.
2. Double-click **`Install.cmd`**.
   - If Windows shows a blue "Windows protected your PC" screen, click **More info**, then **Run anyway**. That's shown for any script downloaded from the internet.
3. Read the summary it prints. It shows what was added, which Claude file the shortcut opens, and every file it wrote. A copy is saved to `%LOCALAPPDATA%\SmoothLaunch\install-log.txt`.
4. Search **Claude Smooth** in the Start menu and open it.
5. Optional: pin Claude Smooth to Start or the taskbar, and unpin the original Claude entry.

You only need to install once. Each time you open Claude Smooth, it looks up where Claude is currently installed, so it keeps working after Claude updates.

No admin rights are needed, and it only affects the Windows user who runs it.

## Uninstall

Double-click **`Uninstall.cmd`**. It removes Claude Smooth and `%LOCALAPPDATA%\SmoothLaunch`, then lists what it removed. Claude itself is never touched.

If you pinned Claude Smooth to the taskbar, unpin it too.

## What it changes

| Changed | Not changed |
| --- | --- |
| Adds a `Claude Smooth` shortcut to your Start menu | Claude's own files |
| Writes a launcher script and an icon to `%LOCALAPPDATA%\SmoothLaunch` | Claude's original Start menu entry |
| | The registry, system settings or graphics drivers |

## How it works

When you open Claude Smooth, a hidden PowerShell script:

1. Finds Claude. It checks the Microsoft Store version first, then the usual install folders, then Windows' list of installed apps, then existing Start menu shortcuts.
2. Closes Claude if it's already running *without* the fix. Otherwise Windows would just switch to the existing laggy window.
3. Starts Claude with `--disable-gpu-compositing`. The Store version is started through Windows, the same way the Start menu does, so it keeps its package identity.

If Claude can't be found or won't start, a message box says why instead of failing silently.

## Things to know

- **The original entry stays in search.** Windows doesn't let anything edit the Start menu entries of Store apps, so Claude Smooth is added next to the original.
- **An open Claude will restart.** If Claude is already open normally, opening Claude Smooth closes and reopens it. Anything unsaved in it may be lost.
- **Your CPU works a bit harder.** On a laptop, that can cost some battery life while Claude is open.
- **Requirements:** Windows 10 or 11. On Windows 10 versions older than 2004 (May 2020), a PowerShell window flashes briefly when you open Claude Smooth. Some work or school PCs block PowerShell scripts entirely; this tool can't run on those.
- If `Install.cmd` says Claude was skipped even though you have it installed, please [open an issue](../../issues) and paste the summary.

This is an unofficial workaround and isn't affiliated with Anthropic. If Claude adds its own "disable hardware acceleration" setting, use that instead.

## License

[MIT](LICENSE)
