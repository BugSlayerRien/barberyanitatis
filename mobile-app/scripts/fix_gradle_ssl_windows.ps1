# Fix Gradle PKIX / plugins.gradle.org SSL errors on Windows.
# Creates %USERPROFILE%\.gradle\ssl\cacerts and updates android/gradle.properties.
#
# Usage:
#   cd mobile-app
#   powershell -ExecutionPolicy Bypass -File .\scripts\fix_gradle_ssl_windows.ps1

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$mobileAppDir = Split-Path -Parent $scriptDir
$gradleProps = Join-Path $mobileAppDir 'android\gradle.properties'

$javaHome = 'C:\Program Files\Android\Android Studio\jbr'
if (-not (Test-Path $javaHome)) {
    Write-Error "Android Studio JBR not found at: $javaHome"
}

$keytool = Join-Path $javaHome 'bin\keytool.exe'
$sourceStore = Join-Path $javaHome 'lib\security\cacerts'
$gradleSslDir = Join-Path $env:USERPROFILE '.gradle\ssl'
$userStore = Join-Path $gradleSslDir 'cacerts'
$userStoreGradle = ($userStore -replace '\\', '/')

New-Item -ItemType Directory -Force -Path $gradleSslDir | Out-Null
if (Test-Path $userStore) { Remove-Item $userStore -Force }
Copy-Item -Path $sourceStore -Destination $userStore -Force
$size = (Get-Item $userStore).Length
if ($size -lt 10000) {
    Write-Error "Trust store copy looks empty ($size bytes). Check Android Studio JBR path."
}

Write-Host "User trust store: $userStore"
Write-Host "Importing Windows LocalMachine Root certificates..."

$imported = 0
$skipped = 0
Get-ChildItem Cert:\LocalMachine\Root | ForEach-Object {
    $alias = 'winroot-' + $_.Thumbprint
    $cer = Join-Path $env:TEMP ($alias + '.cer')
    try {
        Export-Certificate -Cert $_ -FilePath $cer -Force | Out-Null
        & $keytool -importcert -alias $alias -file $cer -keystore $userStore -storepass changeit -storetype PKCS12 -noprompt 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $imported++ } else { $skipped++ }
    } catch {
        $skipped++
    } finally {
        Remove-Item $cer -ErrorAction SilentlyContinue
    }
}

# Patch gradle.properties trustStore path for this Windows user
if (Test-Path $gradleProps) {
    $content = Get-Content $gradleProps -Raw
    $content = $content -replace 'systemProp\.javax\.net\.ssl\.trustStore=.*', "systemProp.javax.net.ssl.trustStore=$userStoreGradle"
    $content = $content -replace 'systemProp\.javax\.net\.ssl\.trustStoreType=.*', 'systemProp.javax.net.ssl.trustStoreType=PKCS12'
    if ($content -notmatch 'systemProp\.javax\.net\.ssl\.trustStore=') {
        $content += "`nsystemProp.javax.net.ssl.trustStore=$userStoreGradle`n"
    }
    if ($content -notmatch 'systemProp\.javax\.net\.ssl\.trustStoreType=') {
        $content += "systemProp.javax.net.ssl.trustStoreType=PKCS12`n"
    }
    Set-Content -Path $gradleProps -Value $content.TrimEnd() -NoNewline
    Add-Content -Path $gradleProps -Value "`n"
    Write-Host "Updated: $gradleProps"
}

# Avast / other AV "HTTPS scanning" presents its own root CA to Java — import live chains.
$hosts = @('plugins.gradle.org', 'repo.maven.apache.org', 'dl.google.com', 'services.gradle.org')
foreach ($h in $hosts) {
    Write-Host "Importing live TLS chain for $h ..."
    & (Join-Path $scriptDir 'import_site_certs.ps1') -HostName $h
}

Write-Host ""
Write-Host "Done. Windows roots: imported $imported, skipped $skipped"
Write-Host ""
Write-Host "Next:"
Write-Host "  flutter config --jdk-dir=`"$javaHome`""
Write-Host "  cd $mobileAppDir"
Write-Host "  flutter clean"
Write-Host "  flutter pub get"
Write-Host "  flutter run"
