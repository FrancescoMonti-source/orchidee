<#
.SYNOPSIS
Renders the ORCHIDEE indicator report with the locked R environment.

.DESCRIPTION
Resolves Quarto and the locked R installation, checks the packages and inputs
the render needs, then renders the indicator report. The effective bundle and
workspace are displayed before any work.

.PARAMETER Rebuild
Rebuild the canonical raw runtime cache even when it is already current. Every
render checks the cache against both its input bundle and the code that
produces it, and rebuilds it when either changed, so this switch is only needed
to force the work anyway.

.PARAMETER Bundle
Explicit external_bundle_v2 directory. Relative paths are resolved from the
repository root. This takes precedence over ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR
for this invocation only.

.PARAMETER Workspace
Explicit private runtime workspace. Relative paths are resolved from the
repository root. This takes precedence over ORCHIDEE_EXTERNAL_WORKSPACE_DIR
for this invocation only.

.PARAMETER DryRun
Check Quarto, locked R, required packages and data paths, then print the
commands without building the runtime or rendering documents.

.EXAMPLE
& .\scripts\render_orchidee.ps1

.EXAMPLE
& .\scripts\render_orchidee.ps1 -Rebuild `
  -Bundle "outputs\rouen_current\bundle_v2_operational" `
  -Workspace "outputs\rouen_current\runtime"
#>

[CmdletBinding()]
param(
  [switch]$Rebuild,

  [string]$Bundle,

  [string]$Workspace,

  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'orchidee_environment.ps1')

function Resolve-Quarto {
  $candidates = @()
  if ($env:ORCHIDEE_QUARTO) {
    if (
      -not (
        Test-Path -LiteralPath $env:ORCHIDEE_QUARTO -PathType Leaf
      )
    ) {
      throw (
        'ORCHIDEE_QUARTO must point to a Quarto executable file: ' +
        $env:ORCHIDEE_QUARTO
      )
    }
    $candidates += $env:ORCHIDEE_QUARTO
  }
  $cmd = Get-Command quarto -ErrorAction SilentlyContinue
  if ($cmd) {
    $candidates += $cmd.Source
  }
  $candidates += @(
    'C:\Program Files\Positron\resources\app\quarto\bin\quarto.exe',
    'C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe',
    'C:\Program Files\Quarto\bin\quarto.exe'
  )
  foreach ($candidate in $candidates | Select-Object -Unique) {
    if (
      $candidate -and
      (Test-Path -LiteralPath $candidate -PathType Leaf)
    ) {
      return $candidate
    }
  }
  throw 'Quarto executable not found. Set ORCHIDEE_QUARTO or install Quarto.'
}

