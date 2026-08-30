#!/bin/sh
set -eu
sh -n ./archimedes.sh
if command -v bash >/dev/null 2>&1; then bash -n ./archimedes.sh; fi
grep -q 'Locally installed Docker images' ./archimedes.sh
grep -q 'Export Docker image archive' ./archimedes.sh
grep -q 'Import RootFS into WSL2' ./archimedes.sh
echo 'PASS POSIX menu smoke'
