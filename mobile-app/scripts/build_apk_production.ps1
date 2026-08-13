# Build release APK pointing at Render production API.
# Output: build/app/outputs/flutter-apk/app-release.apk

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    flutter build apk --release `
        --dart-define=USE_PRODUCTION_API=true
    Write-Host ""
    Write-Host "APK: build/app/outputs/flutter-apk/app-release.apk"
} finally {
    Pop-Location
}
