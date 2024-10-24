. (Join-Path $PSScriptRoot "Request-PwshCoreSession.ps1")
. (Join-Path $PSScriptRoot "Invoke-CommandInPwshCore.ps1")

# Enable remoting for powershell core and create remote session
Request-PwshCoreSession | Out-Null