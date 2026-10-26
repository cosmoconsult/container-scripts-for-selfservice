[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [PSCustomObject[]]$Artifacts,
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

C:\run\prompt.ps1 -silent

$ErrorActionPreference = 'Stop'
$workingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$previousNuGetFeedSelectMode = $env:nuGetFeedSelectMode

try {
    if ($NuGetSelectMode) {
        $env:nuGetFeedSelectMode = $NuGetSelectMode
    }
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    Write-Host "[Deploy] Preparing artifact deployment with scope '$DeployScope'"
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop

    $downloadArtifacts = @(foreach ($artifact in $Artifacts) {
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
            $downloadParameters.InstalledPackages = @(Get-NAVAppInfo -ServerInstance BC -Tenant default -TenantSpecificProperties -ErrorAction Stop |
                Where-Object { $_.IsInstalled } |
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
    Import-Artifacts `
        -Path $workingDirectory `
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
}