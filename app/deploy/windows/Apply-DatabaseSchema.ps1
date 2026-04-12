<#
.SYNOPSIS
  Runs database/schema.sql against RDS using credentials from Secrets Manager.

.DESCRIPTION
  Requires AWS CLI and the mysql client on PATH (e.g. MariaDB or MySQL Shell for Windows).
  Fetches the master secret JSON (host, port, username, password, dbname) via your AWS credentials.

  RDS is private in this stack: this only works if your machine can reach the DB on port 3306
  (e.g. VPN, temporary SG rule, or run the equivalent mysql command on an app EC2 instance via SSM).

.EXAMPLE
  .\Apply-DatabaseSchema.ps1
  .\Apply-DatabaseSchema.ps1 -SecretArn "arn:aws:secretsmanager:us-east-1:123456789012:secret:..."
#>
[CmdletBinding()]
param(
    [string]$SecretArn = "",
    [string]$SchemaFile = ""
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\_common.ps1"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI not on PATH."
}
if (-not (Get-Command mysql -ErrorAction SilentlyContinue)) {
    throw "mysql client not on PATH. Install MariaDB Client or MySQL Shell, or run schema.sql on an EC2 instance (Session Manager) with mysql installed."
}

if (-not $SecretArn) {
    $SecretArn = (Invoke-TerraformOutput -Name "db_master_user_secret_arn" -Raw).Trim()
}

if (-not $SchemaFile) {
    $SchemaFile = Join-Path (Get-RepoRoot) "app\database\schema.sql"
}
if (-not (Test-Path $SchemaFile)) {
    throw "Schema not found: $SchemaFile"
}

Write-Host "Fetching secret..."
$jsonText = aws secretsmanager get-secret-value --secret-id $SecretArn --query SecretString --output text
if ($LASTEXITCODE -ne 0) { throw "get-secret-value failed." }

$sec = $jsonText | ConvertFrom-Json
$hostName = $sec.host
$port = if ($sec.port) { [string]$sec.port } else { "3306" }
$user = $sec.username
$pass = $sec.password
$db = $sec.dbname

if (-not $hostName -or -not $user -or -not $db) {
    throw "Secret JSON missing host, username, or dbname."
}

$sql = Get-Content -Raw -Path $SchemaFile
# MYSQL_PWD avoids passing password on the command line (still protect your shell session).
$env:MYSQL_PWD = $pass
try {
    Write-Host "Applying schema to ${user}@${hostName}:${port}/${db} ..."
    $sql | & mysql -h $hostName -P $port -u $user --protocol=TCP $db
    if ($LASTEXITCODE -ne 0) { throw "mysql exited with code $LASTEXITCODE." }
}
finally {
    Remove-Item Env:MYSQL_PWD -ErrorAction SilentlyContinue
}

Write-Host "Schema applied."
