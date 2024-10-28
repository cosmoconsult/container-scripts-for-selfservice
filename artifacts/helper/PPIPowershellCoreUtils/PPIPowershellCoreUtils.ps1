if (Get-Module 'PPIPowershellCoreUtils') { return }

$path = Join-Path $PSScriptRoot "PPIPowershellCoreUtils.psm1"
Import-Module $path -DisableNameChecking -Global -Force