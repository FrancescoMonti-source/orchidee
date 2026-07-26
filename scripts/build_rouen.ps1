<#
.SYNOPSIS
Builds the validated ORCHIDEE Rouen bundles from BACT and PMSI inputs.

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

function Resolve-RepoPath {
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Remove-TrailingDirectorySeparator {
  param(
    [Parameter(Mandatory)]
    [string]$Path
  )

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($fullPath)
  if ($fullPath.Length -le $root.Length) {
    return $root
  }

  $separators = [char[]]@(
    [System.IO.Path]::DirectorySeparatorChar
    [System.IO.Path]::AltDirectorySeparatorChar
  )
  return $fullPath.TrimEnd($separators)
}

function Test-PathAtOrBelow {
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Directory
  )

  # This is a lexical guard because an output directory may not exist yet.
  # It does not claim to resolve junctions, symlinks or Windows short names.
  $candidate = Remove-TrailingDirectorySeparator -Path $Path
  $parent = Remove-TrailingDirectorySeparator -Path $Directory
  $comparison = if (
    [System.Environment]::OSVersion.Platform -eq
      [System.PlatformID]::Win32NT
  ) {
    [System.StringComparison]::OrdinalIgnoreCase
  } else {
    [System.StringComparison]::Ordinal
  }
  $prefix = $parent
  if (-not $prefix.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $prefix += [System.IO.Path]::DirectorySeparatorChar
  }

  return $candidate.Equals($parent, $comparison) -or
    $candidate.StartsWith($prefix, $comparison)
}

function Resolve-InputFile {
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Label
  )

  $resolved = Resolve-RepoPath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "$Label input not found: $resolved"
  }

  return (Resolve-Path -LiteralPath $resolved).Path
}

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

$bactPath = Resolve-InputFile -Path $Bact -Label 'BACT'
$pmsiPath = Resolve-InputFile -Path $Pmsi -Label 'PMSI'
$outputPath = if ([string]::IsNullOrWhiteSpace($Output)) {
  Join-Path $RepoRoot 'outputs\rouen_current'
} else {
  Resolve-RepoPath -Path $Output
}
$outputPath = Remove-TrailingDirectorySeparator -Path $outputPath
if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
  throw "Output must be a directory, not an existing file: $outputPath"
}

$repoOutputs = Join-Path $RepoRoot 'outputs'
$fileSystemRoot = [System.IO.Path]::GetPathRoot($outputPath)
$outputIsFileSystemRoot = (
  Test-PathAtOrBelow -Path $outputPath -Directory $fileSystemRoot
) -and (
  Test-PathAtOrBelow -Path $fileSystemRoot -Directory $outputPath
)
$outputContainsRepo = Test-PathAtOrBelow `
  -Path $RepoRoot `
  -Directory $outputPath
if ($outputIsFileSystemRoot -or $outputContainsRepo) {
  throw (
    'Output must be a dedicated directory, not a filesystem root or an ' +
    "ancestor of the repository: $outputPath"
  )
}

$outputInsideRepo = Test-PathAtOrBelow -Path $outputPath -Directory $RepoRoot
$outputInsideRepoOutputs = Test-PathAtOrBelow `
  -Path $outputPath `
  -Directory $repoOutputs
$outputIsRepoOutputs = $outputInsideRepoOutputs -and (
  Test-PathAtOrBelow -Path $repoOutputs -Directory $outputPath
)
if (
  $outputInsideRepo -and (
    -not $outputInsideRepoOutputs -or
    $outputIsRepoOutputs
  )
) {
  throw (
    'An output inside the repository must be a dedicated directory under ' +
    "outputs/: $outputPath"
  )
}

$inputsInsideOutput = @(
  @(
    $bactPath
    $pmsiPath
  ) | Where-Object {
    Test-PathAtOrBelow -Path $_ -Directory $outputPath
  }
)
if ($inputsInsideOutput.Count -gt 0) {
  throw (
    'BACT and PMSI inputs must be outside the output directory: ' +
    ($inputsInsideOutput -join ', ')
  )
}

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
  '--contract=v3'
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
