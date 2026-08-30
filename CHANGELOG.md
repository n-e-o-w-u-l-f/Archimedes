# Changelog

All notable changes to Archimedes are documented here.

## [Unreleased]

### Added
- Dependency-free two-column ANSI PowerShell TUI with arrow-key scrolling, PageUp/PageDown, Home/End, filtering, multi-select, and in-place cursor rendering.
- Data-driven distribution repository catalog loaded from `catalog/distributions.tsv`.
- Fifteen verified OpenWrt 24.10.8 Docker RootFS tags as architecture-specific catalog entries.
- Interactive browsing and classification of locally installed Docker images.
- Windows export-drive selection with free-space information and separate Docker data-root display.
- Independent interactive choices for Docker TAR, retained RootFS TAR, WSL2 import, and WSL2 export.
- Sequential multi-image execution queue with per-item status and continue-on-error behavior for interactive batches.
- PowerShell 7 runtime regression coverage and model tests for menu navigation, catalog, local Docker classification, storage and workflow state.
- Paginated POSIX and Fish source/local-image selection flows without third-party TUI dependencies.
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
- PowerShell interactive startup now uses the catalog/local-image wizard when source parameters are omitted; explicit CLI/non-interactive flows remain backward compatible.
- PowerShell frontend is packaged with `lib/` helpers and `catalog/`; installations must keep these paths beside `archimedes.ps1`.
- Local-image WSL eligibility is determined from Docker OS/architecture metadata and Linux userspace evidence rather than searching for a bundled kernel.
- WSL registration names are now separated from human-friendly display/artifact names and sanitized before `wsl --import`.
- Replaced the earlier single-purpose export loop with an interactive reusable CLI workflow.
- PowerShell no longer treats a stopped Docker daemon as an immediate `docker version` failure; expected probe failures are handled explicitly, including on Windows PowerShell 5.1.
- Pull mode resolves recognized shorthand distribution names before calling Docker while local/build modes keep user-defined tags unchanged.

### Fixed
- Fixed PowerShell 7 startup failure caused by colliding with the read-only automatic `$IsWindows` variable.
- Prevented two-column navigation from placing the active cursor on an empty cell.
- Removed `Clear-Host` from menu navigation and restore cursor visibility reliably after raw TUI exit.
- Fixed WSL `E_INVALIDARG` when a display name such as `Kali Linux` was passed directly as the WSL registration name.
- Fixed startup failure when the active context is `desktop-linux` but Docker Desktop has not been started yet.
- Fixed `NativeCommandError` during expected Docker daemon probes under Windows PowerShell 5.1 with `$ErrorActionPreference = 'Stop'`.
- Fixed `docker pull ubuntu26.04` being interpreted as a nonexistent repository instead of the official `ubuntu:26.04` image tag.

### Security
- Existing WSL distributions are never unregistered or overwritten automatically.
- Temporary Docker containers are removed after RootFS export.
