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
        [string]$Tenant = "default"
    )

    process {
        Write-Host "Sync-AppDependencies: App=$($App.Name) Publisher=$($App.Publisher) Version=$($App.Version) ServerInstance=$ServerInstance Tenant=$Tenant"
        if (-not $App.Dependencies) {
            Write-Host "Sync-AppDependencies: no direct dependencies"
            return
        }

        foreach ($dependency in @($App.Dependencies)) {
            Write-Host "Sync-AppDependencies: checking dependency AppId=$($dependency.AppId) Name=$($dependency.Name) Publisher=$($dependency.Publisher) Version=$($dependency.Version)"
            $dependencyApp = Get-NAVAppInfo `
                -ServerInstance $ServerInstance `
                -Tenant $Tenant `
                -TenantSpecificProperties `
                -Id $dependency.AppId `
                -ErrorAction SilentlyContinue | Select-Object -First 1

            if (-not $dependencyApp) {
                Write-Host "Sync-AppDependencies: dependency not found in tenant"
                continue
            }

            Write-Host "Sync-AppDependencies: found Name=$($dependencyApp.Name) Publisher=$($dependencyApp.Publisher) Version=$($dependencyApp.Version) SyncState=$($dependencyApp.SyncState) IsPublished=$($dependencyApp.IsPublished)"
            if ($dependencyApp.SyncState -ne "Synced") {
                Write-Host "Sync dependency $($dependencyApp.Name) $($dependencyApp.Publisher) $($dependencyApp.Version)"
                Sync-NAVApp `
                    -ServerInstance $ServerInstance `
                    -Name $dependencyApp.Name `
                    -Publisher $dependencyApp.Publisher `
                    -Version $dependencyApp.Version `
                    -Tenant $Tenant `
                    -Mode Add `
                    -Force `
                    -ErrorAction SilentlyContinue `
                    -ErrorVariable dependencySyncError
                if ($dependencySyncError) {
                    Write-Host "Sync-AppDependencies: sync failed for $($dependencyApp.Name): $($dependencySyncError -join '; ')"
                }
                else {
                    Write-Host "Sync-AppDependencies: sync completed for $($dependencyApp.Name)"
                }
            }
            else {
                Write-Host "Sync-AppDependencies: dependency already synced"
            }
        }
    }
}
Export-ModuleMember -Function Sync-AppDependencies
