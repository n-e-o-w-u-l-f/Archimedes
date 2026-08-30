$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib/Archimedes.Catalog.ps1')
$c=Import-ArchimedesCatalog (Join-Path $root 'catalog/distributions.tsv')
if($c.Count -lt 25){throw "Catalog unexpectedly small: $($c.Count)"}
$u=Resolve-ArchimedesCatalogAlias $c 'ubuntu26.04'
if(-not $u -or $u.Image -ne 'ubuntu:26.04'){throw 'Ubuntu alias failed'}
$k=Resolve-ArchimedesCatalogAlias $c 'Kali Linux'
if(-not $k -or $k.Image -ne 'kalilinux/kali-rolling:latest'){throw 'Kali alias failed'}
$ow=@($c|Where-Object Family -eq 'openwrt')
if($ow.Count -ne 15){throw "Expected 15 OpenWrt 24.10.8 Docker rootfs tags, got $($ow.Count)"}
$bad=@($ow|Where-Object {$_.Image -notmatch '^openwrt/rootfs:.+-24\.10\.8$'})
if($bad.Count){throw 'OpenWrt catalog contains a non-concrete 24.10.8 image tag'}
if(@($ow|Where-Object Image -match 'mipsel_24kc|riscv64_riscv64').Count){throw 'Catalog contains unpublished 24.10.8 Docker tags'}
Write-Host 'PASS catalog selection'