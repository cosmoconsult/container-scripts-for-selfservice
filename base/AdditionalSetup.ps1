$scripts = @(
                        (Join-Path $PSScriptRoot "AdditionalSetupArtifacts.ps1"),
                        (Join-Path $PSScriptRoot "AdditionalSetupSSH.ps1")
)

Write-Host "Start AdditionalSetup"

if (!$TenantId) { $TenantId = "default" }
$serverInstanceState = (Get-NAVServerInstance BC).State
if ($serverInstanceState -ne "Running") {
    throw "NAV ServerInstance not running, aborting AdditionalSetup"
}
$TenantState = (Get-NavTenant -ServerInstance BC -Tenant $TenantId).State
if ($TenantState -ne "Mounted" -and $TenantState -ne "Operational") {
    throw "Tenant not mounted/operational, aborting AdditionalSetup"
}

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}