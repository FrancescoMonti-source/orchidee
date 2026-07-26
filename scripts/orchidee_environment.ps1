function Get-OrchideeLockMetadata {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot
  )

  $lockPath = Join-Path $RepoRoot 'renv.lock'
  if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
    throw "Missing R dependency lockfile: $lockPath"
  }

  try {
    $lock = Get-Content -Raw -LiteralPath $lockPath | ConvertFrom-Json
  }
  catch {
    throw "Cannot read R dependency lockfile: $lockPath"
  }

  $rVersion = [string]$lock.R.Version
  if ([string]::IsNullOrWhiteSpace($rVersion)) {
    throw "renv.lock does not declare an R version: $lockPath"
  }

  [pscustomobject]@{
    Path = (Resolve-Path -LiteralPath $lockPath).Path
    RVersion = $rVersion
    PackageCount = @($lock.Packages.PSObject.Properties).Count
  }
}

function Get-OrchideeRScriptVersion {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RScript
  )

  $version = & $RScript --vanilla -e "cat(as.character(getRversion()))"
  if ($LASTEXITCODE -ne 0) {
    return $null
  }

  return ([string]$version).Trim()
}

function Resolve-OrchideeRScript {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [string[]]$AdditionalCandidates = @()
  )

  $lock = Get-OrchideeLockMetadata -RepoRoot $RepoRoot
  $candidates = @()

  if ($env:ORCHIDEE_R) {
    if (-not (Test-Path -LiteralPath $env:ORCHIDEE_R -PathType Leaf)) {
      throw "ORCHIDEE_R does not point to an existing file: $env:ORCHIDEE_R"
    }

    $explicit = (Resolve-Path -LiteralPath $env:ORCHIDEE_R).Path
    $explicitVersion = Get-OrchideeRScriptVersion -RScript $explicit
    if ($explicitVersion -ne $lock.RVersion) {
      throw (
        "ORCHIDEE_R points to R $explicitVersion, but renv.lock requires " +
        "R $($lock.RVersion): $explicit"
      )
    }
    return $explicit
  }
  if ($env:ProgramFiles) {
    $candidates += Join-Path `
      $env:ProgramFiles `
      "R\R-$($lock.RVersion)\bin\Rscript.exe"
  }
  if ($env:LOCALAPPDATA) {
    $candidates += Join-Path `
      $env:LOCALAPPDATA `
      "Programs\R\R-$($lock.RVersion)\bin\Rscript.exe"
  }
  $candidates += $AdditionalCandidates

  $command = Get-Command Rscript -ErrorAction SilentlyContinue
  if ($command) {
    $candidates += $command.Source
  }

  $mismatches = @()
  foreach ($candidate in $candidates | Where-Object { $_ } | Select-Object -Unique) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      continue
    }

    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    $actualVersion = Get-OrchideeRScriptVersion -RScript $resolved
    if ($actualVersion -eq $lock.RVersion) {
      return $resolved
    }
    if ($actualVersion) {
      $mismatches += "$resolved (R $actualVersion)"
    }
  }

  $message = (
    "Rscript for R $($lock.RVersion) was not found. Install that version " +
    'or set ORCHIDEE_R to its Rscript executable.'
  )
  if ($mismatches.Count -gt 0) {
    $message += " Other R installations were ignored: $($mismatches -join ', ')."
  }
  throw $message
}
