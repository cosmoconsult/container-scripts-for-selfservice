$script:nuGetPackageDownloadLockFile = Join-Path ([system.IO.Path]::GetTempPath()) "nugetPackageDownload.lock"

function Invoke-NuGetPackageDownload() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Destination,
        [Parameter(Mandatory)]
        [string]$Package,
        [string]$Version,
        [string]$InstalledAppsPath,
        [string]$ServiceTierFolder,
        [Version]$PlatformVersion
    )

    try {
        Write-Host "Waiting for other NuGet Package downloads..."
        while (! $nuGetPackageDownloadLockFileStream) {
            try { $nuGetPackageDownloadLockFileStream = [System.IO.File]::Open($script:nuGetPackageDownloadLockFile, 'OpenOrCreate', 'ReadWrite', 'None') }
            catch { Start-Sleep -Milliseconds 250 }
        }

        if (! $PSBoundParameters.ContainsKey("ServiceTierFolder")) {
            $ServiceTierFolder = Get-NAVServiceTierFolder
        }

        if (! $PSBoundParameters.ContainsKey("PlatformVersion")) {
            $PlatformVersion = [Version](Get-Item (Join-Path $ServiceTierFolder "Microsoft.Dynamics.Nav.Server.exe")).VersionInfo.FileVersion
        }

        Import-NAVModules -ServiceTierFolder $ServiceTierFolder -ExcludeRoleTailoredClient
        Import-NugetTools

        $downloadParameters = @{
            packageName          = $Package
            folder               = $Destination
            installedPlatform    = $PlatformVersion
            installedApps        = @()
            select               = 'LatestMatching'
            downloadDependencies = 'allButMicrosoft'
        }
        
        if ($Version) {
            $stableVersionPattern = '\d+(?:\.\d+){0,3}'     # <major>[.<minor>[.<patch>[.<revision>]]]
            $prereleasePattern    = '(?:-[0-9A-Za-z.-]+)?'  # [-<prerelease>]
            $metadataPattern      = '(?:\+[0-9A-Za-z.-]+)?' # [+<metadata>]

            $versionPattern       = '^\s*(?<version>{0})(?<prerelease>{1})(?<metadata>{2})\s*$' -f $stableVersionPattern, $prereleasePattern, $metadataPattern # <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>][+<metadata>]
            $versionRangePattern  = '^\s*[\[\(]\s*?({0}{1})(,{0}{1})?\s*[\]\)]?\s*$' -f $stableVersionPattern, $prereleasePattern # [[(] <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] [, <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>]] [)]]

            if ($Version -match $versionPattern) {
                # Convert NuGet version to a range (from version, to excl. version + 1)
                $fromVersion  = '{0}{1}' -f $matches.version, $matches.prerelease
                $toVersion    = '{0}{1}' -f ( $matches.version -replace '\d+$', ( [int]$matches.version.Split('.')[-1] + 1 ) ), $matches.prerelease
                $versionRange = '[{0},{1})' -f $fromVersion, $toVersion
                Write-Host "Converted version '$Version' to NuGet version range '$versionRange'"
            } else {
                $versionRange = $Version
            }

            # Validate NuGet version range (error if parsing fails)
            Write-Host "Validating NuGet version range '$versionRange'"
            # $versionRange = ( [NuGet.Versioning.VersionRange]$versionRange ).OriginalString
            if ($versionRange -notmatch $versionRangePattern) {
                throw "Invalid NuGet version range '$versionRange'"
            }

            $downloadParameters.version = $versionRange -replace '\s+'
        }

        Write-Host "Installed Apps Path: $InstalledAppsPath"
        if ($InstalledAppsPath -and (Test-Path -Path $InstalledAppsPath)) {
            Get-ChildItem -Path $InstalledAppsPath -Filter '*.app' -Recurse |
                ForEach-Object { Get-NavAppInfo -Path $_.FullName } |
                ForEach-Object {
                    $downloadParameters.installedApps += [PSCustomObject]@{
                        Name      = $_.Name
                        Publisher = $_.Publisher
                        id        = $_.AppId
                        Version   = $_.version
                    }
                }
        }

        New-Item -ItemType Directory -Path $Destination -ErrorAction SilentlyContinue -Force | Out-Null
        Download-BcNuGetPackageToFolder @downloadParameters
    } finally {
        if ($nuGetPackageDownloadLockFileStream) {
            $nuGetPackageDownloadLockFileStream.Close()
        }
    }
}
Export-ModuleMember -Function Invoke-NuGetPackageDownload