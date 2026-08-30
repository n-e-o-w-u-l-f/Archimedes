[CmdletBinding()]
param(
    [string]$ArchimedesPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'archimedes.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('archimedes-image-ref-' + [guid]::NewGuid().ToString('N'))
$FakeBin = Join-Path $TempRoot 'bin'
$ExportDir = Join-Path $TempRoot 'exports'
$LogFile = Join-Path $TempRoot 'docker.log'
New-Item -ItemType Directory -Force $FakeBin, $ExportDir | Out-Null

$FakeDocker = @'
$ErrorActionPreference = 'Stop'
$log = $env:ARCHIMEDES_TEST_LOG
Add-Content -LiteralPath $log -Value (($args | ForEach-Object { [string]$_ }) -join ' ')

if ($args.Count -eq 0) { exit 0 }
switch ($args[0]) {
    'info' { Write-Output 'Server: fake'; exit 0 }
    'context' { if ($args.Count -gt 1 -and $args[1] -eq 'show') { Write-Output 'desktop-linux'; exit 0 } }
    'pull' { exit 0 }
    'save' {
        $index = [Array]::IndexOf($args, '--output')
        if ($index -lt 0 -or $index + 1 -ge $args.Count) { exit 2 }
        Set-Content -LiteralPath $args[$index + 1] -Value 'fake image archive'
        exit 0
    }
}
exit 0
'@

Set-Content -LiteralPath (Join-Path $FakeBin 'docker-fake.ps1') -Value $FakeDocker -Encoding UTF8
Set-Content -LiteralPath (Join-Path $FakeBin 'docker.cmd') -Value '@powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0docker-fake.ps1" %*' -Encoding ASCII

$OldPath = $env:PATH
$OldLog = $env:ARCHIMEDES_TEST_LOG
try {
    $env:PATH = "$FakeBin;$OldPath"
    $env:ARCHIMEDES_TEST_LOG = $LogFile

    & $ArchimedesPath `
        -SourceMode pull `
        -Image 'ubuntu26.04' `
        -ExportMode image `
        -ExportDirectory $ExportDir `
        -DistributionName 'Ubuntu v26.04' `
        -NonInteractive

    $Commands = Get-Content -LiteralPath $LogFile
    if (-not ($Commands -contains 'pull ubuntu:26.04')) {
        throw "Expected friendly image reference 'ubuntu26.04' to normalize to 'ubuntu:26.04'. Commands: $($Commands -join '; ')"
    }

    Write-Host 'PASS: ubuntu26.04 is normalized to ubuntu:26.04 before docker pull.'
}
finally {
    $env:PATH = $OldPath
    $env:ARCHIMEDES_TEST_LOG = $OldLog
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
