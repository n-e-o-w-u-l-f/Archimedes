Set-StrictMode -Version Latest

function New-ArchimedesActionPlan {
    param(
        [bool]$ExportDockerTar,
        [bool]$KeepRootFs,
        [bool]$ImportWsl,
        [bool]$ExportWslTar
    )
    if ($ExportWslTar) { $ImportWsl=$true }
    $needsRootFs = $KeepRootFs -or $ImportWsl
    if (-not ($ExportDockerTar -or $KeepRootFs -or $ImportWsl -or $ExportWslTar)) {
        throw 'No export/import action selected.'
    }
    [pscustomobject]@{
        ExportDockerTar=$ExportDockerTar
        KeepRootFs=$KeepRootFs
        NeedsRootFs=$needsRootFs
        ImportWsl=$ImportWsl
        ExportWslTar=$ExportWslTar
        DeleteRootFsAfterSuccess=($ImportWsl -and -not $KeepRootFs)
    }
}

function New-ArchimedesQueueItem {
    param(
        [Parameter(Mandatory)][string]$SourceMode,
        [Parameter(Mandatory)][string]$Image,
        [Parameter(Mandatory)][string]$DisplayName,
        [bool]$WslEligible,
        [string]$Architecture=''
    )
    [pscustomobject]@{
        SourceMode=$SourceMode; Image=$Image; DisplayName=$DisplayName
        WslEligible=$WslEligible; Architecture=$Architecture
        Status='Pending'; Error=''; Result=$null
    }
}
function Invoke-ArchimedesBatch {
    param(
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)]$ActionPlan,
        [Parameter(Mandatory)][scriptblock]$Executor,
        [bool]$ContinueOnError=$true
    )
    foreach ($item in $Items) {
        $item.Status='Running'; $item.Error=''; $item.Result=$null
        try {
            $item.Result = & $Executor $item $ActionPlan
            $item.Status='Done'
        } catch {
            $item.Status='Failed'; $item.Error=$_.Exception.Message
            if (-not $ContinueOnError) { throw }
        }
    }
    return @($Items)
}

function New-ArchimedesQueueFromSources {
    param([Parameter(Mandatory)][object[]]$Sources)
    foreach ($source in $Sources) {
        $item=New-ArchimedesQueueItem -SourceMode ([string]$source.SourceMode) -Image ([string]$source.Image) -DisplayName ([string]$source.DisplayName) -WslEligible ([bool]$source.WslEligible) -Architecture ([string]$source.Architecture)
        if ($source.PSObject.Properties['BuildContext']) { $item | Add-Member BuildContext ([string]$source.BuildContext) }
        if ($source.PSObject.Properties['Dockerfile']) { $item | Add-Member Dockerfile ([string]$source.Dockerfile) }
        $item
    }
}

function Get-ArchimedesCatalogSourceObjects {
    param([Parameter(Mandatory)][object[]]$SelectedItems)
    $hostArch=Get-ArchimedesHostArchitecture
    foreach ($item in $SelectedItems) {
        $entry=$item.CatalogEntry; $arches=@($entry.Architectures)
        $selectedArch=if($arches -contains $hostArch){$hostArch}elseif($arches.Count){[string]$arches[0]}else{$hostArch}
        $compat=Get-ArchimedesWslCompatibility -Os $entry.OS -ImageArchitecture $selectedArch -HostArchitecture $hostArch
        [pscustomobject]@{
            SourceMode='pull'; Image=[string]$entry.Image; DisplayName=[string]$entry.DisplayName
            WslEligible=[bool]($compat.Eligible -and $entry.WslEligibility -notmatch '^(?i:no|false|unsupported)$')
            Architecture=$selectedArch; BuildContext=''; Dockerfile=''
        }
    }
}
function Get-ArchimedesLocalSourceObjects {
    param([Parameter(Mandatory)][object[]]$SelectedItems)
    foreach ($item in $SelectedItems) {
        $display=if($item.PrettyName){[string]$item.PrettyName}else{[string]$item.Reference}
        [pscustomobject]@{
            SourceMode='local'; Image=[string]$item.Reference; DisplayName=$display
            WslEligible=[bool]$item.WslEligible; Architecture=[string]$item.Architecture
            BuildContext=''; Dockerfile=''
        }
    }
}

