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

script_dir(){ CDPATH= cd -- "$(dirname -- "$0")" && pwd; }
CATALOG_PATH="$(script_dir)/catalog/distributions.tsv"

catalog_count(){ awk 'NR>1 {n++} END {print n+0}' "$CATALOG_PATH"; }

select_catalog_image(){
    [ -f "$CATALOG_PATH" ] || die "Distribution catalog missing: $CATALOG_PATH"
    page=0; size=10
    while :; do
        total=$(catalog_count); pages=$(((total+size-1)/size)); [ "$pages" -gt 0 ] || pages=1
        say "Distribution / repository catalog - page $((page+1))/$pages"
        awk -F '\t' -v s=$((page*size+2)) -v e=$((page*size+size+1)) 'NR>=s&&NR<=e {printf "[%d] %-28s %s\n",NR-1,$2,$5}' "$CATALOG_PATH"
        choice=$(prompt 'Number, n=next, p=previous, q=back' '')
        case "$choice" in
            n|N) [ $((page+1)) -lt "$pages" ] && page=$((page+1));;
            p|P) [ "$page" -gt 0 ] && page=$((page-1));;
            q|Q) return 1;;
            *[!0-9]*|'') warn 'Invalid selection';;
            *) image=$(awk -F '\t' -v n="$choice" 'NR>1 {i++; if(i==n){print $5; exit}}' "$CATALOG_PATH"); [ -n "$image" ] && { printf '%s\n' "$image"; return 0; }; warn 'Invalid catalog number';;
        esac
    done
}

local_image_lines(){ docker image ls --format '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}' | awk -F '|' '$1 !~ /<none>/ {print}'; }

select_local_image(){
    tmp=${TMPDIR:-/tmp}/archimedes-images-$$; local_image_lines > "$tmp"; trap 'rm -f "$tmp"' EXIT INT TERM HUP
    total=$(wc -l < "$tmp" | tr -d ' '); [ "$total" -gt 0 ] || { rm -f "$tmp"; trap - EXIT INT TERM HUP; return 1; }
    page=0; size=10; pages=$(((total+size-1)/size))
    while :; do
        say "Locally installed Docker images - page $((page+1))/$pages"
        awk -F '|' -v s=$((page*size+1)) -v e=$((page*size+size)) 'NR>=s&&NR<=e {printf "[%d] %-52s %s\n",NR,$1,$3}' "$tmp"
        choice=$(prompt 'Number, n=next, p=previous, q=back' '')
        case "$choice" in
            n|N) [ $((page+1)) -lt "$pages" ] && page=$((page+1));;
            p|P) [ "$page" -gt 0 ] && page=$((page-1));;
            q|Q) rm -f "$tmp"; trap - EXIT INT TERM HUP; return 1;;
            *[!0-9]*|'') warn 'Invalid selection';;
            *) ref=$(awk -F '|' -v n="$choice" 'NR==n {print $1; exit}' "$tmp"); if [ -n "$ref" ]; then rm -f "$tmp"; trap - EXIT INT TERM HUP; printf '%s\n' "$ref"; return 0; fi; warn 'Invalid image number';;
        esac
    done
}

select_interactive_source(){
    while :; do
        say 'Source'; say '  [1] Distribution / repository catalog'; say '  [2] Locally installed Docker images'; say '  [3] Custom Docker image reference'; say '  [4] Build from Dockerfile'; say '  [5] Exit'
        case "$(prompt 'Select' '1')" in
            1) SOURCE_MODE=pull; IMAGE=$(select_catalog_image) || continue; return 0;;
            2) SOURCE_MODE=local; IMAGE=$(select_local_image) || continue; return 0;;
            3) SOURCE_MODE=pull; IMAGE=$(prompt 'Docker image reference' ''); [ -n "$IMAGE" ] && return 0;;
            4) SOURCE_MODE=build; IMAGE=$(prompt 'Image tag' 'archimedes/custom:latest'); return 0;;
            5) exit 0;;
            *) warn 'Invalid source selection';;
        esac
    done
}

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
  --wsl-name NAME
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

SOURCE_MODE=''; IMAGE=''; BUILD_CONTEXT='.'; DOCKERFILE=''; EXPORT_MODE=''; EXPORT_DIR=''; DIST_NAME=''; WSL_DIST_NAME=''; WSL_INSTALL_DIR=''; IMPORT_WSL=0; FORCE=0; NON_INTERACTIVE=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --source) SOURCE_MODE=$2; shift 2;; --image) IMAGE=$2; shift 2;; --context) BUILD_CONTEXT=$2; shift 2;; --dockerfile) DOCKERFILE=$2; shift 2;;
        --export) EXPORT_MODE=$2; shift 2;; --output) EXPORT_DIR=$2; shift 2;; --name) DIST_NAME=$2; shift 2;; --wsl-name) WSL_DIST_NAME=$2; shift 2;; --wsl-install) WSL_INSTALL_DIR=$2; shift 2;;
        --import-wsl) IMPORT_WSL=1; shift;; --force) FORCE=1; shift;; --non-interactive) NON_INTERACTIVE=1; shift;; -h|--help) usage; exit 0;; *) die "Unknown option: $1";;
    esac
done

require_cmd docker
docker version >/dev/null 2>&1 || die 'Docker daemon is not reachable.'

