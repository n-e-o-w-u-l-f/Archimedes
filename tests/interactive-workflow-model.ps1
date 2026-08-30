$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib/Archimedes.Workflow.ps1')
$sources=@(
 [pscustomobject]@{SourceMode='pull';Image='debian:13';DisplayName='Debian 13';WslEligible=$true;Architecture='amd64';BuildContext='';Dockerfile=''}
 [pscustomobject]@{SourceMode='local';Image='ubuntu:26.04';DisplayName='Ubuntu 26.04';WslEligible=$true;Architecture='amd64';BuildContext='';Dockerfile=''}
)
$queue=@(New-ArchimedesQueueFromSources -Sources $sources)
if($queue.Count-ne2){throw 'queue composition lost sources'}
if($queue[0].SourceMode-ne'pull'-or$queue[1].Image-ne'ubuntu:26.04'){throw 'queue composition changed source data'}
if($queue[0].Status-ne'Pending'){throw 'queue item must start Pending'}
Write-Host 'PASS interactive workflow model'
