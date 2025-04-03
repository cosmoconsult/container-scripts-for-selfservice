Param(
    [switch]$Silent
)

if (Get-Module 'PPIArtifactUtils') { return }

$path = "c:\run\PPIArtifactUtils.psd1"

if (!$Silent) {
    Write-Host ("Import PPI Artifact Utils from {0}" -f $path)
}

Import-Module $path -DisableNameChecking -Global -Force