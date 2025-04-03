Param(
    [switch]$Silent
)

if (Get-Module 'PPIAsyncUtils') { return }

$path = "c:\run\helper\PPIAsyncUtils\PPIAsyncUtils.psm1"

if (!$Silent) {
    Write-Host ("Import PPI Async Utils from {0}" -f $path)
}

Import-Module $path -DisableNameChecking -Global -Force