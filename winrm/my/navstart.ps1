$alops_docker_username = "${env:alops-docker-username}"
$alops_docker_password = "${env:alops-docker-password}"

Invoke-Expression "net user /add $alops_docker_username $alops_docker_password"
Invoke-Expression "net localgroup Administrators $alops_docker_username /add"
$cert = New-SelfSignedCertificate -DnsName "dontcare" -CertStoreLocation Cert:\LocalMachine\My
winrm create winrm/config/Listener?Address=*+Transport=HTTPS ('@{Hostname="dontcare"; CertificateThumbprint="' + $cert.Thumbprint + '"}')
winrm set winrm/config/service/Auth '@{Basic="true"}'

# this is from custom-scripts package
$downloadCustomScriptsScript = "C:\run\my\CC-DownloadCustomScripts.ps1"

if (Test-Path $downloadCustomScriptsScript) {
  . $downloadCustomScriptsScript
}

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)