[CmdletBinding()]
param(
  [ValidateSet('memo','docs','indicators','full')]
  [string]$Target = 'docs',
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'orchidee_environment.ps1')

function Resolve-Quarto {
  $candidates = @()
  if ($env:ORCHIDEE_QUARTO -and (Test-Path $env:ORCHIDEE_QUARTO)) { $candidates += $env:ORCHIDEE_QUARTO }
  $cmd = Get-Command quarto -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }
  $candidates += @(
    'C:\Program Files\Positron\resources\app\quarto\bin\quarto.exe',
    'C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe',
    'C:\Program Files\Quarto\bin\quarto.exe'
  )
  foreach ($candidate in $candidates | Select-Object -Unique) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  throw 'Quarto executable not found. Set ORCHIDEE_QUARTO or install Quarto.'
}

$quarto = Resolve-Quarto
$rScript = Resolve-OrchideeRScript `
  -RepoRoot $RepoRoot `
  -AdditionalCandidates @($env:QUARTO_R)
$env:QUARTO_R = $rScript

$targets = switch ($Target) {
  'memo' {
    @('documentation/ratb_implementation_decisions.qmd')
  }
  'docs' {
    @('documentation/ratb_implementation_decisions.qmd')
  }
  'indicators' {
    @('orchidee_ratb_indicators.qmd')
  }
  'full' {
    @('orchidee_ratb_indicators.qmd')
  }
}

Write-Host "Repo: $RepoRoot"
Write-Host "Target: $Target"
Write-Host "Quarto: $quarto"
Write-Host "QUARTO_R: $rScript"

if ($Target -eq 'full') {
  $rawBuilder = Join-Path $RepoRoot 'scripts/build_ratb_raw_runtime.R'
  Write-Host (
    "> $rScript --no-save --no-restore scripts/build_ratb_raw_runtime.R"
  )
  if (-not $DryRun) {
    Push-Location $RepoRoot
    try {
      & $rScript --no-save --no-restore $rawBuilder
      if ($LASTEXITCODE -ne 0) {
        throw "Raw RATB cache build failed (exit $LASTEXITCODE)"
      }
    }
    finally {
      Pop-Location
    }
  }
}

foreach ($relativePath in $targets) {
  $fullPath = Join-Path $RepoRoot $relativePath
  if (-not (Test-Path $fullPath)) {
    throw "Missing render target: $relativePath"
  }
  $args = @('render', $relativePath)
  Write-Host "> $quarto $($args -join ' ')"
  if (-not $DryRun) {
    Push-Location $RepoRoot
    try {
      & $quarto @args
      if ($LASTEXITCODE -ne 0) {
        throw "Quarto render failed for $relativePath (exit $LASTEXITCODE)"
      }
    }
    finally {
      Pop-Location
    }
  }
}
