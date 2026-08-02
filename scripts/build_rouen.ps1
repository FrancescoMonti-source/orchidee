<#
.SYNOPSIS
Builds the validated ORCHIDEE Rouen bundles from BACT and PMSI inputs.

.DESCRIPTION
This is the routine Rouen operator entry point. It accepts the two protected
clinical input files, uses the versioned Rouen adapter configuration already in
the checkout, retains bundle v3 and creates the operational bundle v2.

.PARAMETER Bact
Path to the automatic long BACT export. Relative paths are resolved from the
repository root. The file may have no extension.

.PARAMETER Pmsi
Path to the PMSI RDS object produced by redsan. Relative paths are resolved
from the repository root. The file may have no extension.

.PARAMETER Output
Dedicated output directory. Defaults to outputs\rouen_current. A destination
inside the checkout must be below outputs\.

.PARAMETER Force
Replace outputs from this same Rouen v3 plus operational-v2 workflow. It cannot
replace an incompatible older layout.

.PARAMETER DryRun
Check the input paths, locked R environment, required packages and effective
Rouen configuration without reading the clinical objects or running the build.

.EXAMPLE
& .\scripts\build_rouen.ps1 `
  -Bact "C:\protected\bact22_24" `
  -Pmsi "C:\protected\pmsi"

.EXAMPLE
& .\scripts\build_rouen.ps1 `
  -Bact "data\bact22_24" `
  -Pmsi "data\pmsi" `
  -DryRun
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string]$Bact,

  [Parameter(Mandatory)]
  [string]$Pmsi,

  [string]$Output,

  [switch]$Force,

  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'orchidee_environment.ps1')
. (Join-Path $PSScriptRoot 'orchidee_operator_paths.ps1')

function Test-RouenRDependencies {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RScript
  )

  $probe = Join-Path $RepoRoot 'scripts\check_rouen_environment.R'

  Push-Location $RepoRoot
  try {
    & $RScript --no-save --no-restore $probe
    if ($LASTEXITCODE -ne 0) {
      throw (
        'The Rouen R environment is not ready. Run ' +
        '& .\scripts\setup.ps1 from the repository root, then retry.'
      )
    }
  }
  finally {
    Pop-Location
  }
}

$bactPath = Resolve-OrchideeInputFile `
  -RepoRoot $RepoRoot `
  -Path $Bact `
  -Label 'BACT'
$pmsiPath = Resolve-OrchideeInputFile `
  -RepoRoot $RepoRoot `
  -Path $Pmsi `
  -Label 'PMSI'
$outputPath = if ([string]::IsNullOrWhiteSpace($Output)) {
  Join-Path $RepoRoot 'outputs\rouen_current'
} else {
  Resolve-OrchideeRepoPath -RepoRoot $RepoRoot -Path $Output
}
$outputPath = Assert-OrchideeSafeOutputDirectory `
  -RepoRoot $RepoRoot `
  -OutputPath $outputPath `
  -InputPaths @($bactPath, $pmsiPath) `
  -InputLabel 'BACT and PMSI inputs'

$operationalV2Path = Join-Path $outputPath 'bundle_v2_operational'
$rScript = Resolve-OrchideeRScript -RepoRoot $RepoRoot
$builder = Join-Path $RepoRoot 'scripts\build_rouen_external_bundle.R'

$incompatibleOutputPaths = @(
  (Join-Path $outputPath 'bundle')
  (Join-Path $outputPath 'site_inputs\denominator_by_year.rds')
)
$existingIncompatibleOutputPaths = @(
  $incompatibleOutputPaths | Where-Object {
    Test-Path -LiteralPath $_
  }
)

$knownOutputPaths = @(
  (Join-Path $outputPath 'site_inputs')
  (Join-Path $outputPath 'bundle_v3')
  $operationalV2Path
  (Join-Path $outputPath 'adapter_audit.rds')
  (Join-Path $outputPath 'build_manifest.txt')
  (Join-Path $outputPath 'build_manifest.txt.tmp')
)
$existingOutputPaths = @(
  $knownOutputPaths | Where-Object {
    Test-Path -LiteralPath $_
  }
)

Write-Host "BACT:   $bactPath"
Write-Host "PMSI:   $pmsiPath"
Write-Host "Output: $outputPath"
Write-Host "R:      $rScript"

if ($existingIncompatibleOutputPaths.Count -gt 0) {
  throw (
    "Output contains artifacts from another Rouen build layout: $outputPath. " +
    'Choose a distinct -Output; -Force cannot replace a different layout. ' +
    'No build was run.'
  )
}

if ($existingOutputPaths.Count -gt 0) {
  if ($DryRun) {
    if ($Force) {
      Write-Warning (
        "Rouen outputs already exist under $outputPath; a real build with " +
        '-Force would replace this compatible layout.'
      )
    } else {
      Write-Warning (
        "Rouen outputs already exist under $outputPath; a real build would " +
        'need -Force or another -Output.'
      )
    }
  } elseif (-not $Force) {
    throw (
      "Rouen outputs already exist under $outputPath. " +
      'Review them, then pass -Force to replace them or choose another -Output.'
    )
  }
}

Test-RouenRDependencies -RScript $rScript

if ($DryRun) {
  Write-Host (
    'PASS: inputs, locked R and required Rouen packages are available; ' +
    'no build was run.'
  )
  return
}

$rArgs = @(
  '--no-save'
  '--no-restore'
  $builder
  $bactPath
  $pmsiPath
  $outputPath
  "--operational-v2-output=$operationalV2Path"
)
if ($Force) {
  $rArgs += '--force'
}

Push-Location $RepoRoot
try {
  & $rScript @rArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Rouen build failed (exit $LASTEXITCODE)."
  }
}
finally {
  Pop-Location
}

$manifestPath = Join-Path $outputPath 'build_manifest.txt'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Rouen build ended without its completion marker: $manifestPath"
}

Write-Host "PASS: Rouen build complete. Manifest: $manifestPath"
Write-Host 'Handoff complete; no further command is required.'
Write-Host 'Optional indicator render from this same build:'
$runtimeWorkspace = Join-Path $outputPath 'runtime'
$bundleLiteral = ConvertTo-OrchideePowerShellLiteral -Value $operationalV2Path
$runtimeLiteral = ConvertTo-OrchideePowerShellLiteral -Value $runtimeWorkspace
Write-Host (
  '& .\scripts\render_orchidee.ps1 -Target full ' +
  "-Bundle $bundleLiteral " +
  "-Workspace $runtimeLiteral"
)