if [ -z "$SOURCE_MODE" ]; then
    [ "$NON_INTERACTIVE" -eq 0 ] || die '--source is required with --non-interactive'
    select_interactive_source
fi

case "$SOURCE_MODE" in
    pull)
        if [ -z "$IMAGE" ]; then [ "$NON_INTERACTIVE" -eq 0 ] || die '--image is required for source=pull'; IMAGE=$(select_catalog_image) || die 'No catalog image selected'; fi
        docker pull "$IMAGE";;
    local)
        [ -n "$IMAGE" ] || { [ "$NON_INTERACTIVE" -eq 0 ] && IMAGE=$(select_local_image) || die '--image is required'; }
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

needs_image=0; needs_rootfs=0; needs_wsl_export=0; keep_rootfs=0
if [ -z "$EXPORT_MODE" ]; then
    [ "$NON_INTERACTIVE" -eq 0 ] || die '--export is required with --non-interactive'
    yes_no 'Export Docker image archive?' y && needs_image=1
    yes_no 'Keep RootFS TAR?' y && { needs_rootfs=1; keep_rootfs=1; }
    if has_windows_wsl; then
        if yes_no 'Import RootFS into WSL2?' n; then IMPORT_WSL=1; needs_rootfs=1; fi
        if [ "$IMPORT_WSL" -eq 1 ] && yes_no 'Export imported WSL2 distribution TAR?' n; then needs_wsl_export=1; fi
    fi
    [ "$needs_image" -eq 1 ] || [ "$needs_rootfs" -eq 1 ] || [ "$IMPORT_WSL" -eq 1 ] || die 'No export/import action selected.'
else
    case "$EXPORT_MODE" in
        image) needs_image=1;;
        rootfs) needs_rootfs=1; keep_rootfs=1;;
        both) needs_image=1; needs_rootfs=1; keep_rootfs=1;;
        wsl) has_windows_wsl || die 'WSL unavailable'; needs_rootfs=1; keep_rootfs=1; needs_wsl_export=1; IMPORT_WSL=1;;
        all) has_windows_wsl || die 'WSL unavailable'; needs_image=1; needs_rootfs=1; keep_rootfs=1; needs_wsl_export=1; IMPORT_WSL=1;;
        *) die "Invalid export mode: $EXPORT_MODE";;
    esac
    if [ "$IMPORT_WSL" -eq 1 ]; then has_windows_wsl || die '--import-wsl is Windows/WSL only'; needs_rootfs=1; fi
fi

image_tar="$EXPORT_DIR/$DIST_NAME-docker-image.tar"; rootfs_tar="$EXPORT_DIR/$DIST_NAME-rootfs.tar"; wsl_tar="$EXPORT_DIR/$DIST_NAME-wsl.tar"
[ "$needs_image" -eq 0 ] || new_image_tar "$IMAGE" "$image_tar"
[ "$needs_rootfs" -eq 0 ] || new_rootfs_tar "$IMAGE" "$rootfs_tar"

if [ "$IMPORT_WSL" -eq 1 ]; then
    platform=$(docker image inspect --format '{{.Os}}|{{.Architecture}}' "$IMAGE") || die 'Unable to inspect image platform for WSL import.'
    image_os=${platform%%|*}; image_arch=${platform#*|}
    [ "$image_os" = linux ] || die "WSL import blocked: image OS is $image_os, not linux."
    host_arch=$(docker info --format '{{.Architecture}}' 2>/dev/null || true)
    [ -z "$host_arch" ] || [ "$image_arch" = "$host_arch" ] || die "WSL import blocked: image architecture $image_arch does not match Docker host $host_arch."
    requested_wsl_name=${WSL_DIST_NAME:-$DIST_NAME}
    WSL_DIST_NAME=$(safe_name "$requested_wsl_name")
    [ -n "$WSL_DIST_NAME" ] || WSL_DIST_NAME='Archimedes-WSL'
    [ "$WSL_DIST_NAME" = "$requested_wsl_name" ] || say "Resolved WSL distribution name: $requested_wsl_name -> $WSL_DIST_NAME"
    [ -n "$WSL_INSTALL_DIR" ] || { default_install="$EXPORT_DIR/wsl/$WSL_DIST_NAME"; if [ "$NON_INTERACTIVE" -eq 1 ]; then WSL_INSTALL_DIR=$default_install; else WSL_INSTALL_DIR=$(prompt 'WSL2 install directory' "$default_install"); fi; }
    import_wsl "$WSL_DIST_NAME" "$rootfs_tar" "$WSL_INSTALL_DIR"
    [ "$keep_rootfs" -eq 1 ] || rm -f "$rootfs_tar"
fi
[ "$needs_wsl_export" -eq 0 ] || export_wsl "$WSL_DIST_NAME" "$wsl_tar"

say 'Completed.'
[ "$needs_image" -eq 0 ] || say "Docker image: $image_tar"
[ "$keep_rootfs" -eq 0 ] || say "RootFS:       $rootfs_tar"
[ "$needs_wsl_export" -eq 0 ] || say "WSL2 export:  $wsl_tar"
[ "$IMPORT_WSL" -eq 0 ] || say "WSL2 name:    $WSL_DIST_NAME"
