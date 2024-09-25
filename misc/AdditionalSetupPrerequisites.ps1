Import-Module (Join-Path $PSScriptRoot "helper\k8s-bc-helper.psd1")
Install-OpenSSH
if ($env:IsBuildContainer) {
    Install-Chocolatey
    Install-Nodejs
}