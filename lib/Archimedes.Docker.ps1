Set-StrictMode -Version Latest

function Normalize-ArchimedesArchitecture {
    param([string]$Architecture)
    switch (($Architecture | ForEach-Object { [string]$_ }).ToLowerInvariant()) {
        'x86_64' { 'amd64'; break }
        'amd64' { 'amd64'; break }
        'aarch64' { 'arm64'; break }
        'arm64' { 'arm64'; break }
        default { ([string]$Architecture).ToLowerInvariant() }
    }
}

function Get-ArchimedesHostArchitecture {
    try {
        $value = & docker info --format '{{.Architecture}}' 2>$null
        if ($LASTEXITCODE -eq 0 -and $value) { return Normalize-ArchimedesArchitecture ($value | Select-Object -Last 1) }
    } catch {}
    try {
        return Normalize-ArchimedesArchitecture ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString())
    } catch { return '' }
}

function Get-ArchimedesWslCompatibility {
    param([string]$Os,[string]$ImageArchitecture,[string]$HostArchitecture)
    $osName = ([string]$Os).ToLowerInvariant()
    $imageArch = Normalize-ArchimedesArchitecture $ImageArchitecture
    $hostArch = Normalize-ArchimedesArchitecture $HostArchitecture
    if ($osName -ne 'linux') {
        return [pscustomobject]@{ Eligible=$false; RequiresEmulation=$false; Reason="image OS is $Os, not linux" }
    }
    if (-not $imageArch) {
        return [pscustomobject]@{ Eligible=$false; RequiresEmulation=$false; Reason='unknown image architecture' }
    }
    if (-not $hostArch) {
        return [pscustomobject]@{ Eligible=$false; RequiresEmulation=$false; Reason='unknown host architecture' }
    }
    if ($imageArch -eq $hostArch) {
        return [pscustomobject]@{ Eligible=$true; RequiresEmulation=$false; Reason='native Linux architecture' }
    }
    return [pscustomobject]@{ Eligible=$false; RequiresEmulation=$true; Reason="image architecture $imageArch differs from host $hostArch" }
}

function Get-ArchimedesOsReleaseValue {
    param([string]$Text,[string]$Name)
    foreach ($line in ([string]$Text -split "`r?`n")) {
        if ($line -match ('^' + [regex]::Escape($Name) + '=(.*)$')) {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ''
}

function ConvertTo-ArchimedesImageCandidate {
    param(
        [Parameter(Mandatory)][string]$Reference,
        [Parameter(Mandatory)]$Inspect,
        [string]$OsReleaseText='',
        [string]$HostArchitecture=''
    )
    $compat = Get-ArchimedesWslCompatibility -Os ([string]$Inspect.Os) -ImageArchitecture ([string]$Inspect.Architecture) -HostArchitecture $HostArchitecture
    $distribution = Get-ArchimedesOsReleaseValue $OsReleaseText 'ID'
    $pretty = Get-ArchimedesOsReleaseValue $OsReleaseText 'PRETTY_NAME'
    if (-not $distribution -and ([string]$Inspect.Os).ToLowerInvariant() -eq 'linux') { $distribution='unknown-linux' }
    [pscustomobject]@{
        Id = [string]$Inspect.Id
        Reference = $Reference
        OS = [string]$Inspect.Os
        Architecture = Normalize-ArchimedesArchitecture ([string]$Inspect.Architecture)
        SizeBytes = [long]$Inspect.Size
        Distribution = $distribution
        PrettyName = $pretty
        WslEligible = [bool]$compat.Eligible
        RequiresEmulation = [bool]$compat.RequiresEmulation
        EligibilityReason = [string]$compat.Reason
    }
}
function Get-ArchimedesImageOsRelease {
    param([Parameter(Mandatory)][string]$ImageRef)
    $container=$null
    try {
        $container = (& docker create $ImageRef 2>$null | Select-Object -Last 1)
        if (-not $container -or $LASTEXITCODE -ne 0) { return '' }
        $container = ([string]$container).Trim()
        foreach ($candidate in @('/etc/os-release','/usr/lib/os-release')) {
            $temp=[IO.Path]::GetTempFileName()
            try {
                & docker cp "$container`:$candidate" $temp 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $temp)) {
                    return (Get-Content -LiteralPath $temp -Raw)
                }
            } finally { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
        }
        return ''
    } finally {
        if ($container) { & docker rm $container 2>$null | Out-Null }
    }
}

function Get-ArchimedesImageReferenceFromListRow {
    param($Row)
    $repo=[string]$Row.Repository
    $tag=[string]$Row.Tag
    if (-not $repo -or -not $tag -or $repo -eq '<none>' -or $tag -eq '<none>') { return '' }
    return "$repo`:$tag"
}

function Get-ArchimedesLocalDockerImages {
    param([string]$HostArchitecture=(Get-ArchimedesHostArchitecture))
    $rows = @(& docker image ls --no-trunc --format '{{json .}}')
    if ($LASTEXITCODE -ne 0) { throw 'docker image ls failed.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($line in $rows) {
        if (-not $line) { continue }
        $row = $line | ConvertFrom-Json
        $ref = Get-ArchimedesImageReferenceFromListRow $row
        if (-not $ref -or -not $seen.Add($ref)) { continue }
        $json = & docker image inspect $ref
        if ($LASTEXITCODE -ne 0) { continue }
        $inspect = @($json | ConvertFrom-Json)[0]
        $osRelease=''
        if (([string]$inspect.Os).ToLowerInvariant() -eq 'linux') {
            $osRelease = Get-ArchimedesImageOsRelease -ImageRef $ref
        }
        ConvertTo-ArchimedesImageCandidate -Reference $ref -Inspect $inspect -OsReleaseText $osRelease -HostArchitecture $HostArchitecture
    }
}
