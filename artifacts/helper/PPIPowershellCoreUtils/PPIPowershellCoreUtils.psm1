. (Join-Path $PSScriptRoot "Invoke-CommandInPwshCore.ps1")

Invoke-CommandInPwshCore -ScriptBlock { Write-Host ("Powershell core session created (Version: {0})" -f $PSVersionTable.PSVersion ) }