function Invoke-ArchimedesInteractiveSourceSelection {
    $options=@(
        [pscustomobject]@{Id='catalog';Label='Distribution / repository catalog'},
        [pscustomobject]@{Id='local';Label='Locally installed Docker images'},
        [pscustomobject]@{Id='custom';Label='Custom Docker image reference'},
        [pscustomobject]@{Id='build';Label='Build from Dockerfile'},
        [pscustomobject]@{Id='exit';Label='Exit'}
    )
    while($true){
        $source=@(Invoke-ArchimedesSelectionMenu -Title 'Source' -Items $options -IdProperty Id -DisplayScript { param($x) $x.Label } -PageSize 8)
        if(-not $source.Count){ return @() }
        switch($source[0].Id){
            'catalog' {
                $catalog=@(Import-ArchimedesCatalog -Path $script:ArchimedesCatalogPath)
                $items=@(Get-ArchimedesCatalogMenuItems -Catalog $catalog)
                $picked=@(Invoke-ArchimedesSelectionMenu -Title 'Distribution / repository catalog' -Items $items -IdProperty Id -DisplayScript {
                    param($x); "{0,-28} {1,-44} {2,-12} WSL={3}" -f $x.DisplayName,$x.Image,$x.Architecture,$x.WslEligibility
                } -MultiSelect -PageSize 14)
                if($picked.Count){ return @(Get-ArchimedesCatalogSourceObjects -SelectedItems $picked) }
            }
            'local' {
                Write-Host 'Inspecting local Docker images...'
                $items=@(Get-ArchimedesLocalDockerImages)
                if(-not $items.Count){ Write-Warning 'No tagged local Docker images were found.'; continue }
                $picked=@(Invoke-ArchimedesSelectionMenu -Title 'Locally installed Docker images' -Items $items -IdProperty Reference -DisplayScript {
                    param($x)
                    $flag=if($x.WslEligible){'WSL ready'}elseif($x.RequiresEmulation){'emulation required'}else{'WSL unavailable'}
                    "{0,-48} {1,-12} {2,-16} {3}" -f $x.Reference,("$($x.OS)/$($x.Architecture)"),$x.Distribution,$flag
                } -MultiSelect -PageSize 14)
                if($picked.Count){ return @(Get-ArchimedesLocalSourceObjects -SelectedItems $picked) }
            }
            'custom' {
                $ref=(Read-Host 'Docker image reference').Trim()
                if(-not $ref){ continue }
                return @([pscustomobject]@{SourceMode='pull';Image=$ref;DisplayName=$ref;WslEligible=$true;Architecture=(Get-ArchimedesHostArchitecture);BuildContext='';Dockerfile=''})
            }
            'build' {
                $tag=(Read-Host 'Image tag [archimedes/custom:latest]').Trim(); if(-not $tag){$tag='archimedes/custom:latest'}
                $ctx=(Read-Host 'Build context [.').Trim(); if(-not $ctx){$ctx='.'}
                $df=(Read-Host "Dockerfile [$ctx/Dockerfile]").Trim(); if(-not $df){$df=Join-Path $ctx 'Dockerfile'}
                return @([pscustomobject]@{SourceMode='build';Image=$tag;DisplayName=$tag;WslEligible=$true;Architecture=(Get-ArchimedesHostArchitecture);BuildContext=$ctx;Dockerfile=$df})
            }
            'exit' { return @() }
        }
    }
}

