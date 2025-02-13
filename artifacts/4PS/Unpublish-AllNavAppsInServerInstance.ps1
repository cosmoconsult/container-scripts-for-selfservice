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
        [string]$Tenant,
        [bool]$KeepData
    )
    PROCESS {
        if (!$Tenant) {
            $Tenant = 'default'
        }
        if (!$ServerInstance) {
            $ServerInstance = 'BC'
        }
        
        $InstalledApps = @{}

        $InstalledApps = Get-NAVAppInfo -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant | where-object 'IsInstalled' -eq $true 
        
        foreach ($InstalledApp in $InstalledApps) {
            if($KeepData) {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -WarningAction SilentlyContinue
            }
            else {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -DoNotSaveData -WarningAction SilentlyContinue
            }
        }
        
        while (Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant ) {
            Write-Host "Beginning of while"
            $ExistingApps = Get-NAVAppInfo -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant 
            Write-Host "Existing Apps: $($ExistingApps | ConvertTo-Json -Compress)"
        
            foreach ($ExistingApp in $ExistingApps) {  
                Write-Host "Unpublish-NavApp $($ExistingApp.name) $($ExistingApp.Version), $($ExistingApp.Scope)"
                Unpublish-NAVApp -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance -ErrorAction SilentlyContinue -Tenant $Tenant
                Write-Host "After Unpublish step"
                if (!(Get-NAVAppInfo -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance -Tenant $Tenant )) {
                    "App {0} with version {1} unpublished..." -f $ExistingApp.name, $ExistingApp.Version
                }
                Write-Host "After Get-NAvAppInfo"
            }
        
        } 
    }
}

Export-ModuleMember -Function Unpublish-AllNavAppsInServerInstance
