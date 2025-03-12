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
            $alreadyAdded = $script:installedApps | Where-Object { $_.AppId -eq $anApp.AppId -and $_.Version -eq $anApp.Version }
            if (-not ($alreadyAdded)) {
                AddDependencies -anApp $anApp
                [array]$script:installedApps += $anApp
            }
        }
        
        function AddDependency { Param($dependency)
            $dependentApp = $apps | Where-Object { "$($_.AppId)" -eq "$($dependency.AppId)"  }
            if ($dependentApp) {
                @($dependentApp) | ForEach-Object { AddAnApp -AnApp $_ }
            }
        }
        
        function AddDependencies { Param($anApp)
            if (($anApp) -and ($anApp.Dependencies)) {
                $anApp.Dependencies | % { AddDependency -Dependency $_ }
            }
        }
        
        $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties | ForEach-Object { Get-NAVAppInfo -id "$($_.AppId)" -publisher $_.publisher -name $_.name -version $_.Version -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties }
        $apps | ForEach-Object { AddAnApp -AnApp $_ }
        $apps = $script:installedApps
        [Array]::Reverse($apps)
        
        foreach ($InstalledApp in $apps) {
            if ($InstalledApp.IsInstalled -ne $true) {
                continue
            }
            Write-Host "Uninstalling $($InstalledApp.name) version $($InstalledApp.Version)..."
            if ($KeepData) {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force
            }
            else {
                Uninstall-NAVApp -Name $InstalledApp.name -Version $InstalledApp.Version -ServerInstance $ServerInstance -Force -DoNotSaveData
            }
        }
        $runNo = 1
        while (Get-NAVAppInfo -ServerInstance $ServerInstance) {
            foreach ($ExistingApp in $apps) {  
                Write-Host "Unpublishing $($ExistingApp.name) version $($ExistingApp.Version)..."
                try {
                    Unpublish-NAVApp -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance
                    if (!(Get-NAVAppInfo -Name $ExistingApp.name -Version $ExistingApp.Version -ServerInstance $ServerInstance)) {
                        "App {0} with version {1} unpublished..." -f $ExistingApp.name, $ExistingApp.Version
                    }
                }
                catch {
                    Write-Host "Error: $(ConvertTo-Json $_ -Compress)"
                }
            }
            $runNo = $runNo + 1
            if ($runNo -gt 10) {
                Write-Host "Error: Could not unpublish all apps, finishing after run $runNo"
                break
            }
        } 
    }
}

Export-ModuleMember -Function Unpublish-AllNavAppsInServerInstance
