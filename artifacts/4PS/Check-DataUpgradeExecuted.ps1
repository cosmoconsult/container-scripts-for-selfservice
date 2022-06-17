<#
    .SYNOPSIS
    Checks if data upgrade of app version is executed.
    .DESCRIPTION
    Checks if data upgrade of app version is executed.
    .EXAMPLE
    Check-DataUpgradeExecuted -ServerInstance MyServerInstance - 
    .PARAMETER ServerInstance
    The Nav/Bc Server Instance where dataupgrade must be checked, eg. 'ProdBc16'
    .PARAMETER Tenant
    The Tenant of the Server Instance where dataupgrade must be checked, eg. 'default'
    .PARAMETER RequiredTenantDataVersion
    The required app version in the TenantDataVersion property (so the complete upgrade of an app version has ran). 
#>

function Check-DataUpgradeExecuted {
    [cmdletbinding()]
    PARAM
    (
        [parameter(Mandatory=$true)]
        [string]$ServerInstance,
        [string]$Tenant,
        [parameter(Mandatory=$true)]
        [string]$RequiredTenantDataVersion
    )
    PROCESS
    {
        if (!$Tenant) {
            $Tenant = 'default'
        }        
        if (((Get-NavTenant `
            -ServerInstance $ServerInstance `
            -Tenant $Tenant).TenantDataVersion) -eq $RequiredTenantDataVersion) {
                Write-Host ("### Upgrade of base app {0} in tenant {1} excecuted." -f $RequiredTenantDataVersion, $Tenant) -ForegroundColor green    
        } 
        else {
            Write-Host ("### Upgrade of base app {0} in tenant {1} NOT excecuted!" -f $RequiredTenantDataVersion, $Tenant) -ForegroundColor red
        }
    }

}

Export-ModuleMember -Function Check-DataUpgradeExecuted
