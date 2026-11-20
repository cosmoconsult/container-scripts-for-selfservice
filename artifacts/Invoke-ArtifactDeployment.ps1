<#
    .SYNOPSIS
    Deploys artifacts into a running container from a manifest with the same shape as the container creation artifacts.

    .DESCRIPTION
    DeploymentPath must contain manifest.json in the AzureDevOpsArtifacts shape passed to new containers:
        { "artifacts": [ <AlpacaArtifact> ], "devopsArtifacts": [ <DevOpsArtifact> ] }
    The manifest is removed after reading; deployment status and output remain available through AsyncExec.
    Azure DevOps feeds use the container's AZURE_DEVOPS_EXT_PAT, NuGet packages are resolved from the container's
    configured NuGet feeds, and other files are staged in the deployment folder (e.g. uploads\) and referenced by
    local path.
    Invalid manifests are rejected.
    Artifacts are processed like navstartArtifacts.ps1 (NuGet last, downloaded per dependsOn group) and imported with
    Import-Artifacts without applying the startup app exclusion filter. The deployment folder is kept for traceability:
        uploads\         uploaded artifacts
        apps\            downloaded artifacts (general\ and dependent-on-<dependsOn>\)
#>
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$DeploymentPath,
    [ValidateSet('Global', 'Tenant', 'Dev')]
    [string]$DeployScope = 'Tenant',
    [ValidateSet('Add', 'ForceSync')]
    [string]$SyncMode = 'Add',
    [ValidateSet('Earliest', 'EarliestMatching', 'Latest', 'LatestMatching', 'Exact', 'Any')]
    [string]$NuGetSelectMode = '',
    [switch]$ConsiderInstalledApps,
    [string]$PublicDnsName = '',
    [string]$ContainerId = '',
    [string]$ContainerUser = '',
    [string]$ContainerPassword = ''
)

$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $DeploymentPath 'manifest.json'
$appsPath = Join-Path $DeploymentPath 'apps'

try {
    $manifestJson = Get-Content -LiteralPath $manifestPath -Raw
    Remove-Item -LiteralPath $manifestPath -Force -ErrorAction Stop
    try {
        $manifest = ConvertFrom-Json -InputObject $manifestJson -ErrorAction Stop
    }
    catch {
        throw 'Manifest is invalid JSON'
    }
    C:\run\prompt.ps1 -silent
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop

    $ignoreIn = if ($env:IsBuildContainer) { 'build' } else { 'dev' }
    # Sort NuGet packages last while keeping the original order (same as navstartArtifacts.ps1)
    $artifacts = @(@($manifest.artifacts) + @($manifest.devopsArtifacts) |
        Where-Object { $_ -and -not ($_.ignorein -contains $ignoreIn) } |
        Group-Object { [int]($_.type -eq 'nuget') } | Sort-Object { [int]$_.Name } | ForEach-Object { $_.Group })
    if (-not $artifacts) {
        throw 'Manifest must contain at least one artifact in "artifacts" or "devopsArtifacts"'
    }
    $unsupported = @($artifacts | Where-Object { $_.target -in @('demodata', 'ipartifact') -or $_.type -eq 'ipartifact' })
    if ($unsupported) {
        throw "Artifacts cannot be deployed into a running container: $($unsupported.name -join ', ')"
    }

    $serviceTierFolder = Get-NAVServiceTierFolder
    $downloadParameters = @{
        Destination             = $appsPath
        GroupByDependency       = $true
        ServiceTierFolder       = $serviceTierFolder
        SkipServiceRestartCheck = $true
        ThrowOnError            = $true
        ValidateArtifact        = $true
    }
    if ($artifacts | Where-Object { $_.type -eq 'nuget' }) {
        if ($NuGetSelectMode) {
            $env:nuGetFeedSelectMode = $NuGetSelectMode
        }
        . 'C:\run\my\ExtendedEnvironment.ps1' # NuGet feeds are configured in the extended environment
        Install-NuGetTools
        Initialize-NuGetFeeds
        $artifacts = @(Resolve-NuGetArtifactsFromLocalAppFiles -Artifacts $artifacts -ServiceTierFolder $serviceTierFolder)
        if ($ConsiderInstalledApps) {
            $downloadParameters.InstalledPackages = @(Get-InstalledApps -IncludeMicrosoft |
                ForEach-Object {
                    [PSCustomObject]@{
                        Package   = '{0}.{1}.{2}' -f $_.Publisher, $_.Name, $_.AppId -replace ' '
                        Name      = [string]$_.Name
                        Publisher = [string]$_.Publisher
                        Id        = [string]$_.AppId
                        Version   = [string]$_.Version
                    }
                })
        }
    }
    $downloadParameters.AllArtifacts = $artifacts
    # Add-ins and fonts share destinations across dependency groups and need a single index.
    $artifacts | Where-Object { $_.target -in @('dll', 'add-ins', 'font', 'fonts') } |
        Invoke-DownloadArtifact @downloadParameters
    $artifacts | Where-Object { $_.target -notin @('dll', 'add-ins', 'font', 'fonts') } |
        Group-Object -Property dependsOn | ForEach-Object { $_.Group | Invoke-DownloadArtifact @downloadParameters }

    New-Item -Path $appsPath -ItemType Directory -Force | Out-Null
    $importPaths = @(Get-ChildItem -LiteralPath $appsPath -Directory |
        Where-Object Name -Match '^(general|dependent-on-.+)$' |
        Sort-Object { $_.Name -ne 'general' }, Name |
        ForEach-Object FullName)
    if (-not $importPaths) {
        $importPaths = @($appsPath) # e.g. only fonts, which are downloaded to c:\fonts
    }
    $importFonts = [bool]($artifacts | Where-Object { $_.target -in @('font', 'fonts') })
    foreach ($importPath in $importPaths) {
        Import-Artifacts `
            -Path $importPath `
            -NavServiceName 'MicrosoftDynamicsNavServer$BC' `
            -ServerInstance BC `
            -Scope $DeployScope `
            -SyncMode $SyncMode `
            -ExcludeApps $false `
            -SkipFontImport (-not $importFonts) `
            -ErrorAction Stop `
            -SkipServiceRestartCheck `
            -PublicDnsName $PublicDnsName `
            -ContainerId $ContainerId `
            -ContainerUser $ContainerUser `
            -ContainerPassword $ContainerPassword
        $importFonts = $false
    }

    Write-Host 'Artifact import finished'
}
catch {
    Write-Host "Artifact deployment failed: $($_.Exception.Message)"
    throw
}
