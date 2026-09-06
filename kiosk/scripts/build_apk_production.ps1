# Build the kiosk release APK pointing at the Render production API.
# Output: kiosk/build/app/outputs/flutter-apk/app-release.apk
#
# Mirrors mobile-app/scripts/build_apk_production.ps1. The kiosk is a separate
# Flutter project that depends on mobile-app by path, so ApiConfig (and the
# USE_PRODUCTION_API switch it reads) comes from that package.
#
# Usage:
#   .\scripts\build_apk_production.ps1
#   .\scripts\build_apk_production.ps1 -SplitPerAbi     # smaller per-device APKs

param(
    [switch]$SplitPerAbi
)

$ErrorActionPreference = "Stop"

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    $defines = @("--dart-define=USE_PRODUCTION_API=true")

    $buildArgs = @("build", "apk", "--release") + $defines
    if ($SplitPerAbi) {
        $buildArgs += "--split-per-abi"
    }

    Write-Host "Building kiosk APK against production API..." -ForegroundColor Cyan
    & flutter @buildArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build apk failed with exit code $LASTEXITCODE"
    }

    Write-Host ""
    $outDir = Join-Path (Get-Location) "build\app\outputs\flutter-apk"
    if (Test-Path $outDir) {
        Get-ChildItem -Path $outDir -Filter "*.apk" |
            ForEach-Object {
                $sizeMb = [math]::Round($_.Length / 1MB, 1)
                Write-Host ("APK: {0} ({1} MB)" -f $_.FullName, $sizeMb) -ForegroundColor Green
            }
    } else {
        Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk"
    }
} finally {
    Pop-Location
}
