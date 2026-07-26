<#
.SYNOPSIS
Restores the R environment declared by renv.lock.

.DESCRIPTION
Finds the exact R version declared in renv.lock, restores the project library
and verifies installed package versions and sources.

.PARAMETER DryRun
Check only that the locked R executable and renv.lock are available. This does
not restore or verify the installed package library.

.EXAMPLE
& .\scripts\setup.ps1

.EXAMPLE
& .\scripts\setup.ps1 -DryRun
#>

[CmdletBinding()]
param(
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'orchidee_environment.ps1')

$lock = Get-OrchideeLockMetadata -RepoRoot $RepoRoot
$rScript = Resolve-OrchideeRScript -RepoRoot $RepoRoot

Write-Host "Repo:     $RepoRoot"
Write-Host "R:        $rScript"
Write-Host "Lock:     $($lock.Path)"
Write-Host "Packages: $($lock.PackageCount)"

if ($DryRun) {
  Write-Host 'PASS: R and renv.lock are available; no packages were changed.'
  return
}

$setupScript = Join-Path $RepoRoot 'scripts\setup_r_environment.R'
$previousSetupFlag = [System.Environment]::GetEnvironmentVariable(
  'ORCHIDEE_SETUP',
  'Process'
)
[System.Environment]::SetEnvironmentVariable(
  'ORCHIDEE_SETUP',
  '1',
  'Process'
)

Push-Location $RepoRoot
try {
  & $rScript --no-save --no-restore $setupScript
  if ($LASTEXITCODE -ne 0) {
    throw "R dependency restore failed (exit $LASTEXITCODE)."
  }
}
finally {
  Pop-Location
  [System.Environment]::SetEnvironmentVariable(
    'ORCHIDEE_SETUP',
    $previousSetupFlag,
    'Process'
  )
}
