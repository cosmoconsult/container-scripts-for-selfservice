Write-Host ""
Write-Host "=== Additional Setup ==="

function Import-PPIModules {

    if (Test-Path "c:\run\my\PPIArtifactUtils.ps1") {
        . "c:\run\my\PPIArtifactUtils.ps1"
    }

    if (Test-Path "c:\run\my\PPIOverrides.ps1") {
        . "c:\run\my\PPIOverrides.ps1"
    }

    if (Test-Path "c:\run\my\PPIAsyncUtils.ps1") {
        . "c:\run\my\PPIAsyncUtils.ps1"
    }

    if ((Test-Path 'c:\run\cosmo.compiler.helper.psm1') -and ($env:IsBuildContainer)) {
        Write-Host "Import compiler helper c:\run\cosmo.compiler.helper.psm1"
        Import-Module 'c:\run\cosmo.compiler.helper.psm1' -DisableNameChecking -Force
    }
}

Import-PPIModules
Import-NAVModules -ServiceTierFolder $serviceTierFolder -RoleTailoredClientFolder $roleTailoredClientFolder -Force 2>$null

$telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue

Invoke-LogEvent -name "AdditionalSetup - Started" -telemetryClient $telemetryClient