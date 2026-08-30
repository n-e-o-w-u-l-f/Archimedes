[CmdletBinding()]
param(
    [ValidateSet('pull','local','build')]
    [string]$SourceMode,
    [string]$Image,
    [string]$BuildContext = '.',
    [string]$Dockerfile,
    [ValidateSet('image','rootfs','both','wsl','all')]
    [string]$ExportMode,
    [string]$ExportDirectory,
    [string]$DistributionName,
    [string]$WSLDistributionName,
    [string]$WSLInstallDirectory,
    [switch]$ImportToWSL,
    [switch]$Force,
    [switch]$NonInteractive,
    [switch]$NoAutoStartDocker,
    [ValidateRange(5,600)]
    [int]$DockerStartupTimeoutSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Section {
    param([Parameter(Mandatory)][string]$Text)
    Write-Host ''
    Write-Host ('=' * 72)
    Write-Host $Text
    Write-Host ('=' * 72)
}

function Test-IsWindows {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return $true }
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}

function Require-Command {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Assert-ExitCode {
    param([Parameter(Mandatory)][string]$Operation)
    if ($LASTEXITCODE -ne 0) {
        throw "$Operation failed with exit code $LASTEXITCODE"
    }
}

function Invoke-Probe {
    param([Parameter(Mandatory)][scriptblock]$Script)
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $Script
        return $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Test-DockerDaemon {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & docker info *> $null
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Get-DockerContextName {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $context = & docker context show 2>$null
        if ($LASTEXITCODE -eq 0 -and $context) {
            return (($context | Select-Object -Last 1).ToString().Trim())
        }
    }
    finally {
        $ErrorActionPreference = $previous
    }
    return '<unknown>'
}

function Wait-DockerDaemon {
    param([Parameter(Mandatory)][int]$TimeoutSeconds)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    do {
        if (Test-DockerDaemon) { return $true }
        Start-Sleep -Seconds 2
    } while ([DateTime]::UtcNow -lt $deadline)
    return $false
}

function Start-DockerDesktopIfAvailable {
    param([Parameter(Mandatory)][int]$TimeoutSeconds)
    if (-not $script:IsWindows) { return $false }

    $previous = $ErrorActionPreference
    $desktopCliAvailable = $false
    try {
        $ErrorActionPreference = 'Continue'
        & docker desktop version *> $null
        $desktopCliAvailable = ($LASTEXITCODE -eq 0)
    }
    finally {
        $ErrorActionPreference = $previous
    }

    if ($desktopCliAvailable) {
        Write-Host 'Docker daemon is not reachable. Starting Docker Desktop...'
        $exitCode = 0
        try {
            $ErrorActionPreference = 'Continue'
            & docker desktop start --timeout $TimeoutSeconds
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previous
        }
        if ($exitCode -ne 0) {
            Write-Warning "docker desktop start returned exit code $exitCode; waiting for the daemon anyway."
        }
        return (Wait-DockerDaemon -TimeoutSeconds $TimeoutSeconds)
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'),
        (Join-Path $env:LOCALAPPDATA 'Docker\Docker Desktop.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            Write-Host "Docker daemon is not reachable. Starting Docker Desktop: $candidate"
            Start-Process -FilePath $candidate | Out-Null
            return (Wait-DockerDaemon -TimeoutSeconds $TimeoutSeconds)
        }
    }
    return $false
}

function Get-DockerDaemonDiagnostic {
    $previous = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        return ((& docker info 2>&1 | Out-String).Trim())
    }
    finally {
        $ErrorActionPreference = $previous
    }
}

function Ensure-DockerDaemon {
    if (Test-DockerDaemon) { return }
    $context = Get-DockerContextName

    if ($script:IsWindows -and -not $NoAutoStartDocker) {
        if (Start-DockerDesktopIfAvailable -TimeoutSeconds $DockerStartupTimeoutSeconds) {
            Write-Host "Docker daemon is ready (context: $(Get-DockerContextName))."
            return
        }
    }

    $details = Get-DockerDaemonDiagnostic
    $hint = if ($script:IsWindows) {
        if ($NoAutoStartDocker) {
            'Automatic Docker Desktop startup is disabled by -NoAutoStartDocker. Start Docker Desktop or another Docker Engine and retry.'
        } else {
            'Start Docker Desktop (or another Docker Engine) and retry.'
        }
    } else {
        'Start the Docker daemon for the active context and retry.'
    }
    throw "Docker CLI is installed, but no Docker daemon is reachable (context: $context). $hint`n$details"
}

function Read-Choice {
    param(
        [Parameter(Mandatory)][string]$Prompt,
        [Parameter(Mandatory)][hashtable]$Choices,
        [string]$Default
    )
    while ($true) {
        Write-Host $Prompt
        foreach ($key in ($Choices.Keys | Sort-Object)) {
            Write-Host "  [$key] $($Choices[$key])"
        }
        $suffix = if ($Default) { " [$Default]" } else { '' }
        $value = Read-Host "Select$suffix"
        if ([string]::IsNullOrWhiteSpace($value) -and $Default) { $value = $Default }
        if ($Choices.ContainsKey($value)) { return $value }
        Write-Warning "Invalid selection: $value"
    }
}

function Read-YesNo {
    param([Parameter(Mandatory)][string]$Prompt,[bool]$Default = $false)
    $hint = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $value = (Read-Host "$Prompt $hint").Trim().ToLowerInvariant()
        if (-not $value) { return $Default }
        if ($value -in @('y','yes','j','ja')) { return $true }
        if ($value -in @('n','no','nein')) { return $false }
        Write-Warning 'Please answer yes or no.'
    }
}

