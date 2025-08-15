Param(
    [switch]$Silent
)

if (Get-Module 'PPIPowershellCoreUtils') { return }

$path = "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1"

if (!$Silent) {
    Write-Host ("Import PPI Powershell Core Utils from {0}" -f $path)
}

Import-Module $path -DisableNameChecking -Global -Force