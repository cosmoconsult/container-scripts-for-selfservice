$publicPath = Join-Path $PSScriptRoot "public"
. (Join-Path $publicPath "Request-PwshCoreSession.ps1")
. (Join-Path $publicPath "Invoke-CommandInPwshCore.ps1")

# Enable remoting for powershell core and create remote session
Request-PwshCoreSession | Out-Null