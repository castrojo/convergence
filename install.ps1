# install.ps1 - Convergence installer for Windows
# Usage: irm https://raw.githubusercontent.com/jeefy/convergence/main/install.ps1 | iex
#
# Environment:
#   CONVERGENCE_VERSION  release tag to install (e.g. v0.1.0) or "latest" (default)
#   INSTALL_DIR          target directory (default: %LOCALAPPDATA%\Programs\convergence)
#
# Downloads convergence_windows_<arch>.zip and checksums.txt from the GitHub
# release, refuses to install if the sha256 does not match, and adds the target
# directory to the user PATH. It never elevates.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Repo = 'jeefy/convergence'
$script:BinName = 'convergence'

function Write-Info { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Blue }
function Write-Ok { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) [Console]::Error.WriteLine("[ERROR] $Message") }

function Get-ConvergenceArch {
    param([string]$Arch = $env:PROCESSOR_ARCHITECTURE)
    switch -Regex ($Arch) {
        '^(AMD64|x86_64|x64)$' { return 'amd64' }
        '^(ARM64|aarch64)$' { return 'arm64' }
        default { throw "Unsupported architecture: $Arch. Supported: amd64, arm64." }
    }
}

function Get-ReleaseBaseUrl {
    param([string]$Version = $(if ($env:CONVERGENCE_VERSION) { $env:CONVERGENCE_VERSION } else { 'latest' }))
    if ($Version -eq 'latest') {
        return "https://github.com/$script:Repo/releases/latest/download"
    }
    $tag = if ($Version.StartsWith('v')) { $Version } else { "v$Version" }
    return "https://github.com/$script:Repo/releases/download/$tag"
}

function Get-ArchiveName {
    param([Parameter(Mandatory)][string]$Arch)
    return "${script:BinName}_windows_${Arch}.zip"
}

# Returns the expected sha256 for $Name from a checksums.txt, or throws.
function Get-ExpectedChecksum {
    param([Parameter(Mandatory)][string]$ChecksumsPath, [Parameter(Mandatory)][string]$Name)
    foreach ($line in Get-Content -Path $ChecksumsPath) {
        $parts = $line -split '\s+', 2
        if ($parts.Count -ne 2) { continue }
        $file = $parts[1].TrimStart('*')
        if ($file -eq $Name) { return $parts[0].ToLowerInvariant() }
    }
    throw "No checksum for $Name in checksums.txt. Refusing to install."
}

function Test-Checksum {
    param([Parameter(Mandatory)][string]$FilePath, [Parameter(Mandatory)][string]$ChecksumsPath, [Parameter(Mandatory)][string]$Name)
    $expected = Get-ExpectedChecksum -ChecksumsPath $ChecksumsPath -Name $Name
    $actual = (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($expected -ne $actual) {
        throw "Checksum mismatch for ${Name}: expected $expected, got $actual. Refusing to install."
    }
    Write-Ok "Checksum verified (sha256 $actual)"
}

function Get-InstallDir {
    param([string]$Override = $env:INSTALL_DIR)
    if ($Override) { return $Override }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set and INSTALL_DIR was not given.' }
    return Join-Path $env:LOCALAPPDATA 'Programs\convergence'
}

function Add-UserPath {
    param([Parameter(Mandatory)][string]$Dir)
    $current = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = @()
    if ($current) { $entries = $current -split ';' | Where-Object { $_ } }
    if ($entries -contains $Dir) { return $false }
    [Environment]::SetEnvironmentVariable('Path', (($entries + $Dir) -join ';'), 'User')
    $env:Path = "$env:Path;$Dir"
    return $true
}

function Test-Prerequisites {
    $docker = Get-Command docker -ErrorAction SilentlyContinue
    if ($docker) {
        Write-Ok 'Found docker'
    } else {
        Write-Warn "No docker found. The local stack ('convergence start') is supported through WSL2 only;"
        Write-Warn "native Windows runs the client config writers and commands against a remote gateway or cluster."
    }
}

function Install-Convergence {
    $arch = Get-ConvergenceArch
    Write-Info "Detected platform: windows/$arch"
    Test-Prerequisites

    $base = Get-ReleaseBaseUrl
    $asset = Get-ArchiveName -Arch $arch
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ("convergence-install-" + [IO.Path]::GetRandomFileName())
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Write-Info "Downloading $base/$asset"
        try {
            Invoke-WebRequest -Uri "$base/$asset" -OutFile (Join-Path $tmp $asset) -UseBasicParsing
        } catch {
            throw "Download failed: $($_.Exception.Message). Check that the release exists for windows/$arch at https://github.com/$script:Repo/releases"
        }
        try {
            Invoke-WebRequest -Uri "$base/checksums.txt" -OutFile (Join-Path $tmp 'checksums.txt') -UseBasicParsing
        } catch {
            throw 'Could not download checksums.txt. Refusing to install an unverified binary.'
        }
        Test-Checksum -FilePath (Join-Path $tmp $asset) -ChecksumsPath (Join-Path $tmp 'checksums.txt') -Name $asset

        Expand-Archive -Path (Join-Path $tmp $asset) -DestinationPath (Join-Path $tmp 'x') -Force
        $exe = Join-Path $tmp "x\$script:BinName.exe"
        if (-not (Test-Path $exe)) { throw "$script:BinName.exe not found in $asset" }

        $dir = Get-InstallDir
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Copy-Item -Path $exe -Destination (Join-Path $dir "$script:BinName.exe") -Force
        Write-Ok "Installed $(Join-Path $dir "$script:BinName.exe")"

        if (Add-UserPath -Dir $dir) {
            Write-Info "Added $dir to your user PATH. Open a new terminal to pick it up."
        }
    } finally {
        Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Ok 'Convergence installation complete.'
    Write-Host 'Next steps:'
    Write-Host '  convergence config list        # see which clients can be pointed at a gateway'
    Write-Host '  convergence config <client> --gateway-url http://<gateway>:3000'
}

# Run when executed or piped (irm | iex), not when dot-sourced by tests.
if ($MyInvocation.InvocationName -ne '.' -and -not $env:CONVERGENCE_INSTALL_NO_MAIN) {
    Install-Convergence
}
