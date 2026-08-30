$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'lib/Archimedes.Workflow.ps1')
$items=@(
 New-ArchimedesQueueItem -SourceMode local -Image 'one:test' -DisplayName One -WslEligible $true -Architecture amd64
 New-ArchimedesQueueItem -SourceMode local -Image 'two:test' -DisplayName Two -WslEligible $true -Architecture amd64
 New-ArchimedesQueueItem -SourceMode local -Image 'three:test' -DisplayName Three -WslEligible $true -Architecture amd64
)
$plan=New-ArchimedesActionPlan -ExportDockerTar:$false -KeepRootFs:$true -ImportWsl:$false -ExportWslTar:$false
$exec={param($item,$actionPlan) if($item.Image-eq'two:test'){throw 'synthetic failure'};"ok:$($item.Image)"}
$result=@(Invoke-ArchimedesBatch -Items $items -ActionPlan $plan -Executor $exec -ContinueOnError $true)
if($result[0].Status-ne'Done'-or$result[1].Status-ne'Failed'-or$result[2].Status-ne'Done'){throw "unexpected statuses $($result.Status -join ',')"}
Write-Host 'PASS workflow queue'
