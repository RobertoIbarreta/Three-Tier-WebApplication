# Shared helpers for deploy scripts. Dot-source: . "$PSScriptRoot\_common.ps1"

function Get-RepoRoot {
    # PSScriptRoot = <repo>/app/deploy/windows → repo root is three levels up
    (Resolve-Path (Join-Path $PSScriptRoot "..\..\..\")).Path
}

function Get-TerraformAwsDir {
    Join-Path (Get-RepoRoot) "aws"
}

<#
.SYNOPSIS
  Runs terraform output from the aws/ directory (uses your current workspace state).
#>
function Invoke-TerraformOutput {
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Raw
    )
    $awsDir = Get-TerraformAwsDir
    Push-Location $awsDir
    try {
        $tfArgs = @("output")
        if ($Raw) { $tfArgs += "-raw" }
        $tfArgs += $Name
        & terraform @tfArgs
        if ($LASTEXITCODE -ne 0) { throw "terraform output $Name failed (exit $LASTEXITCODE)." }
    }
    finally {
        Pop-Location
    }
}
