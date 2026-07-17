$scripts = @(
    (Join-Path $PSScriptRoot "AdditionalSetupBegin.ps1"),
    (Join-Path $PSScriptRoot "AdditionalSetupArtifacts.ps1"),
    (Join-Path $PSScriptRoot "AdditionalSetupCheckHealth.ps1"),
    (Join-Path $PSScriptRoot "AdditionalSetupDuplicateUsers.ps1"),
    (Join-Path $PSScriptRoot "AdditionalSetupAdditionalOwners.ps1"),
    (Join-Path $PSScriptRoot "AdditionalSetupCreateTestSuite.ps1"),
    (Join-Path $PSScriptRoot "AdditionalSetupCosmoSetupCompleted.ps1"), # From this point on, the container will be considered healthy and ready for use
    (Join-Path $PSScriptRoot "AdditionalSetupOpenSSH.ps1"),
    (Join-Path $PSScriptRoot "AdditionalSetupEnd.ps1")
)

Write-Host "Start AdditionalSetup"

if (!$TenantId) { $TenantId = "default" }
$serverInstanceState = (Get-NAVServerInstance $ServerInstance ).State
if ($serverInstanceState -ne "Running") {
    Write-Error "NAV ServerInstance not running, skipping AdditionalSetup..."
    return
}
$TenantState = (Get-NavTenant -ServerInstance $ServerInstance -Tenant $TenantId).State
if ($TenantState -ne "Mounted" -and $TenantState -ne "Operational") {
    Write-Error "Tenant not mounted/operational, skipping AdditionalSetup..."
    return
}

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}