# Export Formats

## Docker image archive

Created with `docker save`. It preserves Docker image metadata, layers, and tags and can be restored with `docker load`. It is not a WSL RootFS archive.

## Container RootFS archive

Created from a temporary container with `docker export`. It is a flattened filesystem archive suitable for `docker import` and for Archimedes' WSL2 import path.

Container runtime metadata, image layers, volumes, and image history are not preserved by `docker export`.

## WSL2 distribution archive

On Windows, after a RootFS is imported as a WSL2 distribution, Archimedes can create a WSL-native archive using `wsl --export`.

The three archive types are intentionally named differently because they are not interchangeable.
