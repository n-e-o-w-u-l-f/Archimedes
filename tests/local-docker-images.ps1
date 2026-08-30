$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib/Archimedes.Docker.ps1')
$linuxInspect=[pscustomobject]@{Os='linux';Architecture='amd64';Size=123456789;Id='sha256:linux1';Config=[pscustomobject]@{Labels=@{}}}
$linux=ConvertTo-ArchimedesImageCandidate -Reference 'ubuntu:26.04' -Inspect $linuxInspect -OsReleaseText "ID=ubuntu`nVERSION_ID=26.04" -HostArchitecture 'amd64'
if(-not $linux.WslEligible-or$linux.Distribution-ne'ubuntu'){throw 'linux amd64 classification failed'}
$winInspect=[pscustomobject]@{Os='windows';Architecture='amd64';Size=100;Id='sha256:win1';Config=[pscustomobject]@{Labels=@{}}}
$win=ConvertTo-ArchimedesImageCandidate -Reference 'windows:test' -Inspect $winInspect -HostArchitecture 'amd64'
if($win.WslEligible){throw 'windows image eligible'}
$armInspect=[pscustomobject]@{Os='linux';Architecture='arm64';Size=100;Id='sha256:arm1';Config=[pscustomobject]@{Labels=@{}}}
$arm=ConvertTo-ArchimedesImageCandidate -Reference 'debian:arm64' -Inspect $armInspect -OsReleaseText 'ID=debian' -HostArchitecture 'amd64'
if(-not $arm.RequiresEmulation-or$arm.WslEligible){throw 'architecture mismatch failed'}
$unknown=ConvertTo-ArchimedesImageCandidate -Reference 'custom:latest' -Inspect $linuxInspect -HostArchitecture 'amd64'
if($unknown.Distribution-ne'unknown-linux'-or-not $unknown.WslEligible){throw 'unknown linux failed'}
Write-Host 'PASS local Docker image classification'
