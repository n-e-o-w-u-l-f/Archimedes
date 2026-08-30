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
- Windows Docker daemon preflight based on `docker info`.
- Automatic Docker Desktop startup on Windows when the Docker CLI is installed but its daemon is not reachable.
- `-NoAutoStartDocker` to opt out of automatic Docker Desktop startup.
- `-DockerStartupTimeoutSeconds` to control how long Archimedes waits for Docker Desktop.
- Regression smoke test for the stopped-Docker-Desktop startup path.
- Friendly Docker image reference normalization for common Linux distributions, e.g. `ubuntu26.04` -> `ubuntu:26.04`.
- Regression coverage for friendly image reference normalization.

### Changed
- WSL registration names are now separated from human-friendly display/artifact names and sanitized before `wsl --import`.
- Replaced the earlier single-purpose export loop with an interactive reusable CLI workflow.
- PowerShell no longer treats a stopped Docker daemon as an immediate `docker version` failure; expected probe failures are handled explicitly, including on Windows PowerShell 5.1.
- Pull mode resolves recognized shorthand distribution names before calling Docker while local/build modes keep user-defined tags unchanged.

### Fixed
- Fixed WSL `E_INVALIDARG` when a display name such as `Kali Linux` was passed directly as the WSL registration name.
- Fixed startup failure when the active context is `desktop-linux` but Docker Desktop has not been started yet.
- Fixed `NativeCommandError` during expected Docker daemon probes under Windows PowerShell 5.1 with `$ErrorActionPreference = 'Stop'`.
- Fixed `docker pull ubuntu26.04` being interpreted as a nonexistent repository instead of the official `ubuntu:26.04` image tag.

### Security
- Existing WSL distributions are never unregistered or overwritten automatically.
- Temporary Docker containers are removed after RootFS export.
