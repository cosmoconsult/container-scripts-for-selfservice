Write-Host "Start Setup Configuration"

$scripts = @(
                        (Join-Path $runPath "EnablePerformanceCounter.ps1")
                        (Join-Path $runPath "4PS/Set-AlpacaContainerKeyVaultAadAppAndCertificate.ps1")
)
Write-Host "Set-NAVServerConfiguration -KeyName ServicesDefaultTimeZone -KeyValue `"W. Europe Standard Time`" -ServerInstance BC"
Set-NAVServerConfiguration -KeyName ServicesDefaultTimeZone -KeyValue "W. Europe Standard Time" -ServerInstance BC

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
