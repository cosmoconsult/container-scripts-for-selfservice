$scripts = @(
                        (Join-Path $PSScriptRoot "AdditionalSetupArtifacts.ps1"),
                        (Join-Path $PSScriptRoot "AdditionalSetupSSH.ps1")
)

Write-Host "Start AdditionalSetup"

if (!$TenantId) { $TenantId = "default" }
$serverInstanceState = (Get-NAVServerInstance BC).State
if ($serverInstanceState -ne "Running") {
    Write-Error "Error: NAV ServerInstance not running, aborting AdditionalSetup..."
    exit 1
}
$TenantState = (Get-NavTenant -ServerInstance BC -Tenant $TenantId).State
if ($TenantState -ne "Mounted" -and $TenantState -ne "Operational") {
    Write-Error "Error: Tenant not mounted/operational, aborting AdditionalSetup..."
    exit 1
}

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}