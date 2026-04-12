<#
.SYNOPSIS
  Cross-compile the Go API for Linux amd64 (EC2 / ASG).

.DESCRIPTION
  Requires Go 1.22+ on PATH. Output: app/backend/server (no .exe) suitable for Amazon Linux 2.

.EXAMPLE
  .\Build-Backend.ps1
  .\Build-Backend.ps1 -OutputPath C:\temp\server
#>
[CmdletBinding()]
param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_common.ps1"

$backend = Join-Path (Get-RepoRoot) "app\backend"
if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    throw "Go is not on PATH. Install from https://go.dev/dl/ and reopen the terminal."
}

Push-Location $backend
try {
    Write-Host "go mod tidy..."
    go mod tidy
    if ($LASTEXITCODE -ne 0) { throw "go mod tidy failed." }

    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"
    $out = if ($OutputPath) { $OutputPath } else { Join-Path $backend "server" }
    Write-Host "go build -> $out"
    go build -ldflags="-s -w" -o $out .
    if ($LASTEXITCODE -ne 0) { throw "go build failed." }
    Write-Host "Done. Copy this file to EC2 as /opt/app/server (see root README)."
}
finally {
    Remove-Item Env:GOOS -ErrorAction SilentlyContinue
    Remove-Item Env:GOARCH -ErrorAction SilentlyContinue
    Remove-Item Env:CGO_ENABLED -ErrorAction SilentlyContinue
    Pop-Location
}
