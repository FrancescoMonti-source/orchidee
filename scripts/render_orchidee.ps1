[CmdletBinding()]
param(
  [ValidateSet('memo','meeting','docs','indicators','full')]
  [string]$Target = 'docs',
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot

function Resolve-Quarto {
  $candidates = @()
  if ($env:ORCHIDEE_QUARTO -and (Test-Path $env:ORCHIDEE_QUARTO)) { $candidates += $env:ORCHIDEE_QUARTO }
  $cmd = Get-Command quarto -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }
  $candidates += @(
    'C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe',
    'C:\Program Files\Quarto\bin\quarto.exe'
  )
  foreach ($candidate in $candidates | Select-Object -Unique) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  throw 'Quarto executable not found. Set ORCHIDEE_QUARTO or install Quarto.'
}

function Resolve-RScript {
  $candidates = @()
  if ($env:ORCHIDEE_R -and (Test-Path $env:ORCHIDEE_R)) { $candidates += $env:ORCHIDEE_R }
  if ($env:QUARTO_R -and (Test-Path $env:QUARTO_R)) { $candidates += $env:QUARTO_R }
  $cmd = Get-Command Rscript -ErrorAction SilentlyContinue
  if ($cmd) { $candidates += $cmd.Source }
  $candidates += @(
    'C:\Program Files\R\R-4.5.2\bin\Rscript.exe',
    'C:\Program Files\R\R-4.5.1\bin\Rscript.exe',
    'C:\Program Files\R\R-4.4.3\bin\Rscript.exe'
  )
  foreach ($candidate in $candidates | Select-Object -Unique) {
    if ($candidate -and (Test-Path $candidate)) { return $candidate }
  }
  return $null
}

$quarto = Resolve-Quarto
$rScript = Resolve-RScript
if ($rScript) { $env:QUARTO_R = $rScript }

$targets = switch ($Target) {
  'memo' {
    @('documentation/ratb_implementation_decisions.qmd')
  }
  'meeting' {
    @('documentation/ratb_meeting_prep_spf.qmd')
  }
  'docs' {
    @(
      'documentation/ratb_implementation_decisions.qmd',
      'documentation/ratb_meeting_prep_spf.qmd'
    )
  }
  'indicators' {
    @('orchidee_ratb_indicators.qmd')
  }
  'full' {
    @(
      'orchidee_dedup_workflow.qmd',
      'orchidee_ratb_indicators.qmd'
    )
  }
}

Write-Host "Repo: $RepoRoot"
Write-Host "Target: $Target"
Write-Host "Quarto: $quarto"
if ($rScript) {
  Write-Host "QUARTO_R: $rScript"
} else {
  Write-Warning 'No explicit Rscript found. Quarto will use its default R resolution.'
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
