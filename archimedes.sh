#!/bin/sh
set -eu

PROGRAM="Archimedes"
VERSION="0.1.0"

say(){ printf '%s\n' "$*"; }
warn(){ printf 'WARNING: %s\n' "$*" >&2; }
die(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
require_cmd(){ command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

is_wsl(){
    [ -n "${WSL_INTEROP:-}" ] && return 0
    [ -r /proc/version ] && grep -qiE '(microsoft|wsl)' /proc/version && return 0
    return 1
}

has_windows_wsl(){
    command -v wsl.exe >/dev/null 2>&1 && return 0
    is_wsl && [ -x /mnt/c/Windows/System32/wsl.exe ] && return 0
    return 1
}

wsl_cmd(){
    if command -v wsl.exe >/dev/null 2>&1; then wsl.exe "$@"; else /mnt/c/Windows/System32/wsl.exe "$@"; fi
}

to_windows_path(){
    if command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"
    elif command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"
    else printf '%s\n' "$1"; fi
}

prompt(){
    text=$1; default=${2:-}
    if [ -n "$default" ]; then printf '%s [%s]: ' "$text" "$default" >&2; else printf '%s: ' "$text" >&2; fi
    IFS= read -r answer || answer=''
    [ -n "$answer" ] || answer=$default
    printf '%s\n' "$answer"
}

yes_no(){
    text=$1; default=${2:-n}
    while :; do
        if [ "$default" = y ]; then suffix='[Y/n]'; else suffix='[y/N]'; fi
        printf '%s %s ' "$text" "$suffix" >&2
        IFS= read -r answer || answer=''
        [ -n "$answer" ] || answer=$default
        case "$answer" in y|Y|yes|YES|Yes|j|J|ja|JA|Ja) return 0;; n|N|no|NO|No|nein|NEIN|Nein) return 1;; *) warn 'Please answer yes or no.';; esac
    done
}

safe_name(){ printf '%s' "$1" | sed 's#^.*/##; s/[:@/\\[:space:]]/-/g; s/[^A-Za-z0-9._-]/-/g; s/--*/-/g; s/^[-.]*//; s/[-.]*$//'; }

ensure_output(){
    path=$1
    if [ -e "$path" ] && [ "${FORCE:-0}" -ne 1 ]; then
        [ "${NON_INTERACTIVE:-0}" -eq 0 ] || die "Output already exists: $path (use --force)"
        yes_no "Overwrite '$path'?" n || die "Cancelled because output exists: $path"
    fi
}

new_image_tar(){ ensure_output "$2"; docker save --output "$2" "$1"; }

new_rootfs_tar(){
    image=$1; output=$2; ensure_output "$output"; cid=''
    cid=$(docker create "$image" 2>/dev/null || true)
    [ -n "$cid" ] || cid=$(docker create "$image" /bin/sh)
    [ -n "$cid" ] || die "Docker did not return a container ID for $image"
    trap 'docker rm "$cid" >/dev/null 2>&1 || true' EXIT INT TERM HUP
    docker export --output "$output" "$cid"
    docker rm "$cid" >/dev/null; cid=''; trap - EXIT INT TERM HUP
}

wsl_names(){ wsl_cmd --list --quiet 2>/dev/null | tr -d '\r'; }

import_wsl(){
    name=$1; rootfs=$2; install_dir=$3
    has_windows_wsl || die 'WSL2 import is available only on Windows/WSL with wsl.exe interop.'
    wsl_names | grep -Fx "$name" >/dev/null 2>&1 && die "WSL distribution '$name' already exists. Refusing to overwrite it."
    mkdir -p "$install_dir"
    wsl_cmd --import "$name" "$(to_windows_path "$install_dir")" "$(to_windows_path "$rootfs")" --version 2
}

export_wsl(){ ensure_output "$2"; wsl_cmd --export "$1" "$(to_windows_path "$2")"; }

