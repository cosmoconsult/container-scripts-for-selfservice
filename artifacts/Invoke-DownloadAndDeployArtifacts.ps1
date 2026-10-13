[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('nuget', 'app', 'fob', 'rapidstart', 'font', 'zip')]
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
    [string]$ContainerPassword = '',
    [bool]$SkipVerification = $true,
    [string]$ServerInstance = 'BC',
    [string]$Tenant = 'default',
    [string]$NavServiceName = 'MicrosoftDynamicsNavServer$BC',
    [string]$DatabaseServer = 'localhost\sqlexpress'
)

C:\run\prompt.ps1 -silent

$ErrorActionPreference = 'Stop'
$maximumArchiveEntries = 1000
$maximumExtractedSize = 1GB
$workingDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
$fontExtensions = @('.fon', '.fnt', '.ttf', '.ttc', '.otf')
$supportedExtensions = @('.app', '.fob', '.rapidstart') + $fontExtensions

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
                $installedAppsInfo = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties -ErrorAction Stop |
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
        { $_ -in @('app', 'fob', 'rapidstart', 'font') } {
            if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
                throw "Artifact '$ArtifactPath' does not exist"
            }

            $extension = [System.IO.Path]::GetExtension($ArtifactPath).ToLowerInvariant()
            if (($Type -eq 'font' -and $extension -notin $fontExtensions) -or
                ($Type -ne 'font' -and $extension -ne ".$Type")) {
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

    $artifactFiles = @(Get-ChildItem -LiteralPath $artifactDirectory -Recurse -File -ErrorAction Stop |
        Where-Object { $_.Extension.ToLowerInvariant() -in $supportedExtensions })
    if ($artifactFiles.Count -eq 0) {
        throw "No supported artifacts found for $Type deployment"
    }
    if ($DeployScope -eq 'Dev' -and @($artifactFiles | Where-Object { $_.Extension -ne '.app' }).Count -gt 0) {
        throw 'Dev scope supports only .app artifacts; use Global or Tenant for other artifact types'
    }
    $fontDirectory = Join-Path $workingDirectory 'fonts'
    $fontFiles = @($artifactFiles | Where-Object { $_.Extension.ToLowerInvariant() -in $fontExtensions })
    if ($fontFiles.Count -gt 0) {
        New-Item -Path $fontDirectory -ItemType Directory -Force | Out-Null
        foreach ($fontFile in $fontFiles) {
            $fontDestination = Join-Path $fontDirectory $fontFile.Name
            if (Test-Path -LiteralPath $fontDestination) {
                throw "Duplicate font filename '$($fontFile.Name)' in artifact package"
            }
            Copy-Item -LiteralPath $fontFile.FullName -Destination $fontDestination -ErrorAction Stop
        }
    }

    $appFiles = @($artifactFiles | Where-Object { $_.Extension -eq '.app' })
    Write-Host "[Deploy] Found $($artifactFiles.Count) artifact(s); starting import with sync mode '$SyncMode'"
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop
    Import-Artifacts `
        -Path $artifactDirectory `
        -NavServiceName $NavServiceName `
        -ServerInstance $ServerInstance `
        -Tenant $Tenant `
        -DatabaseServer $DatabaseServer `
        -FontPath $fontDirectory `
        -Scope $DeployScope `
        -SyncMode $SyncMode `
        -ExcludeApps $false `
        -UseArtifactImportSettings $false `
        -Depth ([int]::MaxValue) `
        -throwErrors $true `
        -SkipVerification $SkipVerification `
        -SkipServiceRestartCheck `
        -PublicDnsName $PublicDnsName `
        -ContainerId $ContainerId `
        -ContainerUser $ContainerUser `
        -ContainerPassword $ContainerPassword

    if ($DeployScope -ne 'Dev' -and $appFiles.Count -gt 0) {
        Write-Host '[Deploy] Verifying installed app state'
        foreach ($appFile in $appFiles) {
            $packageApp = Get-NAVAppInfo -Path $appFile.FullName
            $installedApps = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Id $packageApp.AppId -Tenant $Tenant -TenantSpecificProperties -ErrorAction Stop |
                Where-Object { $_.IsInstalled -and [System.Version]$_.Version -ge [System.Version]$packageApp.Version } |
                Sort-Object { [System.Version]$_.Version } -Descending)
            if (-not $installedApps[0]) {
                throw "App '$($packageApp.Name)' version $($packageApp.Version) is not installed for tenant '$Tenant'"
            }
            if ($installedApps[0].SyncState -ne 'Synced' -or $installedApps[0].NeedsUpgrade -or
                ($installedApps[0].ExtensionDataVersion -and [System.Version]$installedApps[0].ExtensionDataVersion -lt [System.Version]$installedApps[0].Version)) {
                throw "App '$($packageApp.Name)' has an incomplete synchronization or data upgrade for tenant '$Tenant'"
            }
        }
    }

    Write-Host 'Artifact deployment completed successfully'
}
catch {
    Write-Host "Artifact deployment failed: $($_.Exception.Message)"
    throw
}
finally {
    Write-Host '[Deploy] Cleaning up deployment files'
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue
}