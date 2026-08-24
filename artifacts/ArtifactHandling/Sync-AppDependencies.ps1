<#
    .SYNOPSIS
    Syncs the unsynced direct dependencies of an app before the app is synchronized.
#>
function Sync-AppDependencies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$App,
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance = "BC",
        [Parameter(Mandatory = $false)]
        [string]$Tenant = "default"
    )

    process {
        foreach ($dependency in @($App.Dependencies)) {
            $dependencyApp = Get-NAVAppInfo `
                -ServerInstance $ServerInstance `
                -Tenant $Tenant `
                -TenantSpecificProperties `
                -AppId $dependency.AppId `
                -Version $dependency.Version `
                -ErrorAction SilentlyContinue | Select-Object -First 1

            if ($dependencyApp -and $dependencyApp.SyncState -ne "Synced") {
                Write-Host "Sync dependency $($dependencyApp.Name) $($dependencyApp.Publisher) $($dependencyApp.Version)"
                Sync-NAVApp `
                    -ServerInstance $ServerInstance `
                    -Name $dependencyApp.Name `
                    -Publisher $dependencyApp.Publisher `
                    -Version $dependencyApp.Version `
                    -Tenant $Tenant `
                    -Mode Add `
                    -Force `
                    -ErrorAction SilentlyContinue
            }
        }
    }
}
Export-ModuleMember -Function Sync-AppDependencies
