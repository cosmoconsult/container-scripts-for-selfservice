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
        
        #$InstalledApps = @{}

        #$InstalledApps = Get-NAVAppInfo -ServerInstance $ServerInstance -TenantSpecificProperties -Tenant $Tenant | where-object 'IsInstalled' -eq $true 

        function AddAnApp { Param($anApp)
            Write-Host "AddAnApp $($anapp.Name) $($anapp.Version)"
            $alreadyAdded = $script:installedApps | Where-Object { $_.AppId -eq $anApp.AppId -and $_.Version -eq $anApp.Version }
            if (-not ($alreadyAdded)) {
                Write-Host "add dependencies"
                AddDependencies -anApp $anApp
                Write-Host "add the app $($anapp.Name)"
                [array]$script:installedApps += $anApp
            }
        }
        
        function AddDependency { Param($dependency)
            Write-Host "Add Dependency $($dependency.Name) $($dependency.Version)"
            $dependentApp = $apps | Where-Object { "$($_.AppId)" -eq "$($dependency.AppId)"  }
            if ($dependentApp) {
                @($dependentApp) | ForEach-Object { AddAnApp -AnApp $_ }
            }
        }
        
        function AddDependencies { Param($anApp)
            Write-Host "Add Dependencies for $($anApp.Name)"
            if (($anApp) -and ($anApp.Dependencies)) {
                $anApp.Dependencies | % { AddDependency -Dependency $_ }
            }
        }
        
        $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | ForEach-Object { Get-NAVAppInfo -id "$($_.AppId)" -publisher $_.publisher -name $_.name -version $_.Version -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties }
        $apps | ForEach-Object { AddAnApp -AnApp $_ }
        $apps = $script:installedApps
        [Array]::Reverse($apps)
        
        #Write-Host "Before foreach InstalledApps $(ConvertTo-Json $InstalledApps -Compress)"
        foreach ($InstalledApp in $apps) {
            #Write-Host "Before Uninstall $(ConvertTo-Json $InstalledApp -Compress)"
            if ($InstalledApp.IsInstalled -ne $true) {
                continue
            }
            if ($KeepData) {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force
            }
            else {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -DoNotSaveData
            }
            #Write-Host "After Uninstall"
        }
        #Write-Host "After foreach InstalledApps"
        $runNo = 1
        while (Get-NAVAppInfo -ServerInstance $ServerInstance) {
            #Write-Host "Before foreach $(ConvertTo-Json $ExistingApps -Compress)"
            <#$appsToUnpublishLater = @(
                @{ Name = "System Application"; Prio = 8 },
                @{ Name = "Business Foundation"; Prio = 7 },
                @{ Name = "Business Foundation W1"; Prio = 7 },
                @{ Name = "Base Application"; Prio = 6 },
                @{ Name = "4PS Construct De"; Prio = 6 },
                @{ Name = "Application"; Prio = 5 },
                @{ Name = "Intrastat Core"; Prio = 4 },
                @{ Name = "4PS System Application W1"; Prio = 4 },
                @{ Name = "Library Assert"; Prio = 3 },
                @{ Name = "4PS Base Application W1"; Prio = 3 },
                @{ Name = "Business Foundation Test Libraries"; Prio = 2 }                
            )
            $appsToSkipThisRun = $appsToUnpublishLater | Where-Object { $_.Prio -gt $runNo }
            [string[]]$names = $appsToSkipThisRun.Name
            $ExistingApps2 = $ExistingApps  | Where-Object { $_.Name -notin $names }#>
            
            foreach ($ExistingApp in $apps) {  
                #Write-Host "in foreach $(ConvertTo-Json $ExistingApp -Compress)"
                try {
                    Unpublish-NAVApp -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance
                    #Write-Host "After unpublish"
                    if (!(Get-NAVAppInfo -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance)) {
                        "App {0} with version {1} unpublished..." -f $ExistingApp.name, $ExistingApp.Version
                    }
                    #Write-Host "End of foreach"
                }
                catch {
                    Write-Host "Error: $(ConvertTo-Json $_ -Compress)"
                }
            }
            #Write-Host "After foreach"  
            $runNo = $runNo + 1
        } 
        #Write-Host "After while Get-NAVAppInfo"
    }
}

Export-ModuleMember -Function Unpublish-AllNavAppsInServerInstance
