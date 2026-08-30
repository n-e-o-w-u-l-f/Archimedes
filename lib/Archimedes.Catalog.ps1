Set-StrictMode -Version Latest

function ConvertTo-ArchimedesAliasKey {
    param([string]$Value)
    if ($null -eq $Value) { return '' }
    return (($Value.Trim().ToLowerInvariant()) -replace '[\s_-]+','')
}

function ConvertTo-ArchimedesBoolean {
    param([string]$Value)
    return ([string]$Value).Trim().ToLowerInvariant() -eq 'true'
}

function Import-ArchimedesCatalog {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Distribution catalog not found: $Path" }
    $rows = @(Import-Csv -LiteralPath $Path -Delimiter "`t")
    foreach ($row in $rows) {
        [pscustomobject]@{
            Id = [string]$row.Id
            DisplayName = [string]$row.DisplayName
            Family = [string]$row.Family
            Version = [string]$row.Version
            Image = [string]$row.Image
            Aliases = @(([string]$row.Aliases -split ';') | Where-Object { $_ } | ForEach-Object { $_.Trim() })
            Registry = [string]$row.Registry
            OS = [string]$row.OS
            Architectures = @(([string]$row.Architectures -split ';') | Where-Object { $_ } | ForEach-Object { $_.Trim() })
            Status = [string]$row.Status
            Rolling = ConvertTo-ArchimedesBoolean $row.Rolling
            Official = ConvertTo-ArchimedesBoolean $row.Official
            WslEligibility = [string]$row.WslEligibility
            Notes = [string]$row.Notes
        }
    }
}
function Resolve-ArchimedesCatalogAlias {
    param([Parameter(Mandatory)][object[]]$Catalog,[Parameter(Mandatory)][string]$Value)
    $key = ConvertTo-ArchimedesAliasKey $Value
    foreach ($entry in $Catalog) {
        $candidates = @($entry.Image,$entry.Id,$entry.DisplayName) + @($entry.Aliases)
        foreach ($candidate in $candidates) {
            if ((ConvertTo-ArchimedesAliasKey ([string]$candidate)) -eq $key) { return $entry }
        }
    }
    return $null
}

function Get-ArchimedesCatalogMenuItems {
    param([Parameter(Mandatory)][object[]]$Catalog)
    foreach ($entry in $Catalog) {
        $arch = if ($entry.Architectures.Count) { $entry.Architectures -join ',' } else { 'unknown' }
        [pscustomobject]@{
            Id = [string]$entry.Id
            DisplayName = [string]$entry.DisplayName
            Image = [string]$entry.Image
            Architecture = $arch
            WslEligibility = [string]$entry.WslEligibility
            CatalogEntry = $entry
        }
    }
}
