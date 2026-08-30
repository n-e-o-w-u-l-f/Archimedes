[CmdletBinding()]
param(
    [string]$ArchimedesPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'archimedes.ps1')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('archimedes-docker-bootstrap-' + [guid]::NewGuid().ToString('N'))
$FakeBin = Join-Path $TempRoot 'bin'
$ExportDir = Join-Path $TempRoot 'exports'
$StateFile = Join-Path $TempRoot 'daemon.started'
$LogFile = Join-Path $TempRoot 'docker.log'

New-Item -ItemType Directory -Force $FakeBin, $ExportDir | Out-Null

$FakeDocker = @'
$ErrorActionPreference = 'Stop'
$state = $env:ARCHIMEDES_TEST_STATE
$log = $env:ARCHIMEDES_TEST_LOG
Add-Content -LiteralPath $log -Value (($args | ForEach-Object { [string]$_ }) -join ' ')

function Is-Running { Test-Path -LiteralPath $state }

if ($args.Count -eq 0) { exit 0 }

switch ($args[0]) {
    'version' {
        if (Is-Running) { Write-Output 'Docker fake version'; exit 0 }
        [Console]::Error.WriteLine('Cannot connect to Docker daemon')
        exit 1
    }
    'info' {
        if (-not (Is-Running)) { [Console]::Error.WriteLine('Cannot connect to Docker daemon'); exit 1 }
        if ($args -contains '--format') { Write-Output 'linux' } else { Write-Output 'Server: fake' }
        exit 0
    }
    'context' {
        if ($args.Count -gt 1 -and $args[1] -eq 'show') { Write-Output 'desktop-linux'; exit 0 }
    }
    'desktop' {
        if ($args.Count -gt 1 -and $args[1] -eq 'version') { Write-Output 'Docker Desktop CLI plugin version: fake'; exit 0 }
        if ($args.Count -gt 1 -and $args[1] -eq 'status') {
            if (Is-Running) { Write-Output 'running'; exit 0 }
            Write-Output 'stopped'; exit 1
        }
        if ($args.Count -gt 1 -and $args[1] -eq 'start') {
            Set-Content -LiteralPath $state -Value 'running'
            Write-Output 'started'
            exit 0
        }
    }
    'image' { if ($args.Count -gt 1 -and $args[1] -eq 'inspect') { exit 0 } }
    'save' {
        $index = [Array]::IndexOf($args, '--output')
        if ($index -lt 0) { $index = [Array]::IndexOf($args, '-o') }
        if ($index -lt 0 -or $index + 1 -ge $args.Count) { exit 2 }
        Set-Content -LiteralPath $args[$index + 1] -Value 'fake docker archive'
        exit 0
    }
    'pull' { exit 0 }
    'create' { Write-Output 'fake-container-id'; exit 0 }
    'export' {
        $index = [Array]::IndexOf($args, '--output')
        if ($index -lt 0 -or $index + 1 -ge $args.Count) { exit 2 }
        Set-Content -LiteralPath $args[$index + 1] -Value 'fake rootfs archive'
        exit 0
    }
    'rm' { exit 0 }
}

exit 0
'@

Set-Content -LiteralPath (Join-Path $FakeBin 'docker-fake.ps1') -Value $FakeDocker -Encoding UTF8
Set-Content -LiteralPath (Join-Path $FakeBin 'docker.cmd') -Value '@powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0docker-fake.ps1" %*' -Encoding ASCII

$OldPath = $env:PATH
$OldState = $env:ARCHIMEDES_TEST_STATE
$OldLog = $env:ARCHIMEDES_TEST_LOG

try {
    $env:PATH = "$FakeBin;$OldPath"
    $env:ARCHIMEDES_TEST_STATE = $StateFile
    $env:ARCHIMEDES_TEST_LOG = $LogFile

    & $ArchimedesPath `
        -SourceMode local `
        -Image 'fake:test' `
        -ExportMode image `
        -ExportDirectory $ExportDir `
        -DistributionName 'Fake-Distro' `
        -NonInteractive

    if ($LASTEXITCODE -notin @(0, $null)) { throw "Archimedes exited with code $LASTEXITCODE" }

    $Commands = Get-Content -LiteralPath $LogFile
    if (-not ($Commands -match '^desktop start(?: |$)')) {
        throw 'Expected Archimedes to start Docker Desktop after the initial daemon check failed.'
    }

    $ExpectedArchive = Join-Path $ExportDir 'Fake-Distro-docker-image.tar'
    if (-not (Test-Path -LiteralPath $ExpectedArchive)) {
        throw "Expected export was not created: $ExpectedArchive"
    }

    Write-Host 'PASS: stopped Docker Desktop is started automatically and the operation continues.'
}
finally {
    $env:PATH = $OldPath
    $env:ARCHIMEDES_TEST_STATE = $OldState
    $env:ARCHIMEDES_TEST_LOG = $OldLog
    Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
