function ConvertTo-OrchideePowerShellLiteral {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Value
  )

  return "'" + $Value.Replace("'", "''") + "'"
}

function Resolve-OrchideeRepoPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [Parameter(Mandatory)]
    [string]$Path
  )

  if ([System.IO.Path]::IsPathRooted($Path)) {
    return [System.IO.Path]::GetFullPath($Path)
  }

  return [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Path))
}

function Remove-OrchideeTrailingDirectorySeparator {
  [CmdletBinding()]
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

function Test-OrchideePathAtOrBelow {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Directory
  )

  # This is a lexical guard because a destination may not exist yet. It does
  # not claim to resolve junctions, symlinks or Windows short names.
  $candidate = Remove-OrchideeTrailingDirectorySeparator -Path $Path
  $parent = Remove-OrchideeTrailingDirectorySeparator -Path $Directory
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

function Resolve-OrchideeInputFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [Parameter(Mandatory)]
    [string]$Path,

    [Parameter(Mandatory)]
    [string]$Label
  )

  $resolved = Resolve-OrchideeRepoPath -RepoRoot $RepoRoot -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "$Label input not found: $resolved"
  }

  return (Resolve-Path -LiteralPath $resolved).Path
}

function Assert-OrchideeSafeOutputDirectory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [Parameter(Mandatory)]
    [string]$OutputPath,

    [string[]]$InputPaths = @(),

    [string]$InputLabel = 'Inputs'
  )

  $resolvedOutput = Remove-OrchideeTrailingDirectorySeparator -Path $OutputPath
  if (Test-Path -LiteralPath $resolvedOutput -PathType Leaf) {
    throw "Output must be a directory, not an existing file: $resolvedOutput"
  }

  $repoOutputs = Join-Path $RepoRoot 'outputs'
  $fileSystemRoot = [System.IO.Path]::GetPathRoot($resolvedOutput)
  $outputIsFileSystemRoot = (
    Test-OrchideePathAtOrBelow `
      -Path $resolvedOutput `
      -Directory $fileSystemRoot
  ) -and (
    Test-OrchideePathAtOrBelow `
      -Path $fileSystemRoot `
      -Directory $resolvedOutput
  )
  $outputContainsRepo = Test-OrchideePathAtOrBelow `
    -Path $RepoRoot `
    -Directory $resolvedOutput
  if ($outputIsFileSystemRoot -or $outputContainsRepo) {
    throw (
      'Output must be a dedicated directory, not a filesystem root or an ' +
      "ancestor of the repository: $resolvedOutput"
    )
  }

  $outputInsideRepo = Test-OrchideePathAtOrBelow `
    -Path $resolvedOutput `
    -Directory $RepoRoot
  $outputInsideRepoOutputs = Test-OrchideePathAtOrBelow `
    -Path $resolvedOutput `
    -Directory $repoOutputs
  $outputIsRepoOutputs = $outputInsideRepoOutputs -and (
    Test-OrchideePathAtOrBelow `
      -Path $repoOutputs `
      -Directory $resolvedOutput
  )
  if (
    $outputInsideRepo -and (
      -not $outputInsideRepoOutputs -or
      $outputIsRepoOutputs
    )
  ) {
    throw (
      'An output inside the repository must be a dedicated directory under ' +
      "outputs/: $resolvedOutput"
    )
  }

  $inputsInsideOutput = @(
    $InputPaths | Where-Object {
      Test-OrchideePathAtOrBelow -Path $_ -Directory $resolvedOutput
    }
  )
  if ($inputsInsideOutput.Count -gt 0) {
    throw (
      "$InputLabel must be outside the output directory: " +
      ($inputsInsideOutput -join ', ')
    )
  }

  return $resolvedOutput
}
