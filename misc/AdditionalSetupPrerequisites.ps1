Import-Module (Join-Path $PSScriptRoot "helper\k8s-bc-helper.psd1")
Install-OpenSSH
if ($env:IsBuildContainer) {
    # seems to kill output log handling in the pipeline
    #Install-Chocolatey
    #Install-Nodejs
}