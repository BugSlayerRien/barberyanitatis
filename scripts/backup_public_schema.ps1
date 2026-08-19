# Portable custom-format dump of the public schema.
# Does not run inside the PHP web request. Requires local pg_dump.
param(
  [string]$OutputDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$envFile = Join-Path $root ".env"

if (Test-Path $envFile) {
  Get-Content $envFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $eq = $line.IndexOf("=")
    if ($eq -lt 1) { return }
    $key = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim().Trim('"').Trim("'")
    if (-not [string]::IsNullOrWhiteSpace($key) -and -not [Environment]::GetEnvironmentVariable($key)) {
      Set-Item -Path "Env:$key" -Value $value
    }
  }
}

if (-not $env:DB_DIRECT_URL) {
  throw "Set DB_DIRECT_URL to the Supabase direct Postgres URL (db.<project-ref>.supabase.co:5432, sslmode=require). See docs/DATABASE_BACKUP.md"
}

if ($env:DB_DIRECT_URL -match ":6543") {
  throw "DB_DIRECT_URL looks like the transaction pooler (port 6543). pg_dump needs the direct host on port 5432."
}

$pgDump = Get-Command pg_dump -ErrorAction SilentlyContinue
if (-not $pgDump) {
  throw "pg_dump not found. Install PostgreSQL client tools and ensure pg_dump is on PATH."
}

if (-not $OutputDir) {
  $OutputDir = if ($env:BACKUP_OUTPUT_DIR) { $env:BACKUP_OUTPUT_DIR } else { Join-Path $root "storage\backups" }
}
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outFile = Join-Path $OutputDir "tatis_public_$stamp.dump"

& pg_dump $env:DB_DIRECT_URL --schema=public --no-owner --no-acl --format=custom --file=$outFile
if ($LASTEXITCODE -ne 0) {
  throw "pg_dump failed with exit code $LASTEXITCODE"
}

$bytes = (Get-Item $outFile).Length
Write-Host "Wrote $(Split-Path $outFile -Leaf) ($bytes bytes)"
Write-Host "Store this file off the Render API filesystem. Do not commit it."
