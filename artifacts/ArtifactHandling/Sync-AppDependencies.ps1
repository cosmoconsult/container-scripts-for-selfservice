<#
    .SYNOPSIS
    Syncs the unsynced direct dependencies of an app before the app is synchronized.
#>
function Sync-AppDependencies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$App,
        [Parameter(Mandatory = $false)]
        [string]$ServerInstance = "BC",
        [Parameter(Mandatory = $false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Add", "ForceSync")]
        [string]$SyncMode = "Add"
    )

    process {
        if (-not $App.Dependencies) {
            return
        }

        foreach ($dependency in @($App.Dependencies)) {
            $dependencyApp = Get-NAVAppInfo `
                -ServerInstance $ServerInstance `
                -Tenant $Tenant `
                -TenantSpecificProperties `
                -Id $dependency.AppId `
                -ErrorAction SilentlyContinue | Select-Object -First 1

            if (-not $dependencyApp) {
                continue
            }

            if ($dependencyApp.SyncState -ne "Synced") {
                try {
                    Sync-NAVApp `
                        -ServerInstance $ServerInstance `
                        -Name $dependencyApp.Name `
                        -Publisher $dependencyApp.Publisher `
                        -Version $dependencyApp.Version `
                        -Tenant $Tenant `
                        -Mode $SyncMode `
                        -Force `
                        -ErrorAction Stop
                }
                catch {
                    Write-Host "Failed to sync dependency '$($dependencyApp.Name)' ($($dependencyApp.Publisher) $($dependencyApp.Version)) for app '$($App.Name)' ($($App.Publisher) $($App.Version)) on server '$ServerInstance', tenant '$Tenant': $($_.Exception.Message)"
                }
            }
        }
    }
}
Export-ModuleMember -Function Sync-AppDependencies
