# CLI Reference

## Interactive workflow

With no explicit source parameters, PowerShell opens the ANSI TUI. The source screen offers:

1. Distribution / repository catalog
2. Locally installed Docker images
3. Custom Docker image reference
4. Build from Dockerfile
5. Exit

Catalog and local-image screens support multi-select. The PowerShell TUI uses two columns with `Up/Down/Left/Right`, `PageUp/PageDown`, `Home/End`, `Space`, `Enter`, `Esc`, `A`, `N`, and `/` filtering. The active cell uses cyan background/black text; full-width header, navigation and footer bars use a blue ANSI background.

After source selection, Windows users choose a filesystem drive and output directory. This selects artifact/WSL paths only and never relocates Docker's global data store.

The action screen independently controls:

- Docker image archive (`docker save`)
- keeping a RootFS TAR (`docker export`)
- WSL2 import
- exporting the imported WSL2 distribution (`wsl --export`)

WSL import requires a RootFS, but the RootFS may be temporary when the user does not choose to keep it. Explicit `-ExportMode`/`--export` values retain their legacy mappings for automation.

## Source modes
- `pull`: pull from a Docker-compatible registry.
- `local`: use an image already present locally.
- `build`: build and tag an image from a Dockerfile.

## Export modes
- `image`: Docker image archive via `docker save`.
- `rootfs`: flattened container filesystem via `docker export`.
- `both`: image + RootFS.
- `wsl`: RootFS + WSL2 import + `wsl --export` (Windows only).
- `all`: all supported formats (Windows only).

## Docker daemon bootstrap

Archimedes checks the active Docker context with `docker info` before doing image work.

On Windows, when the Docker CLI is installed but no daemon is reachable, the PowerShell frontend attempts to start Docker Desktop automatically and waits for the engine to become ready. Current Docker Desktop versions are started through `docker desktop start`; an executable fallback is used for older installations when possible.

Use `-NoAutoStartDocker` when Archimedes must never start Docker Desktop automatically. The wait time defaults to 120 seconds and can be changed with `-DockerStartupTimeoutSeconds`.

## PowerShell

```text
-SourceMode pull|local|build
-Image <reference>
-BuildContext <path>
-Dockerfile <path>
-ExportMode image|rootfs|both|wsl|all
-ExportDirectory <path>
-DistributionName <display/artifact name>
-WSLDistributionName <WSL-safe internal name; optional>
-WSLInstallDirectory <path>
-ImportToWSL
-Force
-NonInteractive
-NoAutoStartDocker
-DockerStartupTimeoutSeconds <5..600>
```

Example:

```powershell
archimedes `
  -SourceMode pull `
  -Image debian:13 `
  -ExportMode both `
  -ExportDirectory 'B:\WSL2\' `
  -DistributionName 'Debian v13.6'
```

If Docker Desktop is stopped, Archimedes starts it automatically before pulling `debian:13`. Because the command is interactive unless `-NonInteractive` is supplied, Windows users are then asked whether the generated RootFS should also be imported into WSL2.

## POSIX shell

```text
--source pull|local|build
--image IMAGE[:TAG]
--context PATH
--dockerfile PATH
--export image|rootfs|both|wsl|all
--output PATH
--name NAME
--wsl-name NAME
--wsl-install PATH
--import-wsl
--force
--non-interactive
```

For a name such as `Debian-13`, possible output files are `Debian-13-docker-image.tar`, `Debian-13-rootfs.tar`, and `Debian-13-wsl.tar`.


WSL registration names are separate from human-friendly display/artifact names. `Kali Linux` is automatically registered as `Kali-Linux` unless an explicit WSL name is supplied.

## Package layout

`archimedes.ps1` loads helpers relative to its own directory. Deploy `archimedes.ps1`, `lib/`, and `catalog/` together. `archimedes.cmd` already launches the adjacent PowerShell script.
