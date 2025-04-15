Param(
    [switch]$Silent
)

if (Get-Module 'PPIOverrides') { return }

$path = "c:\run\helper\PPIOverrides\PPIOverrides.psm1"

if (!$Silent) {
    Write-Host ("Import PPI Overrides from {0}" -f $path)
}

Import-Module $path -DisableNameChecking -Global -Force