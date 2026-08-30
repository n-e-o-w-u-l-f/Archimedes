Set-StrictMode -Version Latest

function Format-ArchimedesBytes {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N1} TB' -f ($Bytes/1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N1} GB' -f ($Bytes/1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes/1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes/1KB)) }
    return "$Bytes B"
}

function ConvertTo-ArchimedesDriveModel {
    param([Parameter(Mandatory)]$Drive)
    $root=[string]$Drive.Name
    $label=''; $free=[long]0; $total=[long]0; $ready=$false; $type='Unknown'
    try { $label=[string]$Drive.VolumeLabel } catch {}
    try { $free=[long]$Drive.AvailableFreeSpace } catch {}
    try { $total=[long]$Drive.TotalSize } catch {}
    try { $ready=[bool]$Drive.IsReady } catch {}
    try { $type=[string]$Drive.DriveType } catch {}
    $writable = $ready -and $root -and $type -in @('Fixed','Removable','Network')
    [pscustomobject]@{
        Id=$root; Root=$root; Label=$label; DriveType=$type; IsReady=$ready
        FreeBytes=$free; TotalBytes=$total; WritableCandidate=$writable
        FreeText=(Format-ArchimedesBytes $free); TotalText=(Format-ArchimedesBytes $total)
    }
}

function Get-ArchimedesWindowsDrives {
    foreach ($drive in [IO.DriveInfo]::GetDrives()) {
        try { $model=ConvertTo-ArchimedesDriveModel $drive; if ($model.IsReady) { $model } } catch {}
    }
}
function Get-ArchimedesSuggestedExportRoot {
    param([Parameter(Mandatory)][string]$DriveRoot)
    if ($DriveRoot -match '^[A-Za-z]:[\\/]?$') {
        return ($DriveRoot.Substring(0,2) + '\WSL2\')
    }
    $root=$DriveRoot
    if (-not $root.EndsWith([IO.Path]::DirectorySeparatorChar)) { $root += [IO.Path]::DirectorySeparatorChar }
    return (Join-Path $root 'WSL2') + [IO.Path]::DirectorySeparatorChar
}

function Get-ArchimedesDockerDataRoot {
    try {
        $value=& docker info --format '{{json .DockerRootDir}}' 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $value) { return '' }
        $text=($value | Select-Object -Last 1).Trim()
        try { return [string]($text | ConvertFrom-Json) } catch { return $text.Trim('"') }
    } catch { return '' }
}
