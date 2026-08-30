# Archimedes

Archimedes is an interactive, cross-platform CLI toolkit for selecting Docker/Linux repositories or locally installed Docker images, turning them into portable `.tar` artifacts and, on Windows, optional WSL2 distributions.

It can pull an image from a registry, reuse a local image, or build one from a Dockerfile. The CLI then asks which export format you want, where the files should be written, and whether a generated RootFS should be imported into WSL2 when WSL is available.

## Export formats

| Artifact | Created with | Intended use |
| --- | --- | --- |
| Docker image archive | `docker save` | Preserve image layers/tags; restore with `docker load` |
| RootFS archive | `docker export` | Flat filesystem; use with `docker import` or `wsl --import` |
| WSL2 distribution archive | `wsl --export` | Windows-only backup/export of an imported WSL2 distribution |

These formats are intentionally kept separate because they are not interchangeable.

## Supported shells

- Windows PowerShell 5.1 and PowerShell 7+: `archimedes.ps1`
- Windows command prompt launcher: `archimedes.cmd`
- POSIX shell: `archimedes.sh` (works with `sh`, Bash, Dash, Ksh and can be invoked from Zsh)
- Fish shell: `archimedes.fish`

The POSIX and Fish versions can optionally call `wsl.exe` when they are running inside WSL or another Windows shell environment with WSL interoperability. On ordinary Linux/macOS they remain Docker-only.

## Requirements

- Docker CLI and a reachable Docker daemon
- For WSL2 import/export: Windows with WSL2 and `wsl.exe`
- For Dockerfile builds: a valid Docker build context

On Windows, the PowerShell frontend checks the Docker daemon with `docker info`. If Docker Desktop is installed but stopped, Archimedes attempts to start it automatically and waits for the engine before continuing. Use `-NoAutoStartDocker` to disable this behavior or `-DockerStartupTimeoutSeconds` to change the default 120-second wait.

No automatic `wsl --unregister`, destructive cleanup, or replacement of an existing WSL distribution is performed.

WSL registration names are sanitized separately from display/artifact names. For example, `-DistributionName 'Kali Linux'` keeps readable archive names while WSL is registered as `Kali-Linux`. PowerShell can override this with `-WSLDistributionName`; the POSIX frontend provides `--wsl-name`.

## Interactive TUI

Running `archimedes` without explicit source parameters opens the interactive workflow:

```text
Source -> Catalog / local Docker images / custom / build
       -> Select one or more images
       -> Choose export drive/directory
       -> Choose Docker TAR / RootFS / WSL2 actions
       -> Execute queue
       -> Summary
```

The PowerShell frontend uses the Archimedes ANSI TUI: blue full-width header/navigation/footer bars, a normal terminal background for the list, and a cyan/black active cell. Repository and local-image lists use two columns and never place the cursor on an empty cell.

Keys: `Up`, `Down`, `Left`, `Right`, `PageUp`, `PageDown`, `Home`, `End`, `Space`, `Enter`, `Esc`, `A`, `N`, and `/` for filtering. Cursor movement is rendered in place; Archimedes does not clear the whole terminal for every keypress. A numbered pager is used when raw console input is unavailable.

The POSIX and Fish frontends provide a dependency-free paginated equivalent rather than requiring a third-party TUI framework.

## Installation layout

The PowerShell frontend is now a small package rather than a standalone script. Keep these paths together:

```text
Archimedes/
├── archimedes.ps1
├── archimedes.cmd
├── lib/
│   ├── Archimedes.Console.ps1
│   ├── Archimedes.Catalog.ps1
│   ├── Archimedes.Docker.ps1
│   ├── Archimedes.Storage.ps1
│   └── Archimedes.Workflow.ps1
└── catalog/
    └── distributions.tsv
```

If `archimedes` is exposed through a PowerShell profile function/alias, point that wrapper at `Archimedes\archimedes.ps1`; do not copy only `archimedes.ps1` away from its `lib/` and `catalog/` directories.

## Quick start

### PowerShell

```powershell
./archimedes.ps1
```

```powershell
./archimedes.ps1 `
  -SourceMode pull `
  -Image debian:13 `
  -ExportMode both `
  -ExportDirectory 'B:\Backup\WSL2\Build-Runner\Exports' `
  -DistributionName Debian-13 `
  -NonInteractive
```

Docker RootFS plus WSL2 import:

```powershell
./archimedes.ps1 `
  -SourceMode pull `
  -Image ubuntu:26.04 `
  -ExportMode rootfs `
  -ExportDirectory 'B:\Backup\WSL2\Build-Runner\Exports' `
  -DistributionName Ubuntu-26.04 `
  -ImportToWSL
```

A user-defined display name may contain spaces:

```powershell
archimedes `
  -SourceMode pull `
  -Image debian:13 `
  -ExportMode both `
  -ExportDirectory 'B:\WSL2\' `
  -DistributionName 'Debian v13.6'
```

When Docker Desktop is stopped, Archimedes starts it before the pull. Without `-NonInteractive`, Windows then asks whether the RootFS should also be imported into WSL2.

### Bash / POSIX shell

```sh
./archimedes.sh
```

```sh
./archimedes.sh \
  --source pull \
  --image debian:13 \
  --export both \
  --output "$HOME/archimedes-exports" \
  --name Debian-13 \
  --non-interactive
```

### Fish

```fish
./archimedes.fish
```

The Fish frontend is intentionally interactive in the initial release.

## Image sources

The interactive frontends load their Linux repository choices from [`catalog/distributions.tsv`](catalog/distributions.tsv) instead of a hardcoded preset switch. The catalog includes the currently verified OpenWrt 24.10.8 Docker RootFS tags as architecture-specific entries. Any Docker-compatible image reference can also be entered manually.

Locally installed Docker images can be browsed directly. Archimedes inspects Docker OS/architecture metadata and, when useful, `/etc/os-release` from a temporary stopped container. Windows images are blocked from WSL import; architecture mismatches are surfaced instead of being silently treated as runnable.

Choosing another export drive changes artifact and WSL install paths only. It does not relocate Docker Desktop's global image store; the PowerShell TUI shows Docker's reported data root separately.

Archimedes does not pretend that every operating system is a Docker/WSL target. BSD, Solaris/illumos, DOS, macOS, OS/2 and other VM-oriented systems require different runners and are outside the Docker-to-WSL path.

## Safety model

Archimedes:

- refuses to overwrite export files unless explicitly allowed;
- refuses to overwrite an existing WSL distribution;
- never unregisters WSL distributions automatically;
- removes only temporary containers created for RootFS export;
- keeps Docker-image archives and RootFS archives clearly named and separate.

## Documentation

- [CLI reference](docs/CLI.md)
- [Export formats](docs/EXPORT_FORMATS.md)
- [Platform support](docs/PLATFORMS.md)
- [Roadmap](ROADMAP.md)
- [Security policy](SECURITY.md)
- [Contributing](CONTRIBUTING.md)
