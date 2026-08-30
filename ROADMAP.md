# Roadmap

## Near term
- Keep PowerShell and POSIX-shell behavior feature-equivalent.
- Extend automated syntax and real Docker/WSL smoke coverage across more hosts.
- Continue expanding the validated data-driven distribution/image catalog as upstream tags change.
- Add checksums and optional manifest generation for exported artifacts.
- Improve WSL2 post-import validation.
- Add structured/non-interactive output for CI and build-runner integration.

## Later
- Pluggable image catalogs.
- Optional OCI archive/layout export where supported by installed tooling.
- RootFS metadata manifests.
- Extend platform-aware pulls/emulation support beyond the current compatibility guardrails.
- Import/export adapters for additional container engines where semantics are compatible.

VM-oriented systems such as BSD, Solaris, DOS, macOS and OS/2 remain separate runner classes instead of being forced through Docker-to-WSL workflows.
