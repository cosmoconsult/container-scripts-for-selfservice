[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppDirectory,
    [ValidateSet('Global', 'Tenant', 'Dev')]
    [string]$Scope = 'Tenant',
    [ValidateSet('Add', 'ForceSync')]
    [string]$SyncMode = 'Add',
    [string]$PublicDnsName = '',
    [string]$ContainerId = '',
    [string]$ContainerUser = '',
    [string]$ContainerPassword = ''
)

C:\run\prompt.ps1

try {
    if (-not (Test-Path -LiteralPath $AppDirectory -PathType Container)) {
        throw "App directory '$AppDirectory' does not exist"
    }

    Write-Host "[AppListV2] Resolving dependencies for app files in '$AppDirectory'"
    if (-not (Get-Command Get-AppFilesSortedByDependencies -ErrorAction SilentlyContinue)) {
        Write-Host '[AppListV2] Loading app dependency helper'
        Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force
    }

    $orderedApps = @(Get-AppFilesSortedByDependencies -Path $AppDirectory)
    if ($orderedApps.Count -eq 0) {
        throw "No app files found in '$AppDirectory'"
    }

    Write-Host "[AppListV2] Deploying $($orderedApps.Count) app(s) in dependency order"
    foreach ($orderedApp in $orderedApps) {
        Write-Host "[AppListV2] Deploying '$($orderedApp.Name)' version $($orderedApp.Version)"
        & 'C:\run\Invoke-AppDeploymentV2.ps1' `
            -AppPath $orderedApp.Path `
            -Scope $Scope `
            -SyncMode $SyncMode `
            -PublicDnsName $PublicDnsName `
            -ContainerId $ContainerId `
            -ContainerUser $ContainerUser `
            -ContainerPassword $ContainerPassword
    }
}
catch {
    Write-Host "[AppListV2] App deployment failed: $($_.Exception.Message)"
    throw
}