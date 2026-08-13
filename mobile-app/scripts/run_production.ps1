# Run mobile app against live Render API (physical device or emulator).
# Usage: .\scripts\run_production.ps1
# Optional: .\scripts\run_production.ps1 -Device chrome

param(
    [string]$Device = ""
)

$defines = @(
    "--dart-define=USE_PRODUCTION_API=true"
)

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($Device) {
        flutter run @defines -d $Device
    } else {
        flutter run @defines
    }
} finally {
    Pop-Location
}
