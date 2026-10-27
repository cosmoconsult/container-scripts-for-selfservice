[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ArtifactsPath,
    [ValidateSet('Global', 'Tenant', 'Dev')]
    [string]$DeployScope = 'Tenant',
    [ValidateSet('Add', 'ForceSync')]
    [string]$SyncMode = 'Add',
    [ValidateSet('Earliest', 'EarliestMatching', 'Latest', 'LatestMatching', 'Exact', 'Any')]
    [string]$NuGetSelectMode = '',
    [switch]$ConsiderInstalledApps,
    [switch]$KeepUploadedFiles,
    [switch]$PreserveArtifactOrder,
    [string]$PublicDnsName = '',
    [string]$ContainerId = '',
    [string]$ContainerUser = '',
    [string]$ContainerPassword = ''
)

$ErrorActionPreference = 'Stop'
$artifacts = @()
$workingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$previousNuGetFeedSelectMode = $env:nuGetFeedSelectMode

try {
    $artifacts = Get-Content -LiteralPath $ArtifactsPath -Raw | ConvertFrom-Json
    $artifacts = @($artifacts)
    if (-not $artifacts.Count) {
        throw 'Artifacts must not be empty'
    }
    C:\run\prompt.ps1 -silent

    if ($NuGetSelectMode) {
        $env:nuGetFeedSelectMode = $NuGetSelectMode
    }
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    Write-Host "[Deploy] Preparing artifact deployment with scope '$DeployScope'"
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop

    $artifactIndex = 0
    $downloadArtifacts = @(foreach ($artifact in $artifacts) {
        $artifactType = ([string]$artifact.Type).ToLowerInvariant()
        if ($artifactType -notin @('nuget', 'source')) {
            throw "Unsupported artifact type '$($artifact.Type)'"
        }
        $downloadArtifact = $artifact.PSObject.Copy()
        if ($artifactType -eq 'nuget') {
            if ([string]::IsNullOrWhiteSpace($artifact.Name)) {
                throw 'Name is required for NuGet deployments'
            }
        }
        else {
            $sourceUrl = [string]$artifact.Source
            if ([string]::IsNullOrWhiteSpace($sourceUrl)) {
                throw 'Source is required for URL or local path deployments'
            }
            if ($sourceUrl -notmatch '^https?://') {
                $sourceUrl = (Get-Item -LiteralPath $sourceUrl -ErrorAction Stop).FullName
            }
            $downloadArtifact | Add-Member -NotePropertyName Url -NotePropertyValue $sourceUrl -Force
            if (-not $downloadArtifact.Name) {
                $downloadArtifact | Add-Member -NotePropertyName Name -NotePropertyValue 'artifact' -Force
            }
        }
        if ($PreserveArtifactOrder) {
            $artifactIndex++
            $downloadArtifact | Add-Member -NotePropertyName TargetFolder -NotePropertyValue ('{0:D3}' -f $artifactIndex) -Force
        }
        $downloadArtifact
    })

    $downloadParameters = @{
        Destination = $workingDirectory
        AllArtifacts = $downloadArtifacts
        SkipServiceRestartCheck = $true
        ThrowOnError = $true
        ValidateArtifact = $true
    }
    if ($downloadArtifacts | Where-Object Type -eq 'nuget') {
        . 'C:\run\my\ExtendedEnvironment.ps1'
        Install-NuGetTools
        Initialize-NuGetFeeds
        if ($ConsiderInstalledApps) {
            . (Join-Path $PSScriptRoot 'ArtifactHandling/Get-InstalledApps.ps1')
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
    $downloadArtifacts | Invoke-DownloadArtifact @downloadParameters

    Write-Host "[Deploy] Importing artifacts with scope '$DeployScope' and sync mode '$SyncMode'"
    $importPaths = @($workingDirectory) # if not preserving artifact order, the working directory is the only path
    if ($PreserveArtifactOrder) {
        Write-Host '[Deploy] Using manual artifact order'
        $importPaths = @($downloadArtifacts | ForEach-Object { Join-Path $workingDirectory $_.TargetFolder })
    }
    foreach ($importPath in $importPaths) {
        Import-Artifacts `
            -Path $importPath `
            -NavServiceName 'MicrosoftDynamicsNavServer$BC' `
            -ServerInstance BC `
            -Scope $DeployScope `
            -SyncMode $SyncMode `
            -ErrorAction Stop `
            -SkipServiceRestartCheck `
            -PublicDnsName $PublicDnsName `
            -ContainerId $ContainerId `
            -ContainerUser $ContainerUser `
            -ContainerPassword $ContainerPassword
    }

    Write-Host 'Artifact import finished'
}
finally {
    $env:nuGetFeedSelectMode = $previousNuGetFeedSelectMode
    Write-Host '[Deploy] Cleaning up deployment files'
    if (Test-Path -LiteralPath $workingDirectory) {
        try {
            Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not clean up deployment files in '$workingDirectory': $($_.Exception.Message)"
        }
    }
    if (-not $KeepUploadedFiles) {
        foreach ($artifact in $artifacts) {
            if ($artifact.Type -eq 'source' -and $artifact.Source -and $artifact.Source -notmatch '^https?://' -and
                (Test-Path -LiteralPath $artifact.Source -PathType Leaf)) {
                Remove-Item -LiteralPath $artifact.Source -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Remove-Item -LiteralPath $ArtifactsPath -Force -ErrorAction SilentlyContinue
}