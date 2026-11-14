<#
    .SYNOPSIS
    Deploys artifacts into a running container from a manifest with the same shape as the container creation artifacts.

    .DESCRIPTION
    DeploymentPath must contain manifest.json in the AzureDevOpsArtifacts shape passed to new containers:
        { "artifacts": [ <AlpacaArtifact> ], "devopsArtifacts": [ <DevOpsArtifact> ] }
    The manifest must not contain credentials. Azure DevOps feeds use the container's AZURE_DEVOPS_EXT_PAT, NuGet
    packages are resolved from the container's configured NuGet feeds, and other files are staged in the deployment
    folder (e.g. uploads\) and referenced by local path.
    Artifacts are processed like navstartArtifacts.ps1 (NuGet last, downloaded per dependsOn group) and imported with
    Import-Artifacts. The deployment folder is kept for traceability:
        manifest.json    deployment manifest
        deployment.json  parameters, artifacts, status, and timestamps
        deployment.log   transcript
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
$transcriptStarted = $false
$deployment = [ordered]@{
    Status                = 'Running'
    StartedAt             = (Get-Date).ToString('o')
    FinishedAt            = $null
    Error                 = $null
    DeployScope           = $DeployScope
    SyncMode              = $SyncMode
    NuGetSelectMode       = $NuGetSelectMode
    ConsiderInstalledApps = [bool]$ConsiderInstalledApps
    Artifacts             = @()
}

try {
    # Never keep credentials in the retained manifest: redact them first and refuse the deployment.
    $manifestJson = Get-Content -LiteralPath $manifestPath -Raw
    $safeManifestJson = $manifestJson `
        -replace '("pat"\s*:\s*")[^"]+(")', '$1***REDACTED***$2' `
        -replace '([?&](pat|sig)=)[^&#"]+', '$1***REDACTED***' `
        -replace '(/filebrowser/(api/public/dl|share)/)[^/?#"]+', '$1***REDACTED***'
    if ($safeManifestJson -ne $manifestJson) {
        Set-Content -LiteralPath $manifestPath -Value $safeManifestJson -Encoding UTF8
        throw 'Manifest must not contain credentials (PAT, SAS signature, or tokenized download URL)'
    }

    try {
        Start-Transcript -LiteralPath (Join-Path $DeploymentPath 'deployment.log') -Append | Out-Null
        $transcriptStarted = $true
    }
    catch {
        Write-Warning "Could not start deployment transcript: $($_.Exception.Message)"
    }

    C:\run\prompt.ps1 -silent
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop

    $manifest = $manifestJson | ConvertFrom-Json
    $ignoreIn = if ($env:IsBuildContainer) { 'build' } else { 'dev' }
    # Sort NuGet packages last while keeping the original order (same as navstartArtifacts.ps1)
    $artifacts = @(@($manifest.artifacts) + @($manifest.devopsArtifacts) |
        Where-Object { $_ -and -not ($_.ignorein -contains $ignoreIn) } |
        Group-Object { [int]($_.type -eq 'nuget') } | Sort-Object { [int]$_.Name } | ForEach-Object { $_.Group })
    if (-not $artifacts) {
        throw 'Manifest must contain at least one artifact in "artifacts" or "devopsArtifacts"'
    }
    $unsupported = @($artifacts | Where-Object { $_.target -in @('bak', 'saasbak', 'demodata') -or $_.type -eq 'ipartifact' })
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
    $deployment.Artifacts = $artifacts

    # Download per dependency for separated indexes (same as navstartArtifacts.ps1)
    $artifacts | Group-Object -Property dependsOn | ForEach-Object { $_.Group | Invoke-DownloadArtifact @downloadParameters }

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
            -SkipFontImport (-not $importFonts) `
            -ErrorAction Stop `
            -SkipServiceRestartCheck `
            -PublicDnsName $PublicDnsName `
            -ContainerId $ContainerId `
            -ContainerUser $ContainerUser `
            -ContainerPassword $ContainerPassword
        $importFonts = $false
    }

    $deployment.Status = 'Succeeded'
    Write-Host 'Artifact import finished'
}
catch {
    $deployment.Status = 'Failed'
    $deployment.Error = $_.Exception.Message
    Write-Host "Artifact deployment failed: $($_.Exception.Message)"
    throw
}
finally {
    $deployment.FinishedAt = (Get-Date).ToString('o')
    try {
        $deployment | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $DeploymentPath 'deployment.json') -Encoding UTF8
    }
    catch {
        Write-Warning "Could not write deployment info: $($_.Exception.Message)"
    }
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
