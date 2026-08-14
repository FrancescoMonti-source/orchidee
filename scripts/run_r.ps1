<#
.SYNOPSIS
Runs a repository R script or expression with the R version in renv.lock.

.EXAMPLE
& .\scripts\run_r.ps1 tests/run_tests.R

.EXAMPLE
& .\scripts\run_r.ps1 -Expression "renv::status()"
#>

[CmdletBinding(DefaultParameterSetName = 'Script')]
param(
  [Parameter(
    Mandatory,
    Position = 0,
    ParameterSetName = 'Script'
  )]
  [string]$Script,

  [Parameter(
    Position = 1,
    ValueFromRemainingArguments,
    ParameterSetName = 'Script'
  )]
  [string[]]$ScriptArgs = @(),

  [Parameter(
    Mandatory,
    ParameterSetName = 'Expression'
  )]
  [string]$Expression
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'orchidee_environment.ps1')

$rScript = Resolve-OrchideeRScript -RepoRoot $RepoRoot
$rArgs = @('--no-save', '--no-restore')

if ($PSCmdlet.ParameterSetName -eq 'Expression') {
  $rArgs += @('-e', $Expression)
  $description = 'R expression'
} else {
  $scriptPath = if ([System.IO.Path]::IsPathRooted($Script)) {
    [System.IO.Path]::GetFullPath($Script)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Script))
  }
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    throw "R script not found: $scriptPath"
  }

  $scriptPath = (Resolve-Path -LiteralPath $scriptPath).Path
  $rArgs += $scriptPath
  $rArgs += $ScriptArgs
  $description = $scriptPath
}

Push-Location $RepoRoot
try {
  # Do not redirect R's stderr here. Windows PowerShell 5.1 turns a redirected
  # native stderr into a terminating error under ErrorActionPreference Stop,
  # which destroys $LASTEXITCODE before the check below reads it; 2>&1 and
  # 2>file both do it, and relaxing the preference does not help. A caller that
  # needs to keep the cause merges the streams on its own side, with
  # `& .\scripts\run_r.ps1 ... *> run.log`.
  & $rScript @rArgs
  if ($LASTEXITCODE -ne 0) {
    throw "$description failed (exit $LASTEXITCODE)."
  }
}
finally {
  Pop-Location
}
