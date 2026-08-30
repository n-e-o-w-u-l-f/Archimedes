$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib/Archimedes.Storage.ps1')
$fake=[pscustomobject]@{Name='B:\';VolumeLabel='Data';DriveType=[IO.DriveType]::Fixed;IsReady=$true;AvailableFreeSpace=600GB;TotalSize=1000GB}
$model=ConvertTo-ArchimedesDriveModel $fake
if($model.Root-ne'B:\'-or$model.FreeBytes-ne600GB-or-not $model.WritableCandidate){throw 'drive model failed'}
$suggested=Get-ArchimedesSuggestedExportRoot 'B:\'
if($suggested-ne'B:\WSL2\'){throw "unexpected suggested root: $suggested"}
Write-Host 'PASS storage selection'
