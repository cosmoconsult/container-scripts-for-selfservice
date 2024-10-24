. (Join-Path $PSScriptRoot "Invoke-CommandInPwshCore.ps1")

# Enable remoting for powershell core and create remote session
Invoke-CommandInPwshCore -ScriptBlock { Write-Host ("Powershell core session created (Version: {0})" -f $PSVersionTable.PSVersion ) }