Param(
    [switch]$ShowImportMessage
)

if (Get-Module 'PPIOverrides') { return }

$path = Join-Path $PSScriptRoot "PPIOverrides.psm1"

if ($ShowImportMessage) {
    Write-Host ("Import PPI Overrides from {0}" -f $path)
}

Import-Module $path -DisableNameChecking -Global -Force