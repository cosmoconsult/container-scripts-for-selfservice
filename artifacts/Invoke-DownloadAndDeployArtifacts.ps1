[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('nuget', 'app', 'zip')]
    [string]$Type,
    [string]$Name = '',
    [string]$Version = '',
    [string]$ArtifactPath = '',
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
$maximumArchiveEntries = 1000
$maximumExtractedSize = 1GB
$workingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())

function Expand-ArtifactArchive {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ArchivePath)
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

    Expand-Archive -LiteralPath $ArchivePath -DestinationPath $DestinationPath -Force
}

try {
    New-Item -Path $workingDirectory -ItemType Directory -Force | Out-Null
    $artifactDirectory = $workingDirectory
    Write-Host "[Deploy] Preparing $Type deployment with scope '$DeployScope'"

    switch ($Type) {
        'nuget' {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                throw 'Name is required for NuGet deployments'
            }

            Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force
            . 'C:\run\my\ExtendedEnvironment.ps1'
            Write-Host "[Deploy] Downloading NuGet package '$Name' version '$Version'"
            try {
                Install-NuGetTools
                Initialize-NuGetFeeds
            }
            catch {
                Write-Host "[Deploy] NuGet feed initialization warning: $($_.Exception.Message)"
            }
            if ($ConsiderInstalledApps) {
                $installedAppsInfo = @(Get-NAVAppInfo -ServerInstance BC -Tenant default -TenantSpecificProperties -ErrorAction Stop |
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
            $downloadParameters = @{
                Name        = $Name
                Version     = $Version
                Type        = 'nuget'
                Destination = $workingDirectory
            }
            if ($ConsiderInstalledApps) {
                $downloadParameters.InstalledAppsInfo = $installedAppsInfo
            }
            if ($NuGetSelectMode) {
                $downloadParameters.NuGetSelectMode = $NuGetSelectMode
            }
            Invoke-DownloadArtifact @downloadParameters
        }
        'app' {
            if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
                throw "Artifact '$ArtifactPath' does not exist"
            }

            $extension = [System.IO.Path]::GetExtension($ArtifactPath).ToLowerInvariant()
            if ($extension -ne '.app') {
                throw "Artifact '$ArtifactPath' does not match type '$Type'"
            }
            Write-Host '[Deploy] Copying staged artifact'
            Copy-Item -LiteralPath $ArtifactPath -Destination (Join-Path $workingDirectory ([System.IO.Path]::GetFileName($ArtifactPath))) -ErrorAction Stop
        }
        'zip' {
            if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
                throw "ZIP artifact '$ArtifactPath' does not exist"
            }

            $archivePath = Join-Path $workingDirectory 'artifact.zip'
            $artifactDirectory = Join-Path $workingDirectory 'artifacts'
            Write-Host '[Deploy] Validating and extracting staged ZIP artifact'
            Copy-Item -LiteralPath $ArtifactPath -Destination $archivePath -ErrorAction Stop
            Expand-ArtifactArchive -ArchivePath $archivePath -DestinationPath $artifactDirectory
        }
    }

    $devParameters = @{}
    if ($DeployScope -eq 'Dev') {
        $devParameters = @{
            PublicDnsName = $PublicDnsName
            ContainerId = $ContainerId
            ContainerUser = $ContainerUser
            ContainerPassword = $ContainerPassword
        }
    }

    Write-Host "[Deploy] Importing artifacts with scope '$DeployScope' and sync mode '$SyncMode'"
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop
    Import-Artifacts `
        -Path $artifactDirectory `
        -NavServiceName 'MicrosoftDynamicsNavServer$BC' `
        -ServerInstance BC `
        -Scope $DeployScope `
        -SyncMode $SyncMode `
        -throwErrors $true `
        @devParameters

    Write-Host 'Artifact import finished'
}
catch {
    Write-Host "Artifact deployment failed: $($_.Exception.Message)"
    throw
}
finally {
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