function ConvertTo-SafeName {
    param([Parameter(Mandatory)][string]$Value)
    $name = $Value.Trim()
    $name = $name -replace '^.*/', ''
    $name = $name -replace '[:@/\\\s]+', '-'
    $name = $name -replace '[^A-Za-z0-9._-]', '-'
    $name = $name -replace '-+', '-'
    $name = $name.Trim('-','.')
    if (-not $name) { return 'archimedes-export' }
    return $name
}

function ConvertTo-WSLDistributionName {
    param([Parameter(Mandatory)][string]$Value)
    $name = $Value.Trim()
    $name = $name -replace '\s+', '-'
    $name = $name -replace '[^A-Za-z0-9._-]', '-'
    $name = $name -replace '-+', '-'
    $name = $name.Trim('-','_','.')
    if (-not $name) { return 'Archimedes-WSL' }
    return $name
}

function Resolve-DockerImageReference {
    param([Parameter(Mandatory)][string]$Value)

    $reference = $Value.Trim()
    $compact = ($reference.ToLowerInvariant() -replace '\s+', '')

    switch -Regex ($compact) {
        '^ubuntu(?:[-_]?v?)?(\d{2}\.\d{2})$' { return "ubuntu:$($Matches[1])" }
        '^debian(?:[-_]?v?)?(\d+|testing|sid)$' { return "debian:$($Matches[1])" }
        '^fedora(?:[-_]?v?)?(\d+|rawhide)$' { return "fedora:$($Matches[1])" }
        '^alpine(?:[-_]?v?)?(\d+\.\d+|edge)$' { return "alpine:$($Matches[1])" }
        '^(?:rocky|rockylinux)(?:[-_]?v?)?(\d+)$' { return "rockylinux/rockylinux:$($Matches[1])" }
        '^(?:alma|almalinux)(?:[-_]?v?)?(\d+)$' { return "almalinux:$($Matches[1])" }
        '^(?:oracle|oraclelinux)(?:[-_]?v?)?(\d+)$' { return "oraclelinux:$($Matches[1])" }
        '^mageia(?:[-_]?v?)?(\d+)$' { return "mageia:$($Matches[1])" }
        '^(?:arch|archlinux)(?:[-_]?latest)?$' { return 'archlinux:latest' }
        '^(?:kali|kalirolling|kali-rolling)$' { return 'kalilinux/kali-rolling:latest' }
        '^(?:opensuse[-_]?tumbleweed|tumbleweed)$' { return 'opensuse/tumbleweed:latest' }
        default { return $reference }
    }
}

