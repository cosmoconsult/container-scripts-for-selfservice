<#
    .SYNOPSIS
    Unpublishes all apps in a ServerInstance
    .DESCRIPTION
    Unpublishes all apps in a ServerInstance
    .EXAMPLE
    Unpublish-AllNavAppsInServerInstance -ServerInstance MyServerInstance 
    .PARAMETER ServerInstance
    The Nav/Bc Server Instance where apps must be unpublished, eg. 'ProdBc16'
    .PARAMETER Tenant
    The Tenant of the Server Instance where dataupgrade must be checked, eg. 'default'
#>

function Unpublish-AllNavAppsInServerInstance {
    [cmdletbinding()]
    PARAM
    (
        [string]$ServerInstance,
        [string]$Tenant
    )
    PROCESS
    {
        if (!$Tenant) {
            $Tenant = 'default'
        }
        if (!$ServerInstance) {
            $ServerInstance = 'BC'
        }
        
        $InstalledApps = @{}

        $InstalledApps = Get-NAVAppInfo -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant | where-object 'IsInstalled' -eq $true 
        
        foreach ($InstalledApp in $InstalledApps) {
            uninstall-navapp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -WarningAction SilentlyContinue
        }
        
        while (Get-NAVAppInfo -ServerInstance $ServerInstance) {
           
            $ExistingApps = Get-NAVAppInfo -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant 
        
            foreach ($ExistingApp in $ExistingApps) {  
                unpublish-navapp -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance -ErrorAction SilentlyContinue
                if (!(get-navappinfo -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance)) {
                    "App {0} with version {1} unpublished..." -f $ExistingApp.name, $ExistingApp.Version
                }
            }
        
        } 
    }
}

Export-ModuleMember -Function Unpublish-AllNavAppsInServerInstance
