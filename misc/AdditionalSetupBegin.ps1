Write-Host ""
Write-Host "=== Additional Setup ==="

Import-PPIModules
Import-NAVModules -ServiceTierFolder $serviceTierFolder -RoleTailoredClientFolder $roleTailoredClientFolder -Force 2>$null

$telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue

Invoke-LogEvent -name "AdditionalSetup - Started" -telemetryClient $telemetryClient