function Invoke-ArchimedesInteractiveStorageSelection {
    if($script:ArchimedesIsWindows){
        $drives=@(Get-ArchimedesWindowsDrives | Where-Object WritableCandidate)
        if($drives.Count){
            $dockerRoot=Get-ArchimedesDockerDataRoot
            if($dockerRoot){ Write-Host "Docker data root (unchanged): $dockerRoot" }
            $picked=@(Invoke-ArchimedesSelectionMenu -Title 'Export drive' -Items $drives -IdProperty Root -DisplayScript {
                param($x); "{0,-5} {1,-16} free {2,-12} total {3}" -f $x.Root,$x.Label,$x.FreeText,$x.TotalText
            } -PageSize 12)
            if($picked.Count){
                $default=Get-ArchimedesSuggestedExportRoot -DriveRoot $picked[0].Root
                $value=(Read-Host "Export directory [$default]").Trim('"')
                if(-not $value){$value=$default}
                return $value
            }
        }
    }
    $default=Join-Path (Get-Location) 'exports'
    $value=(Read-Host "Export directory [$default]").Trim('"')
    if($value){return $value}; return $default
}
function Invoke-ArchimedesInteractiveActionSelection {
    $actions=@(
        [pscustomobject]@{Id='docker-tar';Label='Export Docker image archive'},
        [pscustomobject]@{Id='rootfs-tar';Label='Keep RootFS TAR'},
        [pscustomobject]@{Id='wsl-import';Label='Import RootFS into WSL2'},
        [pscustomobject]@{Id='wsl-export';Label='Export imported WSL2 distribution TAR'}
    )
    while($true){
        $picked=@(Invoke-ArchimedesSelectionMenu -Title 'Actions' -Items $actions -IdProperty Id -DisplayScript { param($x) $x.Label } -MultiSelect -PageSize 8)
        if(-not $picked.Count){ Write-Warning 'Select at least one action.'; continue }
        $ids=@($picked | ForEach-Object Id)
        $import=($ids -contains 'wsl-import') -or ($ids -contains 'wsl-export')
        if(($ids -contains 'wsl-export') -and -not $script:ArchimedesIsWindows){ Write-Warning 'WSL export requires Windows.'; continue }
        if($import -and -not $script:ArchimedesIsWindows){ Write-Warning 'WSL import requires Windows.'; continue }
        return New-ArchimedesActionPlan -ExportDockerTar:($ids -contains 'docker-tar') -KeepRootFs:($ids -contains 'rootfs-tar') -ImportWsl:$import -ExportWslTar:($ids -contains 'wsl-export')
    }
}

function Get-ArchimedesCurrentImageCandidate {
    param([Parameter(Mandatory)][string]$ImageRef)
    $json=& docker image inspect $ImageRef
    Assert-ExitCode "docker image inspect $ImageRef"
    $inspect=@($json | ConvertFrom-Json)[0]
    $osRelease=''
    if(([string]$inspect.Os).ToLowerInvariant() -eq 'linux') { $osRelease=Get-ArchimedesImageOsRelease -ImageRef $ImageRef }
    return ConvertTo-ArchimedesImageCandidate -Reference $ImageRef -Inspect $inspect -OsReleaseText $osRelease -HostArchitecture (Get-ArchimedesHostArchitecture)
}

