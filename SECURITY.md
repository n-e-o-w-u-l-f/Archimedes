# Security Policy

Archimedes invokes local Docker and, on Windows, WSL commands with the permissions of the current user. It does not request or store Docker registry credentials itself.

Generated RootFS and WSL archives may contain secrets already present in the source image or later configuration, so treat exported archives as potentially sensitive artifacts.

Archimedes deliberately refuses to automatically unregister or replace existing WSL distributions.

Please report security-sensitive findings privately to the repository owner rather than publishing exploit details, credentials, private paths, or sensitive archive contents in a public issue.