function Confirm-OutputPath {
    param([Parameter(Mandatory)][string]$Path)
    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        if ($NonInteractive) { throw "Output already exists: $Path. Use -Force to overwrite." }
        if (-not (Read-YesNo "Overwrite '$Path'?" $false)) {
            throw "Cancelled because output exists: $Path"
        }
    }
}

function New-RootFsTar {
    param([Parameter(Mandatory)][string]$ImageRef,[Parameter(Mandatory)][string]$OutputPath)
    Confirm-OutputPath $OutputPath
    $container = $null
    try {
        $container = (& docker create $ImageRef 2>$null)
        if ($LASTEXITCODE -ne 0 -or -not $container) {
            $container = (& docker create $ImageRef /bin/sh)
            Assert-ExitCode "docker create $ImageRef"
        }
        $container = ($container | Select-Object -Last 1).Trim()
        if (-not $container) { throw "Docker did not return a container ID for $ImageRef" }
        & docker export --output $OutputPath $container
        Assert-ExitCode "docker export $ImageRef"
    }
    finally {
        if ($container) { & docker rm $container 2>$null | Out-Null }
    }
    if (-not (Test-Path -LiteralPath $OutputPath)) {
        throw "RootFS export was not created: $OutputPath"
    }
}

function New-DockerImageTar {
    param([Parameter(Mandatory)][string]$ImageRef,[Parameter(Mandatory)][string]$OutputPath)
    Confirm-OutputPath $OutputPath
    & docker save --output $OutputPath $ImageRef
    Assert-ExitCode "docker save $ImageRef"
}

