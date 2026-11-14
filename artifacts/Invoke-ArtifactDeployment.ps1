<#
    .SYNOPSIS
    Deploys artifacts into a running container from a manifest with the same shape as the container creation artifacts.

    .DESCRIPTION
    The manifest uses the AzureDevOpsArtifacts shape passed to new containers:
        { "artifacts": [ <AlpacaArtifact> ], "devopsArtifacts": [ <DevOpsArtifact> ] }
    It must not contain credentials: no "pat" values and no URLs with pat/sig query parameters or filebrowser
    download tokens. Azure DevOps feeds are accessed with the container's AZURE_DEVOPS_EXT_PAT; protected files
    are staged into the deployment folder (e.g. uploads\) and referenced by local path.
    Artifacts are grouped like navstartArtifacts.ps1 (NuGet last, grouped by dependsOn), downloaded with
    Invoke-DownloadArtifact, and imported with Import-Artifacts (apps sorted by dependencies).

    Every deployment is staged in its own folder (default C:\run\my\deployments\<timestamp>) and is kept for traceability:
        manifest.json    deployment manifest (credential-free)
        deployment.json  parameters, normalized artifacts, status, and timestamps
        deployment.log   transcript
        apps\            downloaded artifacts (general\ and dependent-on-<dependsOn>\)
