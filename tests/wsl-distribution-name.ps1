[CmdletBinding()]
param(
    [string]$ArchimedesPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'archimedes.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TempRoot = Join-Path ([IO.Path]::GetTempPath()) ('archimedes-wsl-name-' + [guid]::NewGuid().ToString('N'))
$FakeBin = Join-Path $TempRoot 'bin'
$ExportDir = Join-Path $TempRoot 'exports'
$WslLog = Join-Path $TempRoot 'wsl.log'
New-Item -ItemType Directory -Force $FakeBin, $ExportDir | Out-Null

$FakeDocker = @'
if ($args[0] -eq 'info') { exit 0 }
if ($args[0] -eq 'image' -and $args[1] -eq 'inspect') { exit 0 }
if ($args[0] -eq 'create') { 'fake-container'; exit 0 }
if ($args[0] -eq 'export') {
    $i = [Array]::IndexOf($args, '--output')
    Set-Content -LiteralPath $args[$i + 1] -Value 'fake rootfs'
    exit 0
}
if ($args[0] -eq 'rm') { exit 0 }
exit 0
'@

Set-Content (Join-Path $FakeBin 'docker-fake.ps1') $FakeDocker -Encoding UTF8
Set-Content (Join-Path $FakeBin 'docker.cmd') '@powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0docker-fake.ps1" %*' -Encoding ASCII

$OldPath = $env:PATH
$OldLog = $env:ARCHIMEDES_WSL_TEST_LOG
try {
    $env:PATH = "$FakeBin;$OldPath"
    $env:ARCHIMEDES_WSL_TEST_LOG = $WslLog

    function global:wsl.exe {
        param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Rest)
        Add-Content -LiteralPath $env:ARCHIMEDES_WSL_TEST_LOG -Value (($Rest | ForEach-Object { [string]$_ }) -join '|')
        return
    }

    & $ArchimedesPath `
        -SourceMode local `
        -Image 'fake:test' `
        -ExportMode rootfs `
        -ExportDirectory $ExportDir `
        -DistributionName 'Kali Linux' `
        -ImportToWSL `
        -NonInteractive

    $commands = Get-Content -LiteralPath $WslLog
    if (-not ($commands -match '^--import\|Kali-Linux\|')) {
        throw "Expected WSL import name 'Kali-Linux'. Commands: $($commands -join '; ')"
    }
    Write-Host 'PASS: friendly distribution name is converted to WSL-safe Kali-Linux.'
}
finally {
    Remove-Item Function:\wsl.exe -ErrorAction SilentlyContinue
    $env:PATH = $OldPath
    $env:ARCHIMEDES_WSL_TEST_LOG = $OldLog
    Remove-Item $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
