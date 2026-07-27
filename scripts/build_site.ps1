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
outputs\site_example with -RunExample. A destination inside the checkout must
be below outputs\.

.PARAMETER Force
Replace a complete output from this same site v3 plus operational-v2 workflow.
It cannot replace an incomplete or incompatible layout.

.PARAMETER DryRun
Check paths, locked R, required packages and input columns without building or
writing a bundle. Delimited inputs are read as headers; RDS inputs must be
deserialized to inspect their columns.

.PARAMETER EmitTemplates
Create the six empty v3 handoff CSV templates and the ORCHIDEE mapping-reference
kit in a new or unused directory. Existing generated files are never
overwritten.

.PARAMETER RunExample
Build the versioned synthetic six-block example. This proves that the complete
site workflow works before protected local data are introduced. The default
output is outputs\site_example.

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
& .\scripts\build_site.ps1 -EmitTemplates "data\site_handoff"

.EXAMPLE
& .\scripts\build_site.ps1 -RunExample
#>

[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [string]$MicrobiologyObservations,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [string]$BacteriaMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [string]$SampleTypeMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [string]$AntibioticMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [string]$UnitMapping,

  [Parameter(Mandatory, ParameterSetName = 'Build')]
  [string]$IncidenceExposure,

  [Parameter(ParameterSetName = 'Build')]
  [Parameter(ParameterSetName = 'Example')]
  [string]$Output,

  [Parameter(ParameterSetName = 'Build')]
  [Parameter(ParameterSetName = 'Example')]
  [switch]$Force,

  [Parameter(ParameterSetName = 'Build')]
  [switch]$DryRun,

  [Parameter(Mandatory, ParameterSetName = 'Templates')]
  [string]$EmitTemplates,

  [Parameter(Mandatory, ParameterSetName = 'Example')]
  [switch]$RunExample
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

$rScript = Resolve-OrchideeRScript -RepoRoot $RepoRoot

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

$isExample = $PSCmdlet.ParameterSetName -eq 'Example'
if ($isExample) {
  $exampleRoot = Join-Path $RepoRoot 'examples\site_handoff_minimal'
  $MicrobiologyObservations = Join-Path `
    $exampleRoot `
    'microbiology_observations.csv'
  $BacteriaMapping = Join-Path $exampleRoot 'bacteria_mapping.csv'
  $SampleTypeMapping = Join-Path $exampleRoot 'sample_type_mapping.csv'
  $AntibioticMapping = Join-Path $exampleRoot 'antibiotic_mapping.csv'
  $UnitMapping = Join-Path $exampleRoot 'unit_mapping.csv'
  $IncidenceExposure = Join-Path `
    $exampleRoot `
    'incidence_exposure_by_year_um_uf_ta_de_profile.csv'
  Write-Host 'Mode: versioned synthetic site example'
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
$inputPaths = @(
  $inputDefinitions | ForEach-Object {
    Resolve-OrchideeInputFile `
      -RepoRoot $RepoRoot `
      -Path $_.Value `
      -Label $_.Name
  }
)
$outputRoot = if ([string]::IsNullOrWhiteSpace($Output)) {
  if ($isExample) {
    Join-Path $RepoRoot 'outputs\site_example'
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
  '--contract=v3'
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
  '& .\scripts\render_orchidee.ps1 -Target full ' +
  "-Bundle $bundleV2Literal " +
  "-Workspace $runtimeLiteral"
)
