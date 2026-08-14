<#
.SYNOPSIS
Builds validated ORCHIDEE bundles from the six handoff blocks of a site.

.DESCRIPTION
This is the routine operator entry point for Rennes or another hospital
without a packaged local adapter. It validates the six site-owned input
paths, retains bundle v3 and creates the operational bundle v2.

.PARAMETER MicrobiologyObservations
Long local S/I/R observations. Accepted formats are RDS, CSV, TSV, TAB and TXT.

.PARAMETER BacteriaMapping
Local-to-ORCHIDEE bacterium mapping.

.PARAMETER SampleTypeMapping
Local-to-ORCHIDEE sample-type mapping.

.PARAMETER AntibioticMapping
Local-to-ORCHIDEE antibiotic mapping.

.PARAMETER UnitMapping
Hospitalization UF mapping with CODE_TA, CODE_DE and de_domain_ref.

.PARAMETER IncidenceExposure
Profiled incidence exposure at year + UM + UF + TA + DE grain.

.PARAMETER Output
Dedicated output root. Defaults to outputs\site_current for local inputs and
outputs\site_smoke_test with -RunSmokeTest. With -Diagnose nothing is built and
it only selects where the report is written. A destination inside the checkout
must be below outputs\.

.PARAMETER Force
Replace a complete output from this same site v3 plus operational-v2 workflow.
It cannot replace an incomplete or incompatible layout.

.PARAMETER DryRun
Check paths, locked R, required packages and input columns without building or
writing a bundle. Delimited inputs are read as headers; RDS inputs must be
deserialized to inspect their columns.

.PARAMETER Diagnose
Read the six blocks once and write an aggregated report of every handoff
contract problem, classified as BLOCKING, WARNING and INFO, instead of stopping
at the first error. Use it after -DryRun passes and before a first build. It
answers only whether the six blocks satisfy the handoff contract; it makes no
claim about which indicators would be published. No bundle is built.

.PARAMETER Report
Directory for the -Diagnose report. Defaults to a diagnostics subdirectory of
-Output when that is given, otherwise outputs\site_diagnostics. A destination
inside the checkout must be below outputs\.

.PARAMETER EmitTemplates
Create the six empty v3 handoff CSV templates and the ORCHIDEE mapping-reference
kit in a new or unused directory. Existing generated files are never
overwritten.

.PARAMETER RunSmokeTest
Check this installation by running the complete site workflow on the versioned
synthetic six-block fixture. A failure points at the installation; a PASS rules
it out as the sole explanation without proving anything about your own data,
because one synthetic observation exercises no deduplication, screening
exclusion, phenotype, resistance or perimeter filtering. It is not onboarding
material. Run it before -Diagnose. The default output is
outputs\site_smoke_test.

.EXAMPLE
& .\scripts\build_site.ps1 `
  -MicrobiologyObservations "C:\handoff\microbiology_observations.csv" `
  -BacteriaMapping "C:\handoff\bacteria_mapping.csv" `
  -SampleTypeMapping "C:\handoff\sample_type_mapping.csv" `
  -AntibioticMapping "C:\handoff\antibiotic_mapping.csv" `
  -UnitMapping "C:\handoff\unit_mapping.csv" `
  -IncidenceExposure `
    "C:\handoff\incidence_exposure_by_year_um_uf_ta_de_profile.csv" `
  -DryRun

.EXAMPLE
& .\scripts\build_site.ps1 `
  -MicrobiologyObservations "C:\handoff\microbiology_observations.csv" `
  -BacteriaMapping "C:\handoff\bacteria_mapping.csv" `
  -SampleTypeMapping "C:\handoff\sample_type_mapping.csv" `
  -AntibioticMapping "C:\handoff\antibiotic_mapping.csv" `
  -UnitMapping "C:\handoff\unit_mapping.csv" `
  -IncidenceExposure `
    "C:\handoff\incidence_exposure_by_year_um_uf_ta_de_profile.csv" `
  -Diagnose

.EXAMPLE
& .\scripts\build_site.ps1 -EmitTemplates "data\site_handoff"

.EXAMPLE
& .\scripts\build_site.ps1 -RunSmokeTest
#>

