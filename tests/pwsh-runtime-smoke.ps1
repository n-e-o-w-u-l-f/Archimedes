$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$pwsh=(Get-Command pwsh -ErrorAction Stop).Source
$temp=Join-Path ([IO.Path]::GetTempPath()) ('archimedes-pwsh-'+[guid]::NewGuid().ToString('N'))
$bin=Join-Path $temp 'bin'; $out=Join-Path $temp 'out'
New-Item -ItemType Directory -Force $bin,$out|Out-Null
try {
    if($IsWindows){
        $fake=Join-Path $bin 'docker.cmd'
        Set-Content $fake '@echo off
if "%1"=="info" exit /b 0
if "%1"=="image" exit /b 0
if "%1"=="save" (type nul > "%3" & exit /b 0)
exit /b 0'
    } else {
        $fake=Join-Path $bin 'docker'
        Set-Content $fake '#!/bin/sh
if [ "$1" = info ]; then exit 0; fi
if [ "$1" = image ]; then exit 0; fi
if [ "$1" = save ]; then : > "$3"; exit 0; fi
exit 0'
        & chmod +x $fake
    }
    $oldPath=$env:PATH; $env:PATH="$bin$([IO.Path]::PathSeparator)$oldPath"
    & $pwsh -NoProfile -File (Join-Path $root 'archimedes.ps1') -SourceMode local -Image fake:test -ExportMode image -ExportDirectory $out -DistributionName Pwsh-Test -NonInteractive
    if($LASTEXITCODE -ne 0){throw "pwsh Archimedes runtime failed: $LASTEXITCODE"}
    if(-not (Test-Path (Join-Path $out 'Pwsh-Test-docker-image.tar'))){throw 'Expected Docker TAR missing'}
    Write-Host 'PASS pwsh runtime smoke'
} finally {
    $env:PATH=$oldPath
    Remove-Item -Recurse -Force $temp -ErrorAction SilentlyContinue
}