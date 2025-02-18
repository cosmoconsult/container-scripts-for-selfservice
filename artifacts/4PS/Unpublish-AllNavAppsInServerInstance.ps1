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
            if ($KeepData) {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force
            }
            else {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -DoNotSaveData
            }
            Write-Host "After Uninstall"
        }
        Write-Host "After foreach InstalledApps"
        $firstRun = $true
        while (Get-NAVAppInfo -ServerInstance $ServerInstance) {
            
            $ExistingApps = Get-NAVAppInfo -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant 
            Write-Host "Before foreach $(ConvertTo-Json $ExistingApps -Compress)"
            $appsToSkip = @(
                @{ Name = "System Application"; Prio = 20 },
                @{ Name = "Business Foundation"; Prio = 30 },
                @{ Name = "Base Application"; Prio = 40 },
                @{ Name = "Application"; Prio = 60 },
                @{ Name = "Intrastat Core"; Prio = 100 },
                @{ Name = "Library Assert"; Prio = 115 },
                @{ Name = "Business Foundation Test Libraries"; Prio = 110 }
            )
            $ExistingApps2 = $ExistingApps
            if($firstRun){
                $ExistingApps2 = $ExistingApps  | Where-Object { $_.Name -notin $appsToSkip.Name }
                $firstRun = $false
            }
            
            foreach ($ExistingApp in $ExistingApps2) {  
                Write-Host "in foreach $(ConvertTo-Json $ExistingApp -Compress)"
                try {
                    Unpublish-NAVApp -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance
                    Write-Host "After unpublish"
                    if (!(Get-NAVAppInfo -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance)) {
                        "App {0} with version {1} unpublished..." -f $ExistingApp.name, $ExistingApp.Version
                    }
                    Write-Host "End of foreach"
                }catch{
                    Write-Host "Error: $(ConvertTo-Json $_ -Compress)"
                }
            }
            Write-Host "After foreach"  
        } 
        Write-Host "After while Get-NAVAppInfo"
    }
}

Export-ModuleMember -Function Unpublish-AllNavAppsInServerInstance
