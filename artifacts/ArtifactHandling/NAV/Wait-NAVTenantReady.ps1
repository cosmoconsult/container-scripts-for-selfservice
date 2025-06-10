
function Wait-NAVTenantReady {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        [string]$Tenant = "default",
        [int]$Retries = 30,
        [int]$RetrySeconds = 10,
        [string]$OutputPrefix = ""
    )

    Write-Host "${OutputPrefix}Wait for Tenant to be operational"
    for ($i = 0; $i -lt $Retries; $i++) {
        try {
            $TenantState = (Get-NavTenant -ServerInstance $ServerInstance -Tenant $Tenant).State
            if (($TenantState -eq "Mounted") -or ($TenantState -eq "Operational")) {
                break;
            }
            Write-Host "${OutputPrefix}- Tenant not operational yet (try ${i}), sleeping ${RetrySeconds}s"
        } catch {
            Write-Host "${OutputPrefix}- Error checking tenant state (try ${i}), sleeping ${RetrySeconds}s: $($_.Exception.Message)"
        }
        Start-Sleep -Seconds $RetrySeconds
    }
}
Export-ModuleMember -Function Wait-NAVTenantReady