function Get-WSLNames {
    if (-not $script:IsWindows) { return @() }
    $names = & wsl.exe --list --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { return @() }
    return @($names | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Import-RootFsToWSL {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$RootFsTar,
        [Parameter(Mandatory)][string]$InstallDirectory
    )
    Require-Command 'wsl.exe'
    if ((Get-WSLNames) -contains $Name) {
        throw "WSL distribution '$Name' already exists. Archimedes never unregisters or overwrites an existing WSL distribution automatically."
    }
    New-Item -ItemType Directory -Force -Path $InstallDirectory | Out-Null
    & wsl.exe --import $Name $InstallDirectory $RootFsTar --version 2
    Assert-ExitCode "wsl.exe --import $Name"
}

function Export-WSLDistribution {
    param([Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$OutputPath)
    Confirm-OutputPath $OutputPath
    & wsl.exe --export $Name $OutputPath
    Assert-ExitCode "wsl.exe --export $Name"
}

function Get-PresetImage {
    $presets = [ordered]@{
        '1'=@{Label='Debian 13';Image='debian:13'}
        '2'=@{Label='Ubuntu 24.04 LTS';Image='ubuntu:24.04'}
        '3'=@{Label='Ubuntu 26.04 LTS';Image='ubuntu:26.04'}
        '4'=@{Label='Fedora 44';Image='fedora:44'}
        '5'=@{Label='Alpine 3.22';Image='alpine:3.22'}
        '6'=@{Label='Arch Linux';Image='archlinux:latest'}
        '7'=@{Label='Rocky Linux 10';Image='rockylinux/rockylinux:10'}
        '8'=@{Label='AlmaLinux 10';Image='almalinux:10'}
        '9'=@{Label='Kali Rolling';Image='kalilinux/kali-rolling:latest'}
        '10'=@{Label='openSUSE Tumbleweed';Image='opensuse/tumbleweed:latest'}
        '11'=@{Label='Custom image reference';Image=$null}
    }
    Write-Host 'Available presets:'
    foreach ($key in $presets.Keys) {
        $entry = $presets[$key]
        $imageText = if ($entry.Image) { " ($($entry.Image))" } else { '' }
        Write-Host "  [$key] $($entry.Label)$imageText"
    }
    while ($true) {
        $choice = Read-Host 'Select image'
        if ($presets.Contains($choice)) {
            if ($presets[$choice].Image) { return $presets[$choice].Image }
            return (Read-Host 'Docker image reference (for example debian:13)').Trim()
        }
        Write-Warning "Invalid selection: $choice"
    }
}

$script:IsWindows = Test-IsWindows
Write-Host 'Archimedes - Docker image and RootFS export utility'
Require-Command 'docker'
Ensure-DockerDaemon

if (-not $SourceMode) {
    if ($NonInteractive) { throw '-SourceMode is required with -NonInteractive.' }
    $choice = Read-Choice 'How should the Docker image be obtained?' ([ordered]@{
        '1'='Pull an image from a registry'
        '2'='Use an image that already exists locally'
        '3'='Build an image from a Dockerfile'
    }) '1'
    $SourceMode = @{'1'='pull';'2'='local';'3'='build'}[$choice]
}

switch ($SourceMode) {
    'pull' {
        if (-not $Image) {
            if ($NonInteractive) { throw '-Image is required for source mode pull.' }
            $Image = Get-PresetImage
        }
        if (-not $Image) { throw 'Image reference cannot be empty.' }
        $requestedImage = $Image
        $Image = Resolve-DockerImageReference $Image
        if ($Image -ne $requestedImage) {
            Write-Host "Resolved image reference: $requestedImage -> $Image"
        }
        Write-Section "Pulling $Image"
        & docker pull $Image
        Assert-ExitCode "docker pull $Image"
    }
    'local' {
        if (-not $Image) {
            if ($NonInteractive) { throw '-Image is required for source mode local.' }
            $Image = (Read-Host 'Local Docker image reference').Trim()
        }
        & docker image inspect $Image *> $null
        Assert-ExitCode "docker image inspect $Image"
    }
    'build' {
        if (-not $Image) {
            if ($NonInteractive) { throw '-Image is required as the tag for source mode build.' }
            $Image = (Read-Host 'Tag for the new Docker image').Trim()
        }
        if (-not $Dockerfile) { $Dockerfile = Join-Path $BuildContext 'Dockerfile' }
        if (-not (Test-Path -LiteralPath $BuildContext)) { throw "Build context does not exist: $BuildContext" }
        if (-not (Test-Path -LiteralPath $Dockerfile)) { throw "Dockerfile does not exist: $Dockerfile" }
        Write-Section "Building $Image"
        & docker build --file $Dockerfile --tag $Image $BuildContext
        Assert-ExitCode "docker build $Image"
    }
}

if (-not $DistributionName) { $DistributionName = ConvertTo-SafeName $Image }
if (-not $ExportDirectory) {
    if ($NonInteractive) {
        $ExportDirectory = (Join-Path (Get-Location) 'exports').Path
    } else {
        $defaultExport = (Join-Path (Get-Location) 'exports').Path
        $value = Read-Host "Export directory [$defaultExport]"
        $ExportDirectory = if ([string]::IsNullOrWhiteSpace($value)) { $defaultExport } else { $value.Trim('"') }
    }
}
$ExportDirectory = [System.IO.Path]::GetFullPath($ExportDirectory)
New-Item -ItemType Directory -Force -Path $ExportDirectory | Out-Null

if (-not $ExportMode) {
    if ($NonInteractive) { throw '-ExportMode is required with -NonInteractive.' }
    $choices = [ordered]@{
        '1'='Docker image archive (.tar) - preserves image layers/tags; restore with docker load'
        '2'='Container RootFS archive (.tar) - flat filesystem; usable with docker import or WSL2 import'
        '3'='Both Docker image archive and RootFS archive'
    }
    if ($script:IsWindows) {
        $choices['4']='WSL2 distribution archive (.tar) - import RootFS then export with wsl --export'
        $choices['5']='All formats: Docker image + RootFS + WSL2 distribution archive'
    }
    $choice = Read-Choice 'What should Archimedes export?' $choices '3'
    $ExportMode = @{'1'='image';'2'='rootfs';'3'='both';'4'='wsl';'5'='all'}[$choice]
}

if (($ExportMode -in @('wsl','all')) -and -not $script:IsWindows) {
    throw "Export mode '$ExportMode' requires Windows with WSL2."
}
if ($ImportToWSL -and -not $script:IsWindows) {
    throw '-ImportToWSL is available only on Windows.'
}

$needsImageTar = $ExportMode -in @('image','both','all')
$needsRootFs = $ExportMode -in @('rootfs','both','wsl','all') -or $ImportToWSL
$needsWSLExport = $ExportMode -in @('wsl','all')

if ($script:IsWindows -and -not $NonInteractive -and -not $ImportToWSL -and -not $needsWSLExport) {
    if (Read-YesNo 'Import the exported RootFS into WSL2 afterwards?' $false) {
        $ImportToWSL = $true
        $needsRootFs = $true
    }
}

$imageTar = Join-Path $ExportDirectory "$DistributionName-docker-image.tar"
$rootFsTar = Join-Path $ExportDirectory "$DistributionName-rootfs.tar"
$wslTar = Join-Path $ExportDirectory "$DistributionName-wsl.tar"

Write-Section 'Export'
Write-Host "Image:          $Image"
Write-Host "Name:           $DistributionName"
Write-Host "Export folder:  $ExportDirectory"
Write-Host "Export mode:    $ExportMode"

if ($needsImageTar) { New-DockerImageTar -ImageRef $Image -OutputPath $imageTar }
if ($needsRootFs) { New-RootFsTar -ImageRef $Image -OutputPath $rootFsTar }

$mustImport = $ImportToWSL -or $needsWSLExport
if ($mustImport) {
    Require-Command 'wsl.exe'
    $requestedWSLName = if ($WSLDistributionName) { $WSLDistributionName } else { $DistributionName }
    $WSLDistributionName = ConvertTo-WSLDistributionName $requestedWSLName
    if ($WSLDistributionName -ne $requestedWSLName) {
        Write-Host "Resolved WSL distribution name: $requestedWSLName -> $WSLDistributionName"
    }
    if (-not $WSLInstallDirectory) {
        $defaultInstall = Join-Path (Join-Path $ExportDirectory 'wsl') $WSLDistributionName
        if ($NonInteractive) {
            $WSLInstallDirectory = $defaultInstall
        } else {
            $value = Read-Host "WSL2 install directory [$defaultInstall]"
            $WSLInstallDirectory = if ([string]::IsNullOrWhiteSpace($value)) { $defaultInstall } else { $value.Trim('"') }
        }
    }
    $WSLInstallDirectory = [System.IO.Path]::GetFullPath($WSLInstallDirectory)
    Import-RootFsToWSL -Name $WSLDistributionName -RootFsTar $rootFsTar -InstallDirectory $WSLInstallDirectory
    if ($needsWSLExport) {
        Export-WSLDistribution -Name $WSLDistributionName -OutputPath $wslTar
    }
}

Write-Section 'Completed'
if ($needsImageTar) { Write-Host "Docker image: $imageTar" }
if ($needsRootFs) { Write-Host "RootFS:       $rootFsTar" }
if ($needsWSLExport) { Write-Host "WSL2 export:  $wslTar" }
if ($mustImport) { Write-Host "WSL2 name:    $WSLDistributionName" }
