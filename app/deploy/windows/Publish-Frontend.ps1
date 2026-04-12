<#
.SYNOPSIS
  Upload Vite dist/ to the Terraform frontend S3 bucket and invalidate CloudFront.

.DESCRIPTION
  Reads bucket and distribution IDs from terraform output (run from the same aws/ workspace you applied).
  Requires AWS CLI v2 and a profile/identity that can s3:PutObject and cloudfront:CreateInvalidation.

.EXAMPLE
  cd C:\path\To\Three-Tier-WebApplication
  .\app\deploy\windows\Publish-Frontend.ps1
  .\app\deploy\windows\Publish-Frontend.ps1 -Bucket "my-bucket" -DistributionId "E123..."
#>
[CmdletBinding()]
param(
    [string]$Bucket = "",
    [string]$DistributionId = "",
    [string]$Region = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_common.ps1"

$frontend = Join-Path (Get-RepoRoot) "app\frontend"
$dist = Join-Path $frontend "dist"
if (-not (Test-Path $dist)) {
    throw "dist/ not found. Run Build-Frontend.ps1 first."
}

if (-not $Bucket) {
    $Bucket = (Invoke-TerraformOutput -Name "frontend_s3_bucket_name" -Raw).Trim()
}
if (-not $DistributionId) {
    $DistributionId = (Invoke-TerraformOutput -Name "frontend_cloudfront_distribution_id" -Raw).Trim()
}
if (-not $Region) {
    $Region = (Invoke-TerraformOutput -Name "aws_region" -Raw).Trim()
}

Write-Host "Bucket:        $Bucket"
Write-Host "Distribution:  $DistributionId"
Write-Host "Region:        $Region"

$syncArgs = @(
    "s3", "sync", $dist, "s3://$Bucket/",
    "--delete",
    "--region", $Region
)
& aws @syncArgs
if ($LASTEXITCODE -ne 0) { throw "aws s3 sync failed." }

$invArgs = @(
    "cloudfront", "create-invalidation",
    "--distribution-id", $DistributionId,
    "--paths", "/*",
    "--region", "us-east-1"
)
& aws @invArgs
if ($LASTEXITCODE -ne 0) { throw "aws cloudfront create-invalidation failed." }

Write-Host "Publish complete. Open frontend_cloudfront_url from terraform output (or your custom domain)."
