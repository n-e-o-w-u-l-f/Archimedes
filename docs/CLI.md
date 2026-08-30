# CLI Reference

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

## PowerShell

```text
-SourceMode pull|local|build
-Image <reference>
-BuildContext <path>
-Dockerfile <path>
-ExportMode image|rootfs|both|wsl|all
-ExportDirectory <path>
-DistributionName <name>
-WSLInstallDirectory <path>
-ImportToWSL
-Force
-NonInteractive
```

## POSIX shell

```text
--source pull|local|build
--image IMAGE[:TAG]
--context PATH
--dockerfile PATH
--export image|rootfs|both|wsl|all
--output PATH
--name NAME
--wsl-install PATH
--import-wsl
--force
--non-interactive
```

For a name such as `Debian-13`, possible output files are `Debian-13-docker-image.tar`, `Debian-13-rootfs.tar`, and `Debian-13-wsl.tar`.
