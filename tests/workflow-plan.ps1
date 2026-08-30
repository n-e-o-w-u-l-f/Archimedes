$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib/Archimedes.Workflow.ps1')
$p=New-ArchimedesActionPlan -ExportDockerTar:$false -KeepRootFs:$false -ImportWsl:$true -ExportWslTar:$false
if(-not $p.NeedsRootFs-or-not $p.DeleteRootFsAfterSuccess){throw 'temporary RootFS implication failed'}
$p2=New-ArchimedesActionPlan -ExportDockerTar:$true -KeepRootFs:$true -ImportWsl:$false -ExportWslTar:$false
if(-not $p2.ExportDockerTar-or-not $p2.KeepRootFs-or$p2.DeleteRootFsAfterSuccess){throw 'persistent plan failed'}
$p3=New-ArchimedesActionPlan -ExportDockerTar:$false -KeepRootFs:$false -ImportWsl:$false -ExportWslTar:$true
if(-not $p3.ImportWsl-or-not $p3.NeedsRootFs){throw 'wsl export implication failed'}
Write-Host 'PASS workflow plan'