#>
[CmdletBinding()]
param (
    [string]$ArtifactsPath = '',
    [string]$DeploymentPath = '',
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
$deploymentsRoot = 'C:\run\my\deployments'
$supportedTypes = @('nuget', 'url', 'upack')
$supportedTargets = @('app', 'rapidstart', 'fob', 'dll', 'add-ins', 'font', 'fonts')
$previousNuGetFeedSelectMode = $env:nuGetFeedSelectMode
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

if (-not $DeploymentPath) {
    if (-not $ArtifactsPath) {
        throw 'ArtifactsPath or DeploymentPath is required'
    }
    $DeploymentPath = Join-Path $deploymentsRoot (Get-Date -Format 'yyyyMMdd-HHmmss-fff')
    if (Test-Path -LiteralPath $DeploymentPath) {
        throw "Deployment folder '$DeploymentPath' already exists"
    }
}
New-Item -Path $DeploymentPath -ItemType Directory -Force | Out-Null
$DeploymentPath = (Get-Item -LiteralPath $DeploymentPath).FullName
$manifestPath = Join-Path $DeploymentPath 'manifest.json'
$deploymentInfoPath = Join-Path $DeploymentPath 'deployment.json'
$appsPath = Join-Path $DeploymentPath 'apps'
if (-not $ArtifactsPath) {
    $ArtifactsPath = $manifestPath
}

function Save-DeploymentInfo {
    try {
        $deployment | ConvertTo-Json -Depth 20 |
            Set-Content -LiteralPath $deploymentInfoPath -Encoding UTF8
    }
    catch {
        Write-Warning "Could not write deployment info '$deploymentInfoPath': $($_.Exception.Message)"
    }
}

# The manifest must be credential-free. Check it before anything else runs so credentials are never retained.
# Patterns match what Get-SafeArtifactUri redacts (PATs, SAS signatures, filebrowser download tokens).
$manifestJson = Get-Content -LiteralPath $ArtifactsPath -Raw
$credentialPatterns = @{
    '("pat"\s*:\s*")[^"]+(")'                = '$1***REDACTED***$2'
    '([?&](pat|sig)=)[^&#"]+'                = '$1***REDACTED***'
    '(/filebrowser/api/public/dl/)[^/?#"]+' = '$1***REDACTED***'
}
$safeManifestJson = $manifestJson
foreach ($pattern in $credentialPatterns.Keys) {
    $safeManifestJson = $safeManifestJson -replace $pattern, $credentialPatterns[$pattern]
}
Set-Content -LiteralPath $manifestPath -Value $safeManifestJson -Encoding UTF8
if ([System.IO.Path]::GetFullPath($ArtifactsPath) -ne $manifestPath) {
    Remove-Item -LiteralPath $ArtifactsPath -Force
}
if ($safeManifestJson -ne $manifestJson) {
    $deployment.Status = 'Failed'
    $deployment.Error = 'Manifest contains credentials'
    $deployment.FinishedAt = (Get-Date).ToString('o')
    Save-DeploymentInfo
    throw 'Manifest must not contain credentials (PAT, SAS signature, or tokenized download URL). DevOps feeds use the container''s AZURE_DEVOPS_EXT_PAT; stage other protected files as uploads.'
}

try {
    try {
        Start-Transcript -LiteralPath (Join-Path $DeploymentPath 'deployment.log') -Append | Out-Null
        $transcriptStarted = $true
    }
    catch {
        Write-Warning "Could not start deployment transcript: $($_.Exception.Message)"
    }
    Write-Host "[Deploy] Deployment folder: $DeploymentPath"

    C:\run\prompt.ps1 -silent
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop

    $manifest = $manifestJson | ConvertFrom-Json
    $artifacts = @(@($manifest.artifacts) + @($manifest.devopsArtifacts) | Where-Object { $_ })
    $ignoreIn = if ($env:IsBuildContainer) { 'build' } else { 'dev' }
    $artifacts = @($artifacts | Where-Object { -not ($_.ignorein -contains $ignoreIn) })
    if (-not $artifacts.Count) {
        throw 'Manifest must contain at least one artifact in "artifacts" or "devopsArtifacts"'
    }

    # Make type and target explicit using the defaults of the container creation request
    $artifacts = @(foreach ($artifact in $artifacts) {
        $artifact = $artifact.PSObject.Copy()
        if ([string]::IsNullOrWhiteSpace($artifact.name)) {
            throw 'Artifact name is required'
        }
        $type = ([string]$artifact.type).ToLowerInvariant()
        if (-not $type) {
            $type = if ($artifact.url) { 'url' } else { 'upack' }
        }
        $target = ([string]$artifact.target).ToLowerInvariant()
        if (-not $target) {
            $target = 'app'
        }
        if ($type -notin $supportedTypes) {
            throw "Artifact '$($artifact.name)' has unsupported type '$($artifact.type)'. Supported: $($supportedTypes -join ', ')"
        }
        if ($target -notin $supportedTargets) {
            throw "Artifact '$($artifact.name)' has target '$($artifact.target)', which cannot be deployed into a running container. Supported: $($supportedTargets -join ', ')"
        }
        if ($type -eq 'url') {
            if ([string]::IsNullOrWhiteSpace($artifact.url)) {
                throw "Artifact '$($artifact.name)' of type Url requires a url"
            }
            if ($artifact.url -notmatch '^https?://') {
                $artifact | Add-Member -NotePropertyName url -NotePropertyValue (Get-Item -LiteralPath $artifact.url).FullName -Force
            }
        }
        $artifact | Add-Member -NotePropertyName type -NotePropertyValue $type -Force
        $artifact | Add-Member -NotePropertyName target -NotePropertyValue $target -Force
        if ($target -in @('dll', 'add-ins')) {
            Write-Warning "Add-in artifact '$($artifact.name)' is copied to the service tier; a service restart is required to load it."
        }
        $artifact
    })

    # Sort NuGet packages last while keeping the original order (same as navstartArtifacts.ps1)
    $artifacts = @($artifacts | Group-Object { [int]($_.type -eq 'nuget') } | Sort-Object { [int]$_.Name } | ForEach-Object { $_.Group })

    $hasNuGet = $null -ne ($artifacts | Where-Object { $_.type -eq 'nuget' } | Select-Object -First 1)
    $serviceTierFolder = Get-NAVServiceTierFolder
    $downloadParameters = @{
        Destination             = $appsPath
        GroupByDependency       = $true
        ServiceTierFolder       = $serviceTierFolder
        SkipServiceRestartCheck = $true
        ThrowOnError            = $true
        ValidateArtifact        = $true
    }
    if ($hasNuGet) {
        if ($NuGetSelectMode) {
            $env:nuGetFeedSelectMode = $NuGetSelectMode
        }
        . 'C:\run\my\ExtendedEnvironment.ps1'
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
    Save-DeploymentInfo

    Write-Host "[Deploy] Downloading $($artifacts.Count) artifact(s) to '$appsPath'"
    $artifacts |
        Group-Object -Property dependsOn |
        ForEach-Object {
            # Download per dependency for separated indexes (same as navstartArtifacts.ps1)
            $_.Group | Invoke-DownloadArtifact @downloadParameters
        }

    $importPaths = @()
    if (Test-Path -LiteralPath (Join-Path $appsPath 'general')) {
        $importPaths += Join-Path $appsPath 'general'
    }
    if (Test-Path -LiteralPath $appsPath) {
        $importPaths += @(Get-ChildItem -LiteralPath $appsPath -Directory -Filter 'dependent-on-*' | Sort-Object Name | ForEach-Object { $_.FullName })
    }
    $hasFonts = $null -ne ($artifacts | Where-Object { $_.target -in @('font', 'fonts') } | Select-Object -First 1)
    if (-not $importPaths -and $hasFonts) {
        New-Item -Path $appsPath -ItemType Directory -Force | Out-Null
        $importPaths = @($appsPath)
    }

    Write-Host "[Deploy] Importing artifacts with scope '$DeployScope' and sync mode '$SyncMode'"
    $importFonts = $hasFonts
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
    throw
}
finally {
    $env:nuGetFeedSelectMode = $previousNuGetFeedSelectMode
    $deployment.FinishedAt = (Get-Date).ToString('o')
    Save-DeploymentInfo
    Write-Host "[Deploy] Deployment files kept in '$DeploymentPath'"
    if ($transcriptStarted) {
        Stop-Transcript | Out-Null
    }
}
