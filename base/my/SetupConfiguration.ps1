Write-Host "Start Setup Configuration"

$scripts = @(
    (Join-Path $PSScriptRoot "SetupConfigurationServerFileCacheDirectory.ps1")
    (Join-Path $runPath "EnablePerformanceCounter.ps1")
    (Join-Path $runPath "4PS/Set-AlpacaContainerKeyVaultAadAppAndCertificate.ps1")
)
Push-Location
# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)

Pop-Location


foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}