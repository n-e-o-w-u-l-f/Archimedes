# Platform Support

| Platform | Docker exports | Dockerfile build | WSL2 import/export |
| --- | --- | --- | --- |
| Windows PowerShell | Yes | Yes | Yes |
| PowerShell 7 on Windows | Yes | Yes | Yes |
| Linux + POSIX shell | Yes | Yes | No |
| WSL + POSIX shell | Yes | Yes | Yes, through `wsl.exe` interoperability |
| macOS + POSIX shell | Yes | Yes | No |
| Fish on Linux/macOS | Yes | Yes | No |
| Fish inside WSL | Yes | Yes | Yes, when `wsl.exe` interoperability is available |

WSL support is runtime-detected. Archimedes does not emulate WSL commands on non-Windows hosts.

## Interactive UI behavior

PowerShell uses the dependency-free ANSI two-column TUI when raw console input and cursor positioning are available. If they are unavailable, it falls back to a numbered pager. POSIX shell and Fish use paginated menus and retain the same source/action semantics without requiring `fzf`, `Terminal.Gui`, or another TUI dependency.

Local Docker image WSL eligibility is based on Docker OS/architecture metadata and Linux userspace evidence. Docker images do not normally carry their own running kernel; containers use the Docker host kernel.