[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [Parameter(Mandatory, ParameterSetName = 'Diagnose')]
  [string]$MicrobiologyObservations,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [Parameter(Mandatory, ParameterSetName = 'Diagnose')]
  [string]$BacteriaMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [Parameter(Mandatory, ParameterSetName = 'Diagnose')]
  [string]$SampleTypeMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [Parameter(Mandatory, ParameterSetName = 'Diagnose')]
  [string]$AntibioticMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [Parameter(Mandatory, ParameterSetName = 'Diagnose')]
  [string]$UnitMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [Parameter(Mandatory, ParameterSetName = 'Diagnose')]
  [string]$IncidenceExposure,

  [Parameter(ParameterSetName = 'Build')]
  [Parameter(ParameterSetName = 'SmokeTest')]
  [Parameter(ParameterSetName = 'Diagnose')]
  [string]$Output,

  [Parameter(ParameterSetName = 'Build')]
  [Parameter(ParameterSetName = 'SmokeTest')]
  [switch]$Force,

  [Parameter(ParameterSetName = 'Build')]
  [switch]$DryRun,

  [Parameter(Mandatory, ParameterSetName = 'Diagnose')]
  [switch]$Diagnose,

  [Parameter(ParameterSetName = 'Diagnose')]
  [string]$Report,

  [Parameter(Mandatory, ParameterSetName = 'Templates')]
  [string]$EmitTemplates,

  [Parameter(Mandatory, ParameterSetName = 'SmokeTest')]
  [switch]$RunSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'orchidee_environment.ps1')
. (Join-Path $PSScriptRoot 'orchidee_operator_paths.ps1')

function Test-SiteBundleManifest {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$ContractVersion,

    [Parameter(Mandatory)]
    [string]$Role
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $false
  }
  $lines = @(Get-Content -LiteralPath $Path)
  return (
    $lines -ccontains 'status: complete'
  ) -and (
    $lines -ccontains 'workflow: site_handoff'
  ) -and (
    $lines -ccontains "contract_version: $ContractVersion"
  ) -and (
    $lines -ccontains "role: $Role"
  ) -and (
    $lines -ccontains 'runtime_smoke: PASS'
  )
}

function Get-SiteBundleManifestValue {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Key
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }
  $prefix = "${Key}: "
  $line = @(
    Get-Content -LiteralPath $Path |
      Where-Object { $_.StartsWith($prefix) }
  ) | Select-Object -First 1
  if ($null -eq $line) {
    return $null
  }
  return $line.Substring($prefix.Length).Trim()
}

function Assert-SafeTemplateDirectory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  $resolved = Remove-OrchideeTrailingDirectorySeparator -Path $Path
  if (Test-Path -LiteralPath $resolved -PathType Leaf) {
    throw "Template destination must be a directory: $resolved"
  }
  $fileSystemRoot = [System.IO.Path]::GetPathRoot($resolved)
  $isFileSystemRoot = (
    Test-OrchideePathAtOrBelow -Path $resolved -Directory $fileSystemRoot
  ) -and (
    Test-OrchideePathAtOrBelow -Path $fileSystemRoot -Directory $resolved
  )
  $containsRepo = Test-OrchideePathAtOrBelow `
    -Path $RepoRoot `
    -Directory $resolved
  if ($isFileSystemRoot -or $containsRepo) {
    throw (
      'Template destination must be a dedicated directory, not a filesystem ' +
      "root or an ancestor of the repository: $resolved"
    )
  }

  $insideRepo = Test-OrchideePathAtOrBelow -Path $resolved -Directory $RepoRoot
  if ($insideRepo) {
    $repoData = Join-Path $RepoRoot 'data'
    $insideData = Test-OrchideePathAtOrBelow `
      -Path $resolved `
      -Directory $repoData
    $isDataRoot = $insideData -and (
      Test-OrchideePathAtOrBelow -Path $repoData -Directory $resolved
    )
    if (-not $insideData -or $isDataRoot) {
      throw (
        'A template destination inside the repository must be a dedicated ' +
        "directory under data/: $resolved"
      )
    }
  }

  return $resolved
}

# -Diagnose has its own exit-status contract: 1 means blocking findings in the
# six blocks, 2 means no verdict could be produced. Everything that can fail
# before R runs -- resolving R, the six input paths, the report directory -- has
# to honour it, or a caller reads a setup mistake as a problem with the site's
# data.
$isDiagnose = $PSCmdlet.ParameterSetName -eq 'Diagnose'

function Exit-OrchideeDiagnoseSetupFailure {
  param([string]$Message)

  Write-Host ''
  Write-Host (
    "The diagnostics could not start: $Message" + ' This is not a verdict on ' +
    'the six blocks, and no report was written.'
  )
  exit 2
}

