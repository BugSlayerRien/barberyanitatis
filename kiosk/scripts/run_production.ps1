# Run the kiosk app against the live Render API (tablet or emulator).
#
# Usage:
#   .\scripts\run_production.ps1
#   .\scripts\run_production.ps1 -Device chrome
#
# To run against a local XAMPP API on the shop LAN instead, pass -LanHost:
#   .\scripts\run_production.ps1 -LanHost 192.168.1.3

param(
    [string]$Device = "",
    [string]$LanHost = ""
)

$ErrorActionPreference = "Stop"

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if ($LanHost) {
        # LAN_HOST only takes effect when USE_PRODUCTION_API is false.
        $defines = @("--dart-define=LAN_HOST=$LanHost")
        Write-Host "Kiosk -> local API at $LanHost" -ForegroundColor Cyan
    } else {
        $defines = @("--dart-define=USE_PRODUCTION_API=true")
        Write-Host "Kiosk -> production API" -ForegroundColor Cyan
    }

    if ($Device) {
        & flutter run @defines -d $Device
    } else {
        & flutter run @defines
    }
} finally {
    Pop-Location
}
