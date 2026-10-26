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

function Test-DeploymentArtifact {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if ([System.IO.Path]::GetExtension($Path) -ine '.zip') {
        return
    }

    $maximumArchiveEntries = 1000
    $maximumExtractedSize = 1GB
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        if ($archive.Entries.Count -gt $maximumArchiveEntries) {
            throw "ZIP contains more than $maximumArchiveEntries entries"
        }

        [long]$expandedSize = 0
        $destinationRoot = [System.IO.Path]::GetFullPath($DestinationPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
        foreach ($entry in $archive.Entries) {
            $expandedSize += $entry.Length
            if ($expandedSize -gt $maximumExtractedSize) {
                throw "ZIP expands beyond the $maximumExtractedSize byte limit"
            }

            $entryPath = [System.IO.Path]::GetFullPath((Join-Path $DestinationPath $entry.FullName))
            if (-not $entryPath.StartsWith($destinationRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "ZIP entry '$($entry.FullName)' is outside the destination directory"
            }
        }
    }
    finally {
        $archive.Dispose()
    }
}

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
        if ($artifactType -eq 'nuget') {
            if ([string]::IsNullOrWhiteSpace($artifact.Name)) {
                throw 'Name is required for NuGet deployments'
            }
            [PSCustomObject]@{ Type = $artifactType; Name = $artifact.Name; Version = $artifact.Version; Url = '' }
        }
        else {
            $sourceUrl = [string]$artifact.Source
            if ([string]::IsNullOrWhiteSpace($sourceUrl)) {
                throw 'Source is required for URL or local path deployments'
            }
            if ($sourceUrl -notmatch '^https?://') {
                $sourceUrl = (Get-Item -LiteralPath $sourceUrl -ErrorAction Stop).FullName
            }
            [PSCustomObject]@{ Type = $artifactType; Name = 'artifact'; Url = $sourceUrl }
        }
    })

    $downloadParameters = @{
        Destination = $workingDirectory
        AllArtifacts = $downloadArtifacts
        SkipServiceRestartCheck = $true
        ThrowOnError = $true
        ValidateArtifact = ${function:Test-DeploymentArtifact}
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

    Get-ChildItem -LiteralPath $workingDirectory -Filter '*.app' -Recurse -File |
        ForEach-Object { Get-NAVAppInfo -Path $_.FullName -ErrorAction Stop | Out-Null }

    Write-Host "[Deploy] Importing artifacts with scope '$DeployScope' and sync mode '$SyncMode'"
    Import-Artifacts `
        -Path $workingDirectory `
        -NavServiceName 'MicrosoftDynamicsNavServer$BC' `
        -ServerInstance BC `
        -Scope $DeployScope `
        -SyncMode $SyncMode `
        -throwErrors $true `
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