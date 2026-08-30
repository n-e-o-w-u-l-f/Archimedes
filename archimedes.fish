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
    read -P "$text [$default]: " value
    if test -z "$value"; set value $default; end
    echo $value
end
function yes_no
    set -l default n
    if test (count $argv) -ge 2; set default $argv[2]; end
    set -l suffix '[y/N]'
    if test "$default" = y; set suffix '[Y/n]'; end
    read -P "$argv[1] $suffix " v
    if test -z "$v"; set v $default; end
    switch (string lower -- $v)
        case y yes j ja; return 0
        case '*'; return 1
    end
end
function has_wsl
    type -q wsl.exe; and return 0
    test -x /mnt/c/Windows/System32/wsl.exe; and return 0
    return 1
end
function wsl_cmd
    if type -q wsl.exe; wsl.exe $argv
    else; /mnt/c/Windows/System32/wsl.exe $argv
    end
end
function winpath
    if type -q wslpath; wslpath -w $argv[1]
    else if type -q cygpath; cygpath -w $argv[1]
    else; echo $argv[1]
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
function rootfs_tar
    set image $argv[1]; set out $argv[2]
    set cid (docker create "$image" 2>/dev/null)
    if test -z "$cid"; set cid (docker create "$image" /bin/sh); or die 'docker create failed'; end
    docker export --output "$out" "$cid"; or begin
        docker rm "$cid" >/dev/null 2>&1
        die 'docker export failed'
    end
    docker rm "$cid" >/dev/null; or true
end

set script_root (dirname (status --current-filename))
set catalog "$script_root/catalog/distributions.tsv"
function select_catalog_image
    test -f "$catalog"; or die "Distribution catalog missing: $catalog"
    set page 0; set size 10
    set total (count (tail -n +2 "$catalog"))
    set pages (math "($total + $size - 1) / $size")
    if test $pages -lt 1; set pages 1; end
    while true
        echo "Distribution / repository catalog - page "(math $page + 1)"/$pages"
        set start (math $page \* $size + 2); set stop (math $start + $size - 1)
        awk -F '\t' -v s=$start -v e=$stop 'NR>=s&&NR<=e {printf "[%d] %-28s %s\n",NR-1,$2,$5}' "$catalog"
        set choice (ask 'Number, n=next, p=previous, q=back' '')
        switch $choice
            case n N; if test (math $page + 1) -lt $pages; set page (math $page + 1); end
            case p P; if test $page -gt 0; set page (math $page - 1); end
            case q Q; return 1
            case '*'
                if string match -qr '^[0-9]+$' -- $choice
                    set image (awk -F '\t' -v n=$choice 'NR>1 {i++; if(i==n){print $5; exit}}' "$catalog")
                    if test -n "$image"; echo $image; return 0; end
                end
                echo 'Invalid catalog selection.' >&2
        end
    end
end
function select_local_image
    set tmp (mktemp); or return 1
    docker image ls --format '{{.Repository}}:{{.Tag}}|{{.ID}}|{{.Size}}' | awk -F '|' '$1 !~ /<none>/ {print}' > "$tmp"
    set total (count (cat "$tmp"))
    if test $total -eq 0; rm -f "$tmp"; return 1; end
    set page 0; set size 10; set pages (math "($total + $size - 1) / $size")
    while true
        echo "Locally installed Docker images - page "(math $page + 1)"/$pages"
        set start (math $page \* $size + 1); set stop (math $start + $size - 1)
        awk -F '|' -v s=$start -v e=$stop 'NR>=s&&NR<=e {printf "[%d] %-52s %s\n",NR,$1,$3}' "$tmp"
        set choice (ask 'Number, n=next, p=previous, q=back' '')
        switch $choice
            case n N; if test (math $page + 1) -lt $pages; set page (math $page + 1); end
            case p P; if test $page -gt 0; set page (math $page - 1); end
            case q Q; rm -f "$tmp"; return 1
            case '*'
                if string match -qr '^[0-9]+$' -- $choice
                    set ref (awk -F '|' -v n=$choice 'NR==n {print $1; exit}' "$tmp")
                    if test -n "$ref"; rm -f "$tmp"; echo $ref; return 0; end
                end
                echo 'Invalid image selection.' >&2
        end
    end
