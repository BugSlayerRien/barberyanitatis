# Import live TLS certificate chain from a host into the Gradle trust store.
param(
    [string]$HostName = 'plugins.gradle.org',
    [int]$Port = 443
)

$ErrorActionPreference = 'Stop'
$javaHome = 'C:\Program Files\Android\Android Studio\jbr'
$keytool = Join-Path $javaHome 'bin\keytool.exe'
$userStore = Join-Path $env:USERPROFILE '.gradle\ssl\cacerts'

$tcp = New-Object System.Net.Sockets.TcpClient($HostName, $Port)
$ssl = New-Object System.Net.Security.SslStream($tcp.GetStream(), $false, ({ $true }))
$ssl.AuthenticateAsClient($HostName)
$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2 $ssl.RemoteCertificate
$chain = New-Object System.Security.Cryptography.X509Certificates.X509Chain
[void]$chain.Build($cert)

Write-Host "Chain for $HostName ($($chain.ChainElements.Count) certs)"
$i = 0
foreach ($el in $chain.ChainElements) {
    $i++
    $alias = "live-$HostName-$i"
    $cer = Join-Path $env:TEMP "$alias.cer"
    Export-Certificate -Cert $el.Certificate -FilePath $cer -Force | Out-Null
    & $keytool -importcert -alias $alias -file $cer -keystore $userStore -storepass changeit -storetype PKCS12 -noprompt
    Write-Host "  imported $alias : $($el.Certificate.Subject)"
    Remove-Item $cer -Force -ErrorAction SilentlyContinue
}
$ssl.Close()
$tcp.Close()
