Param(
    [switch]$Silent
)

if (Get-Module 'PPIPowershellUtils') { return }

$path = "c:\run\helper\PPIPowershellUtils\PPIPowershellUtils.psm1"

if (!$Silent) {
    Write-Host ("Import PPI Powershell Utils from {0}" -f $path)
}

Import-Module $path -DisableNameChecking -Global -Force