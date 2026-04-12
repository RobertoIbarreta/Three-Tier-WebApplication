<#
.SYNOPSIS
  Production build of the React (Vite) frontend.

.DESCRIPTION
  Sets VITE_API_URL to your public API base URL (ALB HTTPS DNS or custom api.example.com).
  No trailing slash. Requires Node.js and npm.

.EXAMPLE
  .\Build-Frontend.ps1 -ApiBaseUrl "https://three-tier-webapp-dev-alb-123456789.us-east-1.elb.amazonaws.com"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ApiBaseUrl
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_common.ps1"

$ApiBaseUrl = $ApiBaseUrl.TrimEnd("/")
$frontend = Join-Path (Get-RepoRoot) "app\frontend"

if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm is not on PATH. Install Node.js LTS from https://nodejs.org/"
}

Push-Location $frontend
try {
    if (-not (Test-Path "node_modules")) {
        Write-Host "npm install..."
        npm install
        if ($LASTEXITCODE -ne 0) { throw "npm install failed." }
    }
    $env:VITE_API_URL = $ApiBaseUrl
    Write-Host "VITE_API_URL=$ApiBaseUrl"
    npm run build
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed." }
    Write-Host "Done. Output: app\frontend\dist — upload with Publish-Frontend.ps1 or aws s3 sync."
}
finally {
    Remove-Item Env:VITE_API_URL -ErrorAction SilentlyContinue
    Pop-Location
}
