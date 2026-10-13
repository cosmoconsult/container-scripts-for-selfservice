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
    [string]$ContainerPassword = '',
    [bool]$SkipVerification = $true
)

C:\run\prompt.ps1 -silent

$maximumArchiveEntries = 1000
$maximumExtractedSize = 1GB
$workingDirectory = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())

function Expand-AppArchive {
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
    $appDirectory = $workingDirectory
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
                $installedAppsInfo = @(Get-NAVAppInfo -ServerInstance BC -Tenant default -TenantSpecificProperties -ErrorAction SilentlyContinue |
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
                throw "App artifact '$ArtifactPath' does not exist"
            }

            Write-Host '[Deploy] Copying staged app artifact'
            Copy-Item -LiteralPath $ArtifactPath -Destination (Join-Path $workingDirectory 'artifact.app') -ErrorAction Stop
        }
        'zip' {
            if (-not (Test-Path -LiteralPath $ArtifactPath -PathType Leaf)) {
                throw "ZIP artifact '$ArtifactPath' does not exist"
            }

            $archivePath = Join-Path $workingDirectory 'artifact.zip'
            $appDirectory = Join-Path $workingDirectory 'apps'
            Write-Host '[Deploy] Validating and extracting staged ZIP artifact'
            Copy-Item -LiteralPath $ArtifactPath -Destination $archivePath -ErrorAction Stop
            Expand-AppArchive -ArchivePath $archivePath -DestinationPath $appDirectory
        }
    }

    $appFiles = @(Get-ChildItem -LiteralPath $appDirectory -Filter '*.app' -Recurse -File)
    if ($appFiles.Count -eq 0) {
        throw "No .app files found for $Type deployment"
    }

    Write-Host "[Deploy] Found $($appFiles.Count) app(s); starting ordered deployment with sync mode '$SyncMode'"
    Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop
    Import-Artifacts `
        -Path $appDirectory `
        -NavServiceName 'BC' `
        -ServerInstance 'BC' `
        -Tenant 'default' `
        -Scope $DeployScope `
        -SyncMode $SyncMode `
        -AppsOnly `
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

    if ($DeployScope -ne 'Dev') {
        Write-Host '[Deploy] Verifying installed app state'
        foreach ($appFile in $appFiles) {
            $packageApp = Get-NAVAppInfo -Path $appFile.FullName
            $installedApps = @(Get-NAVAppInfo -ServerInstance BC -Id $packageApp.AppId -Tenant default -TenantSpecificProperties -ErrorAction SilentlyContinue |
                Where-Object { $_.IsInstalled -and [System.Version]$_.Version -ge [System.Version]$packageApp.Version } |
                Sort-Object { [System.Version]$_.Version } -Descending)
            if (-not $installedApps[0]) {
                throw "App '$($packageApp.Name)' version $($packageApp.Version) is not installed for tenant 'default'"
            }
            if ($installedApps[0].SyncState -ne 'Synced' -or $installedApps[0].NeedsUpgrade -or
                ($installedApps[0].ExtensionDataVersion -and [System.Version]$installedApps[0].ExtensionDataVersion -lt [System.Version]$installedApps[0].Version)) {
                throw "App '$($packageApp.Name)' has an incomplete synchronization or data upgrade for tenant 'default'"
            }
        }
    }

    Write-Host 'App deployment verified successfully'
}
catch {
    Write-Host "App deployment failed: $($_.Exception.Message)"
    throw
}
finally {
    Write-Host '[Deploy] Cleaning up deployment files'
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    if ($ArtifactPath) {
        Remove-Item -LiteralPath $ArtifactPath -Force -ErrorAction SilentlyContinue
    }
}