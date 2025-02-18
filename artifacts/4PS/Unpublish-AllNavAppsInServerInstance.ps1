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
        
        Write-Host "Before foreach InstalledApps $(ConvertTo-Json $InstalledApps -Compress)"
        foreach ($InstalledApp in $InstalledApps) {
            Write-Host "Before Uninstall $(ConvertTo-Json $InstalledApp -Compress)"
            if($KeepData) {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -WarningAction SilentlyContinue
            }
            else {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -DoNotSaveData -WarningAction SilentlyContinue
            }
            Write-Host "After Uninstall"
        }
        Write-Host "After foreach InstalledApps"
        
        while (Get-NAVAppInfo -ServerInstance $ServerInstance) {
            
            $ExistingApps = Get-NAVAppInfo -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant 
            Write-Host "Before foreach $(ConvertTo-Json $ExistingApps -Compress)"
            
            foreach ($ExistingApp in $ExistingApps) {  
                Write-Host "in foreach $(ConvertTo-Json $ExistingApp -Compress)"
                Unpublish-NAVApp -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance
                Write-Host "After unpublish"
                do{
                    $appinfo = Get-NAVAppInfo -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant;
                    if(!$appinfo) { break; }
                    Write-Host "Still got Get-NAVAppInfo $(ConvertTo-Json $appinfo -Compress)"
                    Start-Sleep -Seconds 5
                } while ($true)
                if (!(Get-NAVAppInfo -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance)) {
                    "App {0} with version {1} unpublished..." -f $ExistingApp.name, $ExistingApp.Version
                }
                Write-Host "End of foreach"
            }
            Write-Host "After foreach"
        } 
        Write-Host "After while Get-NAVAppInfo"
    }
}

Export-ModuleMember -Function Unpublish-AllNavAppsInServerInstance
