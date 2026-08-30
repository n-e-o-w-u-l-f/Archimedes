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