try {
  $rScript = Resolve-OrchideeRScript -RepoRoot $RepoRoot
}
catch {
  if (-not $isDiagnose) { throw }
  Exit-OrchideeDiagnoseSetupFailure -Message $_.Exception.Message
}

if ($PSCmdlet.ParameterSetName -eq 'Templates') {
  $templatePath = Resolve-OrchideeRepoPath `
    -RepoRoot $RepoRoot `
    -Path $EmitTemplates
  $templatePath = Assert-SafeTemplateDirectory -Path $templatePath
  $templateWriter = Join-Path `
    $RepoRoot `
    'scripts\emit_site_handoff_templates.R'

  Write-Host "Templates: $templatePath"
  Write-Host "R:         $rScript"
  Push-Location $RepoRoot
  try {
    & $rScript --no-save --no-restore $templateWriter $templatePath
    if ($LASTEXITCODE -ne 0) {
      throw "Site template generation failed (exit $LASTEXITCODE)."
    }
  }
  finally {
    Pop-Location
  }
  return
}

$isSmokeTest = $PSCmdlet.ParameterSetName -eq 'SmokeTest'
if ($isSmokeTest) {
  $fixtureRoot = Join-Path $RepoRoot 'examples\site_handoff_minimal'
  $MicrobiologyObservations = Join-Path `
    $fixtureRoot `
    'microbiology_observations.csv'
  $BacteriaMapping = Join-Path $fixtureRoot 'bacteria_mapping.csv'
  $SampleTypeMapping = Join-Path $fixtureRoot 'sample_type_mapping.csv'
  $AntibioticMapping = Join-Path $fixtureRoot 'antibiotic_mapping.csv'
  $UnitMapping = Join-Path $fixtureRoot 'unit_mapping.csv'
  $IncidenceExposure = Join-Path `
    $fixtureRoot `
    'incidence_exposure_by_year_um_uf_ta_de_profile.csv'
  Write-Host 'Mode: installation smoke test on the versioned synthetic fixture'
}