function Invoke-ArchimedesQueueItemExecution {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)]$ActionPlan,
        [Parameter(Mandatory)][string]$ExportDirectory
    )
    Write-Section "$($Item.DisplayName) [$($Item.SourceMode)]"
    switch($Item.SourceMode){
        'pull' {
            $requested=$Item.Image; $resolved=Resolve-DockerImageReference $requested
            if($resolved -ne $requested){ Write-Host "Resolved image reference: $requested -> $resolved" }
            $Item.Image=$resolved; $Item.Status='Pulling'; & docker pull $Item.Image; Assert-ExitCode "docker pull $($Item.Image)"
        }
        'local' { $Item.Status='Inspecting'; & docker image inspect $Item.Image *> $null; Assert-ExitCode "docker image inspect $($Item.Image)" }
        'build' {
            $Item.Status='Building'
            if(-not $Item.BuildContext){$Item.BuildContext='.'}; if(-not $Item.Dockerfile){$Item.Dockerfile=Join-Path $Item.BuildContext 'Dockerfile'}
            if(-not (Test-Path -LiteralPath $Item.BuildContext)){throw "Build context does not exist: $($Item.BuildContext)"}
            if(-not (Test-Path -LiteralPath $Item.Dockerfile)){throw "Dockerfile does not exist: $($Item.Dockerfile)"}
            & docker build --file $Item.Dockerfile --tag $Item.Image $Item.BuildContext; Assert-ExitCode "docker build $($Item.Image)"
        }
        default { throw "Unsupported source mode: $($Item.SourceMode)" }
    }
    $candidate=Get-ArchimedesCurrentImageCandidate -ImageRef $Item.Image
    $Item.WslEligible=[bool]$candidate.WslEligible; $Item.Architecture=[string]$candidate.Architecture
    $artifactName=if($Item.DisplayName){[string]$Item.DisplayName}else{ConvertTo-SafeName $Item.Image}
    $imageTar=Join-Path $ExportDirectory "$artifactName-docker-image.tar"
    $rootFsTar=Join-Path $ExportDirectory "$artifactName-rootfs.tar"
    $wslTar=Join-Path $ExportDirectory "$artifactName-wsl.tar"
    if($ActionPlan.ExportDockerTar){$Item.Status='Exporting Docker image';New-DockerImageTar -ImageRef $Item.Image -OutputPath $imageTar}
    if($ActionPlan.NeedsRootFs){$Item.Status='Exporting RootFS';New-RootFsTar -ImageRef $Item.Image -OutputPath $rootFsTar}
    $wslName=ConvertTo-WSLDistributionName $artifactName
    $installDirectory=Join-Path (Join-Path $ExportDirectory 'wsl') $wslName
    if($ActionPlan.ImportWsl){
        if(-not $candidate.WslEligible){throw "WSL import blocked for $($Item.Image): $($candidate.EligibilityReason)"}
        $Item.Status='Importing WSL2';Import-RootFsToWSL -Name $wslName -RootFsTar $rootFsTar -InstallDirectory $installDirectory
        if($ActionPlan.ExportWslTar){$Item.Status='Exporting WSL2';Export-WSLDistribution -Name $wslName -OutputPath $wslTar}
        if($ActionPlan.DeleteRootFsAfterSuccess -and (Test-Path -LiteralPath $rootFsTar)){Remove-Item -LiteralPath $rootFsTar -Force}
    }
    [pscustomobject]@{
        Image=$Item.Image
        DockerTar=if($ActionPlan.ExportDockerTar){$imageTar}else{''}
        RootFsTar=if($ActionPlan.KeepRootFs){$rootFsTar}else{''}
        WslName=if($ActionPlan.ImportWsl){$wslName}else{''}
        WslTar=if($ActionPlan.ExportWslTar){$wslTar}else{''}
    }
}

function Invoke-ArchimedesInteractiveWorkflow {
    $sources=@(Invoke-ArchimedesInteractiveSourceSelection)
    if(-not $sources.Count){Write-Host 'No source selected.';return}
    $exportRoot=Invoke-ArchimedesInteractiveStorageSelection
    $exportRoot=[IO.Path]::GetFullPath($exportRoot);New-Item -ItemType Directory -Force -Path $exportRoot | Out-Null
    $actionPlan=Invoke-ArchimedesInteractiveActionSelection
    $queue=@(New-ArchimedesQueueFromSources -Sources $sources)
    Write-Section 'Execution queue'
    for($i=0;$i -lt $queue.Count;$i++){Write-Host ("{0}/{1}  {2}  {3}" -f ($i+1),$queue.Count,$queue[$i].DisplayName,$queue[$i].Image)}
    $executor={param($item,$plan) Invoke-ArchimedesQueueItemExecution -Item $item -ActionPlan $plan -ExportDirectory $exportRoot}
    $result=@(Invoke-ArchimedesBatch -Items $queue -ActionPlan $actionPlan -Executor $executor -ContinueOnError $true)
    Write-Section 'Summary'
    foreach($item in $result){$suffix=if($item.Error){" - $($item.Error)"}else{''};Write-Host ("{0,-8} {1}{2}" -f $item.Status,$item.DisplayName,$suffix)}
    if(@($result|Where-Object Status -eq 'Failed').Count){Write-Warning 'One or more queue items failed.'}
}