usage(){
cat <<EOF
$PROGRAM $VERSION

Usage: ./archimedes.sh [options]

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
  -h, --help

Export types:
  image   Docker image archive (.tar), restore with docker load
  rootfs  Flat container filesystem (.tar), usable with docker import or WSL2 import
  both    image + rootfs
  wsl     rootfs + WSL2 import + wsl --export (Windows/WSL only)
  all     image + rootfs + WSL2 archive (Windows/WSL only)
EOF
}

SOURCE_MODE=''; IMAGE=''; BUILD_CONTEXT='.'; DOCKERFILE=''; EXPORT_MODE=''; EXPORT_DIR=''; DIST_NAME=''; WSL_INSTALL_DIR=''; IMPORT_WSL=0; FORCE=0; NON_INTERACTIVE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) SOURCE_MODE=$2; shift 2;; --image) IMAGE=$2; shift 2;; --context) BUILD_CONTEXT=$2; shift 2;; --dockerfile) DOCKERFILE=$2; shift 2;;
        --export) EXPORT_MODE=$2; shift 2;; --output) EXPORT_DIR=$2; shift 2;; --name) DIST_NAME=$2; shift 2;; --wsl-install) WSL_INSTALL_DIR=$2; shift 2;;
        --import-wsl) IMPORT_WSL=1; shift;; --force) FORCE=1; shift;; --non-interactive) NON_INTERACTIVE=1; shift;; -h|--help) usage; exit 0;; *) die "Unknown option: $1";;
    esac
done

require_cmd docker
docker version >/dev/null 2>&1 || die 'Docker daemon is not reachable.'

if [ -z "$SOURCE_MODE" ]; then
    [ "$NON_INTERACTIVE" -eq 0 ] || die '--source is required with --non-interactive'
    say 'How should the Docker image be obtained?'; say '  [1] Pull from registry'; say '  [2] Use local image'; say '  [3] Build from Dockerfile'
    case "$(prompt 'Select' '1')" in 1) SOURCE_MODE=pull;; 2) SOURCE_MODE=local;; 3) SOURCE_MODE=build;; *) die 'Invalid source selection';; esac
fi

case "$SOURCE_MODE" in
    pull)
        if [ -z "$IMAGE" ]; then
            [ "$NON_INTERACTIVE" -eq 0 ] || die '--image is required for source=pull'
            say 'Presets: [1] debian:13 [2] ubuntu:24.04 [3] ubuntu:26.04 [4] fedora:44 [5] alpine:3.22 [6] archlinux:latest [7] Rocky 10 [8] Alma 10 [9] Kali [10] openSUSE Tumbleweed [11] custom'
            case "$(prompt 'Select image' '1')" in
                1) IMAGE='debian:13';; 2) IMAGE='ubuntu:24.04';; 3) IMAGE='ubuntu:26.04';; 4) IMAGE='fedora:44';; 5) IMAGE='alpine:3.22';; 6) IMAGE='archlinux:latest';;
                7) IMAGE='rockylinux/rockylinux:10';; 8) IMAGE='almalinux:10';; 9) IMAGE='kalilinux/kali-rolling:latest';; 10) IMAGE='opensuse/tumbleweed:latest';; 11) IMAGE=$(prompt 'Docker image reference' '');; *) die 'Invalid image selection';;
            esac
        fi
        docker pull "$IMAGE";;
    local)
        [ -n "$IMAGE" ] || { [ "$NON_INTERACTIVE" -eq 0 ] && IMAGE=$(prompt 'Local Docker image reference' '') || die '--image is required'; }
        docker image inspect "$IMAGE" >/dev/null;;
    build)
        [ -n "$IMAGE" ] || { [ "$NON_INTERACTIVE" -eq 0 ] && IMAGE=$(prompt 'Tag for the new Docker image' 'archimedes/custom:latest') || die '--image is required'; }
        [ -n "$DOCKERFILE" ] || DOCKERFILE="$BUILD_CONTEXT/Dockerfile"
        [ -d "$BUILD_CONTEXT" ] || die "Build context missing: $BUILD_CONTEXT"; [ -f "$DOCKERFILE" ] || die "Dockerfile missing: $DOCKERFILE"
        docker build --file "$DOCKERFILE" --tag "$IMAGE" "$BUILD_CONTEXT";;
    *) die "Invalid source mode: $SOURCE_MODE";;