$inputDefinitions = @(
  [pscustomobject]@{
    Name = 'microbiology_observations'
    Value = $MicrobiologyObservations
  }
  [pscustomobject]@{
    Name = 'bacteria_mapping'
    Value = $BacteriaMapping
  }
  [pscustomobject]@{
    Name = 'sample_type_mapping'
    Value = $SampleTypeMapping
  }
  [pscustomobject]@{
    Name = 'antibiotic_mapping'
    Value = $AntibioticMapping
  }
  [pscustomobject]@{
    Name = 'unit_mapping'
    Value = $UnitMapping
  }
  [pscustomobject]@{
    Name = 'incidence_exposure_by_year_um_uf_ta_de_profile'
    Value = $IncidenceExposure
  }
)
try {
  $inputPaths = @(
    $inputDefinitions | ForEach-Object {
      Resolve-OrchideeInputFile `
        -RepoRoot $RepoRoot `
        -Path $_.Value `
        -Label $_.Name
    }
  )
}
catch {
  if (-not $isDiagnose) { throw }
  Exit-OrchideeDiagnoseSetupFailure -Message $_.Exception.Message
}

if ($isDiagnose) {
  # -Output is accepted here so that the documented workflow really is the same
  # command line with -DryRun swapped for -Diagnose. The report then sits
  # beside the build it precedes.
  try {
    $reportRoot = if (-not [string]::IsNullOrWhiteSpace($Report)) {
      Resolve-OrchideeRepoPath -RepoRoot $RepoRoot -Path $Report
    } elseif (-not [string]::IsNullOrWhiteSpace($Output)) {
      Join-Path (
        Resolve-OrchideeRepoPath -RepoRoot $RepoRoot -Path $Output
      ) 'diagnostics'
    } else {
      Join-Path $RepoRoot 'outputs\site_diagnostics'
    }
    $reportRoot = Assert-OrchideeSafeOutputDirectory `
      -RepoRoot $RepoRoot `
      -OutputPath $reportRoot `
      -InputPaths $inputPaths `
      -InputLabel 'Site handoff inputs'
  }
  catch {
    Exit-OrchideeDiagnoseSetupFailure -Message $_.Exception.Message
  }

  for ($index = 0; $index -lt $inputDefinitions.Count; $index++) {
    Write-Host "$($inputDefinitions[$index].Name): $($inputPaths[$index])"
  }
  Write-Host "Report: $reportRoot"
  Write-Host "R:      $rScript"

  $diagnoser = Join-Path $RepoRoot 'scripts\diagnose_site_inputs.R'
  Push-Location $RepoRoot
  try {
    # Do not redirect this stderr: sites run this wrapper under Windows
    # PowerShell 5.1, where a redirected native stderr becomes a terminating
    # error and $diagnoseExit never gets read, collapsing the documented exit 2
    # onto exit 1.
    & $rScript --no-save --no-restore $diagnoser @inputPaths $reportRoot
    $diagnoseExit = $LASTEXITCODE
  }
  finally {
    Pop-Location
  }

  if ($diagnoseExit -eq 1) {
    Write-Host ''
    Write-Host (
      'Correct the blocking findings above and rerun -Diagnose. No bundle was ' +
      'built.'
    )
    exit 1
  }
  if ($diagnoseExit -eq 2) {
    # Exit rather than throw: the documented interface promises 2 for a
    # technical failure, and a throw would surface 1 to the caller, which is
    # the code reserved for blocking findings in the blocks themselves.
    Write-Host ''
    Write-Host (
      'The diagnostics could not run or publish their report; this is not a ' +
      "verdict on the six blocks. See the message above. Report: $reportRoot"
    )
    exit 2
  }
  if ($diagnoseExit -ne 0) {
    # Any other status is a technical failure too, so report it as one instead
    # of collapsing it onto the blocking-findings code.
    Write-Host ''
    Write-Host (
      "Site input diagnostics failed unexpectedly (exit $diagnoseExit); this " +
      'is not a verdict on the six blocks.'
    )
    exit 2
  }
  return
}

$outputRoot = if ([string]::IsNullOrWhiteSpace($Output)) {
  if ($isSmokeTest) {
    Join-Path $RepoRoot 'outputs\site_smoke_test'
  } else {
    Join-Path $RepoRoot 'outputs\site_current'
  }
} else {
  Resolve-OrchideeRepoPath -RepoRoot $RepoRoot -Path $Output
}
$outputRoot = Assert-OrchideeSafeOutputDirectory `
  -RepoRoot $RepoRoot `
  -OutputPath $outputRoot `
  -InputPaths $inputPaths `
  -InputLabel 'Site handoff inputs'

$bundleV3Path = Join-Path $outputRoot 'bundle_v3'
$bundleV2Path = Join-Path $outputRoot 'bundle_v2_operational'
$runtimePath = Join-Path $outputRoot 'runtime'
$bundleV3Manifest = Join-Path $bundleV3Path 'build_manifest.txt'
$bundleV2Manifest = Join-Path $bundleV2Path 'build_manifest.txt'

for ($index = 0; $index -lt $inputDefinitions.Count; $index++) {
  Write-Host "$($inputDefinitions[$index].Name): $($inputPaths[$index])"
}
Write-Host "Output: $outputRoot"
Write-Host "R:      $rScript"

$incompatiblePaths = @(
  (Join-Path $outputRoot 'site_inputs')
  (Join-Path $outputRoot 'adapter_audit.rds')
  (Join-Path $outputRoot 'bundle')
)
$existingIncompatiblePaths = @(
  $incompatiblePaths | Where-Object { Test-Path -LiteralPath $_ }
)
if ($existingIncompatiblePaths.Count -gt 0) {
  throw (
    "Output contains artifacts from another build layout: $outputRoot. " +
    'Choose a distinct -Output; -Force cannot replace this layout.'
  )
}

$knownBundlePaths = @($bundleV3Path, $bundleV2Path)
$existingKnownBundlePaths = @(
  $knownBundlePaths | Where-Object { Test-Path -LiteralPath $_ }
)
$bundleV3BuildId = Get-SiteBundleManifestValue `
  -Path $bundleV3Manifest `
  -Key 'build_id'
$bundleV2BuildId = Get-SiteBundleManifestValue `
  -Path $bundleV2Manifest `
  -Key 'build_id'
$matchingBuildId = (
  -not [string]::IsNullOrWhiteSpace($bundleV3BuildId)
) -and (
  $bundleV3BuildId -eq $bundleV2BuildId
)
$completeCompatibleLayout = (
  Test-SiteBundleManifest `
    -Path $bundleV3Manifest `
    -ContractVersion 'v3' `
    -Role 'durable_v3'
) -and (
  Test-SiteBundleManifest `
    -Path $bundleV2Manifest `
    -ContractVersion 'v2' `
    -Role 'operational_v2'
) -and $matchingBuildId
if ($existingKnownBundlePaths.Count -gt 0 -and -not $completeCompatibleLayout) {
  $cleanupTargets = @(
    ConvertTo-OrchideePowerShellLiteral -Value $bundleV3Path
    ConvertTo-OrchideePowerShellLiteral -Value $bundleV2Path
  ) -join ', '
  throw (
    "Output contains an incomplete or incompatible site build: $outputRoot. " +
    'Choose another -Output; -Force cannot replace it. After confirming no ' +
    'build is running and these partial bundles are disposable, run: ' +
    "Remove-Item -LiteralPath $cleanupTargets -Recurse -Force " +
    '-ErrorAction SilentlyContinue'
  )
}
if ($completeCompatibleLayout) {
  if ($DryRun) {
    if ($Force) {
      Write-Warning (
        "Complete site outputs already exist under $outputRoot; a real build " +
        'with -Force would replace the two compatible bundles.'
      )
    } else {
      Write-Warning (
        "Complete site outputs already exist under $outputRoot; a real build " +
        'would need -Force or another -Output.'
      )
    }
  } elseif (-not $Force) {
    throw (
      "Complete site outputs already exist under $outputRoot. " +
      'Review them, then pass -Force or choose another -Output.'
    )
  }
} elseif ($Force) {
  Write-Warning '-Force is unnecessary because no compatible output exists.'
}

$environmentProbe = Join-Path $RepoRoot 'scripts\check_site_environment.R'
Push-Location $RepoRoot
try {
  & $rScript --no-save --no-restore $environmentProbe @inputPaths
  if ($LASTEXITCODE -ne 0) {
    throw (
      'The site build environment or input columns are not ready. Run ' +
      '& .\scripts\setup.ps1 if packages are missing, correct the named ' +
      'input error above, then retry.'
    )
  }
}
finally {
  Pop-Location
}

if ($DryRun) {
  Write-Host (
    'PASS: paths, locked R, required packages and input columns are ' +
    'available; no bundle was built.'
  )
  return
}

$builder = Join-Path `
  $RepoRoot `
  'scripts\build_external_bundle_from_site_inputs.R'
$builderArgs = @(
  '--no-save'
  '--no-restore'
  $builder
) + $inputPaths + @(
  $bundleV3Path
  "--operational-v2-output=$bundleV2Path"
  '--no-next-steps'
)
if ($Force) {
  $builderArgs += '--force'
}

Push-Location $RepoRoot
try {
  & $rScript @builderArgs
  if ($LASTEXITCODE -ne 0) {
    throw "Site bundle build failed (exit $LASTEXITCODE)."
  }
}
finally {
  Pop-Location
}

if (-not (
  Test-SiteBundleManifest `
    -Path $bundleV3Manifest `
    -ContractVersion 'v3' `
    -Role 'durable_v3'
)) {
  throw "Site build ended without a valid v3 completion marker."
}
if (-not (
  Test-SiteBundleManifest `
    -Path $bundleV2Manifest `
    -ContractVersion 'v2' `
    -Role 'operational_v2'
)) {
  throw "Site build ended without a valid operational-v2 completion marker."
}
$builtV3BuildId = Get-SiteBundleManifestValue `
  -Path $bundleV3Manifest `
  -Key 'build_id'
$builtV2BuildId = Get-SiteBundleManifestValue `
  -Path $bundleV2Manifest `
  -Key 'build_id'
if (
  [string]::IsNullOrWhiteSpace($builtV3BuildId) -or
  $builtV3BuildId -ne $builtV2BuildId
) {
  throw (
    'Site build ended without matching v3 and operational-v2 build IDs. ' +
    'Do not use either bundle.'
  )
}

Write-Host (
  'PASS: site handoff build, strict bundle validation and operational-v2 ' +
  'runtime smoke are complete.'
)
Write-Host "V3 manifest: $bundleV3Manifest"
Write-Host "V2 manifest: $bundleV2Manifest"
Write-Host 'Handoff complete; no further command is required.'
Write-Host 'Optional indicator render from this same build:'
$bundleV2Literal = ConvertTo-OrchideePowerShellLiteral -Value $bundleV2Path
$runtimeLiteral = ConvertTo-OrchideePowerShellLiteral -Value $runtimePath
Write-Host (
  '& .\scripts\render_orchidee.ps1 -Rebuild ' +
  "-Bundle $bundleV2Literal " +
  "-Workspace $runtimeLiteral"
)