function Resolve-RepoPath {
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'Bundle and workspace paths cannot be empty.'
  }

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Restore-ProcessEnvironmentVariable {
  param(
    [Parameter(Mandatory)]
    [string]$Name,

    [AllowNull()]
    # [string] would coerce an absent value ($null) to "" and prevent removal.
    [object]$Value
  )

  if ($null -eq $Value) {
    Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    return
  }

  [System.Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

$previousBundle = [System.Environment]::GetEnvironmentVariable(
  'ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR',
  'Process'
)
$previousWorkspace = [System.Environment]::GetEnvironmentVariable(
  'ORCHIDEE_EXTERNAL_WORKSPACE_DIR',
  'Process'
)
$previousQuartoR = [System.Environment]::GetEnvironmentVariable(
  'QUARTO_R',
  'Process'
)
$bundleWasExplicit = $PSBoundParameters.ContainsKey('Bundle')
$workspaceWasExplicit = $PSBoundParameters.ContainsKey('Workspace')

try {
  if ($bundleWasExplicit) {
    $env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR = Resolve-RepoPath -Path $Bundle
  }
  if ($workspaceWasExplicit) {
    $env:ORCHIDEE_EXTERNAL_WORKSPACE_DIR = Resolve-RepoPath -Path $Workspace
  }

  $quarto = Resolve-Quarto
  $quartoVersionOutput = @(& $quarto --version)
  if ($LASTEXITCODE -ne 0) {
    throw "Quarto failed its version check (exit $LASTEXITCODE): $quarto"
  }
  $quartoVersion = ($quartoVersionOutput -join ' ').Trim()
  if (
    $quartoVersion -notmatch
      '^\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?$'
  ) {
    throw "Unexpected Quarto version output from ${quarto}: $quartoVersion"
  }
  $rScript = Resolve-OrchideeRScript `
    -RepoRoot $RepoRoot `
    -AdditionalCandidates @($env:QUARTO_R)
  $env:QUARTO_R = $rScript

  $targets = @('orchidee_ratb_indicators.qmd')

  Write-Host "Repo: $RepoRoot"
  Write-Host "Rebuild: $($Rebuild.IsPresent)"
  Write-Host "Quarto: $quarto ($quartoVersion)"
  Write-Host "QUARTO_R: $rScript"

  $bundleValue = $env:ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR
  $workspaceValue = $env:ORCHIDEE_EXTERNAL_WORKSPACE_DIR
  $bundleSource = if ($bundleWasExplicit) {
    '-Bundle parameter'
  } elseif ($bundleValue) {
    'environment variable ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR'
  } else {
    'config/pipeline.R default'
  }
  $workspaceSource = if ($workspaceWasExplicit) {
    '-Workspace parameter'
  } elseif ($workspaceValue) {
    'environment variable ORCHIDEE_EXTERNAL_WORKSPACE_DIR'
  } else {
    'config/pipeline.R default'
  }

  Write-Host "Bundle source: $bundleSource"
  Write-Host "Workspace source: $workspaceSource"
  if (-not $bundleWasExplicit -and $bundleValue) {
    Write-Warning (
      'A bundle environment override is active. This render may not use ' +
      'the Rouen bundle just built. Pass -Bundle explicitly to bind the ' +
      'intended bundle to this invocation.'
    )
  }

  $renderProbe = Join-Path $RepoRoot 'scripts\check_render_environment.R'
  $probeArgs = @('--no-save', '--no-restore', $renderProbe)
  Push-Location $RepoRoot
  try {
    & $rScript @probeArgs
    if ($LASTEXITCODE -ne 0) {
      throw (
        'Render preflight failed. Review the R error above; correct the ' +
        'bundle/workspace path or run & .\scripts\setup.ps1 when packages ' +
        'are missing.'
      )
    }
  }
  finally {
    Pop-Location
  }

  # The builder decides for itself whether the cache is current, so running it
  # unconditionally is what keeps -Rebuild from being a rule to remember.
  $rawBuilder = Join-Path $RepoRoot 'scripts\build_ratb_raw_runtime.R'
  $rawBuilderArgs = @('--no-save', '--no-restore', $rawBuilder)
  $rawBuilderDisplay = '> ' + $rScript +
    ' --no-save --no-restore scripts/build_ratb_raw_runtime.R'
  if ($Rebuild) {
    $rawBuilderArgs += '--force'
    $rawBuilderDisplay += ' --force'
  }
  Write-Host $rawBuilderDisplay
  if (-not $DryRun) {
    Push-Location $RepoRoot
    try {
      & $rScript @rawBuilderArgs
      if ($LASTEXITCODE -ne 0) {
        throw "Raw RATB cache build failed (exit $LASTEXITCODE)"
      }
    }
    finally {
      Pop-Location
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
}
finally {
  if ($bundleWasExplicit) {
    Restore-ProcessEnvironmentVariable `
      -Name 'ORCHIDEE_EXTERNAL_BUNDLE_V2_DIR' `
      -Value $previousBundle
  }
  if ($workspaceWasExplicit) {
    Restore-ProcessEnvironmentVariable `
      -Name 'ORCHIDEE_EXTERNAL_WORKSPACE_DIR' `
      -Value $previousWorkspace
  }
  Restore-ProcessEnvironmentVariable `
    -Name 'QUARTO_R' `
    -Value $previousQuartoR
}