esac

[ -n "$DIST_NAME" ] || DIST_NAME=$(safe_name "$IMAGE"); [ -n "$DIST_NAME" ] || DIST_NAME='archimedes-export'
if [ -z "$EXPORT_DIR" ]; then default_dir=$(pwd)/exports; if [ "$NON_INTERACTIVE" -eq 1 ]; then EXPORT_DIR=$default_dir; else EXPORT_DIR=$(prompt 'Export directory' "$default_dir"); fi; fi
mkdir -p "$EXPORT_DIR"; EXPORT_DIR=$(cd "$EXPORT_DIR" && pwd)

if [ -z "$EXPORT_MODE" ]; then
    [ "$NON_INTERACTIVE" -eq 0 ] || die '--export is required with --non-interactive'
    say 'Export: [1] Docker image tar [2] RootFS tar [3] both'; has_windows_wsl && say '        [4] WSL2 tar [5] all formats'
    case "$(prompt 'Select' '3')" in 1) EXPORT_MODE=image;; 2) EXPORT_MODE=rootfs;; 3) EXPORT_MODE=both;; 4) has_windows_wsl || die 'WSL unavailable'; EXPORT_MODE=wsl;; 5) has_windows_wsl || die 'WSL unavailable'; EXPORT_MODE=all;; *) die 'Invalid export selection';; esac
fi

needs_image=0; needs_rootfs=0; needs_wsl_export=0
case "$EXPORT_MODE" in image) needs_image=1;; rootfs) needs_rootfs=1;; both) needs_image=1; needs_rootfs=1;; wsl) has_windows_wsl || die 'WSL unavailable'; needs_rootfs=1; needs_wsl_export=1; IMPORT_WSL=1;; all) has_windows_wsl || die 'WSL unavailable'; needs_image=1; needs_rootfs=1; needs_wsl_export=1; IMPORT_WSL=1;; *) die "Invalid export mode: $EXPORT_MODE";; esac

if [ "$IMPORT_WSL" -eq 1 ]; then has_windows_wsl || die '--import-wsl is Windows/WSL only'; needs_rootfs=1
elif has_windows_wsl && [ "$NON_INTERACTIVE" -eq 0 ] && [ "$needs_wsl_export" -eq 0 ]; then yes_no 'Import RootFS into WSL2 afterwards?' n && { IMPORT_WSL=1; needs_rootfs=1; }
fi

image_tar="$EXPORT_DIR/$DIST_NAME-docker-image.tar"; rootfs_tar="$EXPORT_DIR/$DIST_NAME-rootfs.tar"; wsl_tar="$EXPORT_DIR/$DIST_NAME-wsl.tar"
[ "$needs_image" -eq 0 ] || new_image_tar "$IMAGE" "$image_tar"
[ "$needs_rootfs" -eq 0 ] || new_rootfs_tar "$IMAGE" "$rootfs_tar"

if [ "$IMPORT_WSL" -eq 1 ]; then
    [ -n "$WSL_INSTALL_DIR" ] || { default_install="$EXPORT_DIR/wsl/$DIST_NAME"; if [ "$NON_INTERACTIVE" -eq 1 ]; then WSL_INSTALL_DIR=$default_install; else WSL_INSTALL_DIR=$(prompt 'WSL2 install directory' "$default_install"); fi; }
    import_wsl "$DIST_NAME" "$rootfs_tar" "$WSL_INSTALL_DIR"
fi
[ "$needs_wsl_export" -eq 0 ] || export_wsl "$DIST_NAME" "$wsl_tar"

say 'Completed.'
[ "$needs_image" -eq 0 ] || say "Docker image: $image_tar"
[ "$needs_rootfs" -eq 0 ] || say "RootFS:       $rootfs_tar"
[ "$needs_wsl_export" -eq 0 ] || say "WSL2 export:  $wsl_tar"
