# Contributing to Archimedes

Contributions are welcome when they keep the CLI predictable, cross-platform, and non-destructive.

## Development principles

1. Keep Docker image archives, RootFS archives, and WSL2 exports semantically separate.
2. Do not introduce destructive WSL operations as automatic behavior.
3. Keep the PowerShell and POSIX-shell feature sets aligned where the underlying platform permits it.
4. Avoid mandatory dependencies when a standard Docker/OS tool is sufficient.
5. Treat Windows-only features as optional capabilities rather than universal assumptions.
6. Validate shell syntax before submitting changes.

## Pull requests

A pull request should explain what changed, which shells/platforms were tested, whether export compatibility changed, and whether any new dependency was introduced.

Internal agent prompts, handoff files, private orchestration documents, private paths, tokens, credentials, or private workflow material must never be submitted to this public repository.
