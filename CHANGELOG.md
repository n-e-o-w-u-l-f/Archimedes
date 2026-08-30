# Changelog

All notable changes to Archimedes are documented here.

## [Unreleased]

### Added
- Interactive source selection: pull, local image, or Dockerfile build.
- Interactive export-format selection.
- User-defined export directory.
- Docker image archive export via `docker save`.
- Container RootFS export via `docker export`.
- Optional WSL2 import on Windows.
- Optional WSL2 distribution archive via `wsl --export`.
- PowerShell, POSIX shell, Fish shell, and Windows CMD frontends.
- Non-interactive PowerShell and POSIX-shell operation.
- Initial Linux image preset catalog.

### Changed
- Replaced the earlier single-purpose export loop with an interactive reusable CLI workflow.

### Security
- Existing WSL distributions are never unregistered or overwritten automatically.
- Temporary Docker containers are removed after RootFS export.