end
type -q docker; or die 'Docker is required'
docker version >/dev/null 2>&1; or die 'Docker daemon unavailable'
while true
    echo 'Source'
    echo '  [1] Distribution / repository catalog'
    echo '  [2] Locally installed Docker images'
    echo '  [3] Custom Docker image reference'
    echo '  [4] Build from Dockerfile'
    echo '  [5] Exit'
    set source_choice (ask Select 1)
    switch $source_choice
        case 1
            set source_mode pull; set image (select_catalog_image); or continue
        case 2
            set source_mode local; set image (select_local_image); or continue
        case 3
            set source_mode pull; set image (ask 'Docker image reference' '')
            if test -z "$image"; continue; end
        case 4
            set source_mode build; set image (ask 'Image tag' 'archimedes/custom:latest')
            set context (ask 'Build context' .); set df (ask Dockerfile "$context/Dockerfile")
        case 5
            exit 0
        case '*'
            echo 'Invalid source.' >&2; continue
    end
    break
end

switch $source_mode
    case pull
        docker pull "$image"; or die 'pull failed'
    case local
        docker image inspect "$image" >/dev/null; or die 'image missing'
    case build
        docker build -f "$df" -t "$image" "$context"; or die 'build failed'
end

set name (safe_name "$image")
set out (ask 'Export directory' "$PWD/exports")
mkdir -p "$out"; or die 'cannot create output'
set out (cd "$out"; and pwd)
set export_image 0; set needs_rootfs 0; set keep_rootfs 0; set import_wsl 0; set export_wsl 0
if yes_no 'Export Docker image archive?' y; set export_image 1; end
if yes_no 'Keep RootFS TAR?' y; set needs_rootfs 1; set keep_rootfs 1; end
if has_wsl
    if yes_no 'Import RootFS into WSL2?' n; set import_wsl 1; set needs_rootfs 1; end
    if test $import_wsl -eq 1; and yes_no 'Export imported WSL2 distribution TAR?' n; set export_wsl 1; end
end
if test $export_image -eq 0; and test $needs_rootfs -eq 0; and test $import_wsl -eq 0
    die 'No export/import action selected.'
end

set image_tar "$out/$name-docker-image.tar"
set rootfs_tar "$out/$name-rootfs.tar"
set wsl_tar "$out/$name-wsl.tar"
if test $export_image -eq 1
    docker save --output "$image_tar" "$image"; or die 'docker save failed'
end
if test $needs_rootfs -eq 1
    rootfs_tar "$image" "$rootfs_tar"
end

if test $import_wsl -eq 1
    set platform (docker image inspect --format '{{.Os}}|{{.Architecture}}' "$image"); or die 'image platform inspect failed'
    set fields (string split '|' -- $platform)
    test "$fields[1]" = linux; or die "WSL import blocked: image OS is $fields[1], not linux."
    set host_arch (docker info --format '{{.Architecture}}' 2>/dev/null)
    if test -n "$host_arch"; and test "$fields[2]" != "$host_arch"
        die "WSL import blocked: image architecture $fields[2] does not match Docker host $host_arch."
    end
    if wsl_cmd --list --quiet 2>/dev/null | string replace -a '\r' '' | string match -qx "$name"
        die "WSL '$name' already exists"
    end
    set wsl_dir (ask 'WSL install directory' "$out/wsl/$name")
    mkdir -p "$wsl_dir"; or die 'cannot create WSL directory'
    wsl_cmd --import "$name" (winpath "$wsl_dir") (winpath "$rootfs_tar") --version 2; or die 'WSL import failed'
    if test $export_wsl -eq 1
        wsl_cmd --export "$name" (winpath "$wsl_tar"); or die 'WSL export failed'
    end
    if test $keep_rootfs -eq 0; rm -f "$rootfs_tar"; end
end

echo 'Completed.'
if test $export_image -eq 1; echo "Docker image: $image_tar"; end
if test $keep_rootfs -eq 1; echo "RootFS:       $rootfs_tar"; end
if test $export_wsl -eq 1; echo "WSL2 export:  $wsl_tar"; end
if test $import_wsl -eq 1; echo "WSL2 name:    $name"; end
