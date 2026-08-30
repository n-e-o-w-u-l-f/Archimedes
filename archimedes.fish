#!/usr/bin/env fish

set -g PROGRAM Archimedes
set -g VERSION 0.1.0

function die
    echo "ERROR: $argv" >&2
    exit 1
end

function ask
    set -l text $argv[1]
    set -l default $argv[2]
    if test -n "$default"
        read -P "$text [$default]: " value
        if test -z "$value"; set value $default; end
    else
        read -P "$text: " value
    end
    echo $value
end

function yes_no
    set -l text $argv[1]
    set -l default n
    if test (count $argv) -ge 2; set default $argv[2]; end
    while true
        if test "$default" = y; set suffix '[Y/n]'; else; set suffix '[y/N]'; end
        read -P "$text $suffix " answer
        if test -z "$answer"; set answer $default; end
        switch (string lower -- $answer)
            case y yes j ja
                return 0
            case n no nein
                return 1
        end
    end
end

function has_wsl
    type -q wsl.exe; and return 0
    test -x /mnt/c/Windows/System32/wsl.exe; and return 0
    return 1
end

function wsl_cmd
    if type -q wsl.exe
        wsl.exe $argv
    else
        /mnt/c/Windows/System32/wsl.exe $argv
    end
end

function winpath
    if type -q wslpath
        wslpath -w $argv[1]
    else if type -q cygpath
        cygpath -w $argv[1]
    else
        echo $argv[1]
    end
end

function safe_name
    echo $argv[1] | sed 's#^.*/##; s/[:@/\\[:space:]]/-/g; s/[^A-Za-z0-9._-]/-/g; s/--*/-/g; s/^[-.]*//; s/[-.]*$//'
end

function ensure_output
    set -l p $argv[1]
    if test -e "$p"
        yes_no "Overwrite '$p'?" n; or die "Cancelled because output exists: $p"
    end
end

function image_tar
    ensure_output $argv[2]
    docker save --output $argv[2] $argv[1]; or die 'docker save failed'
end

function rootfs_tar
    set -l image $argv[1]
    set -l output $argv[2]
    ensure_output "$output"
    set -l cid (docker create "$image" 2>/dev/null)
    if test -z "$cid"
        set cid (docker create "$image" /bin/sh); or die 'docker create failed'
    end
    docker export --output "$output" "$cid"; or begin; docker rm "$cid" >/dev/null 2>&1; die 'docker export failed'; end
    docker rm "$cid" >/dev/null; or true
end

if not type -q docker
    die 'Docker is required.'
end
docker version >/dev/null 2>&1; or die 'Docker daemon is not reachable.'

echo "$PROGRAM $VERSION"
echo 'Source: [1] pull [2] local image [3] Dockerfile build'
set source_choice (ask 'Select' 1)

switch $source_choice
    case 1
        echo 'Presets: [1] debian:13 [2] ubuntu:24.04 [3] ubuntu:26.04 [4] fedora:44 [5] alpine:3.22 [6] archlinux:latest [7] custom'
        set c (ask 'Select image' 1)
        switch $c
            case 1; set image debian:13
            case 2; set image ubuntu:24.04
            case 3; set image ubuntu:26.04
            case 4; set image fedora:44
            case 5; set image alpine:3.22
            case 6; set image archlinux:latest
            case 7; set image (ask 'Docker image reference' '')
            case '*'; die 'Invalid selection'
        end
        docker pull "$image"; or die 'docker pull failed'
    case 2
        set image (ask 'Local Docker image reference' '')
        docker image inspect "$image" >/dev/null; or die 'Local image does not exist'
    case 3
        set image (ask 'Tag for the new Docker image' 'archimedes/custom:latest')
        set context (ask 'Build context' .)
        set dockerfile (ask 'Dockerfile' "$context/Dockerfile")
        docker build --file "$dockerfile" --tag "$image" "$context"; or die 'docker build failed'
    case '*'
        die 'Invalid source selection'
end

set dist_name (safe_name "$image")
set export_dir (ask 'Export directory' "$PWD/exports")
mkdir -p "$export_dir"; or die 'Cannot create export directory'
set export_dir (cd "$export_dir"; and pwd)

echo 'Export: [1] Docker image tar [2] RootFS tar [3] both'
if has_wsl
    echo '        [4] WSL2 tar [5] all formats'
end
set mode (ask 'Select' 3)
set need_image 0
set need_rootfs 0
set need_wsl 0
set import_wsl 0
switch $mode
    case 1; set need_image 1
    case 2; set need_rootfs 1
    case 3; set need_image 1; set need_rootfs 1
    case 4; has_wsl; or die 'WSL2 unavailable'; set need_rootfs 1; set need_wsl 1; set import_wsl 1
    case 5; has_wsl; or die 'WSL2 unavailable'; set need_image 1; set need_rootfs 1; set need_wsl 1; set import_wsl 1
    case '*'; die 'Invalid export selection'
end

if has_wsl; and test $import_wsl -eq 0
    if yes_no 'Import RootFS into WSL2 afterwards?' n
        set import_wsl 1
        set need_rootfs 1
    end
end

set image_out "$export_dir/$dist_name-docker-image.tar"
set rootfs_out "$export_dir/$dist_name-rootfs.tar"
set wsl_out "$export_dir/$dist_name-wsl.tar"

test $need_image -eq 0; or image_tar "$image" "$image_out"
test $need_rootfs -eq 0; or rootfs_tar "$image" "$rootfs_out"

if test $import_wsl -eq 1
    set install_dir (ask 'WSL2 install directory' "$export_dir/wsl/$dist_name")
    if wsl_cmd --list --quiet 2>/dev/null | string replace -a '\r' '' | string match -qx "$dist_name"
        die "WSL distribution '$dist_name' already exists; refusing to overwrite it."
    end
    mkdir -p "$install_dir"; or die 'Cannot create WSL install directory'
    wsl_cmd --import "$dist_name" (winpath "$install_dir") (winpath "$rootfs_out") --version 2; or die 'WSL import failed'
end

if test $need_wsl -eq 1
    ensure_output "$wsl_out"
    wsl_cmd --export "$dist_name" (winpath "$wsl_out"); or die 'WSL export failed'
end

echo 'Completed.'
test $need_image -eq 0; or echo "Docker image: $image_out"
test $need_rootfs -eq 0; or echo "RootFS:       $rootfs_out"
test $need_wsl -eq 0; or echo "WSL2 export:  $wsl_out"
