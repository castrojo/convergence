# Offline tests for install.ps1 (no network, no install). Run: pwsh -File tests/test_install.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Failures = 0
$script:Passes = 0
function Assert-True { param([bool]$Cond, [string]$Name)
    if ($Cond) { $script:Passes++; Write-Host "ok: $Name" } else { $script:Failures++; Write-Host "FAIL: $Name" }
}
function Assert-Throws { param([scriptblock]$Block, [string]$Pattern, [string]$Name)
    try { & $Block; Assert-True $false "$Name (no error)" }
    catch { Assert-True ($_.Exception.Message -match $Pattern) "$Name ($($_.Exception.Message))" }
}

$env:CONVERGENCE_INSTALL_NO_MAIN = '1'
. (Join-Path $PSScriptRoot '..' 'install.ps1')

# arch detection
Assert-True ((Get-ConvergenceArch -Arch 'AMD64') -eq 'amd64') 'AMD64 -> amd64'
Assert-True ((Get-ConvergenceArch -Arch 'ARM64') -eq 'arm64') 'ARM64 -> arm64'
Assert-Throws { Get-ConvergenceArch -Arch 'x86' } 'Unsupported architecture' 'x86 refused'

# release URL
Assert-True ((Get-ReleaseBaseUrl -Version 'latest') -eq 'https://github.com/jeefy/convergence/releases/latest/download') 'latest url'
Assert-True ((Get-ReleaseBaseUrl -Version 'v0.1.0') -eq 'https://github.com/jeefy/convergence/releases/download/v0.1.0') 'tag url'
Assert-True ((Get-ReleaseBaseUrl -Version '0.1.0') -eq 'https://github.com/jeefy/convergence/releases/download/v0.1.0') 'bare version gets v prefix'
Assert-True ((Get-ArchiveName -Arch 'amd64') -eq 'convergence_windows_amd64.zip') 'archive name'

# checksum verification
$work = Join-Path ([IO.Path]::GetTempPath()) ("convergence-test-" + [IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $work | Out-Null
try {
    $asset = Join-Path $work 'convergence_windows_amd64.zip'
    [IO.File]::WriteAllText($asset, 'hello')
    $good = (Get-FileHash -Path $asset -Algorithm SHA256).Hash.ToLowerInvariant()
    $sums = Join-Path $work 'checksums.txt'

    "$good  convergence_windows_amd64.zip`n0000  other.tar.gz" | Set-Content -Path $sums
    Test-Checksum -FilePath $asset -ChecksumsPath $sums -Name 'convergence_windows_amd64.zip'
    Assert-True $true 'matching checksum accepted'

    "$($good.ToUpperInvariant()) *convergence_windows_amd64.zip" | Set-Content -Path $sums
    Test-Checksum -FilePath $asset -ChecksumsPath $sums -Name 'convergence_windows_amd64.zip'
    Assert-True $true 'binary-mode (*) entry and upper-case hash accepted'

    "deadbeef  convergence_windows_amd64.zip" | Set-Content -Path $sums
    Assert-Throws { Test-Checksum -FilePath $asset -ChecksumsPath $sums -Name 'convergence_windows_amd64.zip' } 'Checksum mismatch' 'mismatch refused'

    "0000  other.tar.gz" | Set-Content -Path $sums
    Assert-Throws { Test-Checksum -FilePath $asset -ChecksumsPath $sums -Name 'convergence_windows_amd64.zip' } 'No checksum for' 'missing entry refused'
} finally {
    Remove-Item -Path $work -Recurse -Force
}

# install dir
Assert-True ((Get-InstallDir -Override 'C:\x') -eq 'C:\x') 'INSTALL_DIR override wins'
$env:LOCALAPPDATA = $PSScriptRoot
Assert-True ((Get-InstallDir -Override '') -eq (Join-Path $PSScriptRoot 'Programs\convergence')) 'default under LOCALAPPDATA'
$env:LOCALAPPDATA = ''
Assert-Throws { Get-InstallDir -Override '' } 'LOCALAPPDATA' 'no LOCALAPPDATA refused'

# never elevates
$src = Get-Content -Raw (Join-Path $PSScriptRoot '..' 'install.ps1')
Assert-True ($src -notmatch 'RunAs|Start-Process .*-Verb') 'no elevation'

Write-Host ''
if ($script:Failures -gt 0) { Write-Host "$($script:Failures) failed"; exit 1 }
Write-Host "Installer tests passed ($($script:Passes))."
