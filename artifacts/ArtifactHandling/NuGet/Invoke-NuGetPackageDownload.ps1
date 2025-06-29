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
        [Version]$PlatformVersion,
        [PSCustomObject[]]$PredefinedPackages = @()
    )

    begin {
        $namePattern = '^(?<publisher>[^\.]+)\.(?<name>[^\.]+)(?:\.(?<country>[^\.][^\.]))?(?:\.(?<symbols>symbols))?(?:\.(?<id>[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12}))?$' # <publisher>.<name>[.<country>][.<symbols>][.<id>]

        $versionStablePattern     = '\d+(?:\.\d+){0,3}'     # <major>[.<minor>[.<patch>[.<revision>]]]
        $versionPrereleasePattern = '(?:-[0-9A-Za-z.-]+)?'  # [-<prerelease>]
        $versionMetadataPattern   = '(?:\+[0-9A-Za-z.-]+)?' # [+<metadata>]

        $versionPattern       = '^\s*(?<version>{0})(?<prerelease>{1})(?<metadata>{2})\s*$' -f $versionStablePattern, $versionPrereleasePattern, $versionMetadataPattern # <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>][+<metadata>]
        $versionRangePattern  = '^\s*[\[\(]?\s*({0}{1})(,{0}{1})?\s*[\]\)]?\s*$' -f $versionStablePattern, $versionPrereleasePattern # [[(] <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] [, <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>]] [)]]
    }

    process {
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

            if ($InstalledAppsPath -and (Test-Path -Path $InstalledAppsPath)) {
                Get-ChildItem -Path $InstalledAppsPath -Filter '*.app' -Recurse |
                    ForEach-Object { Get-NavAppInfo -Path $_.FullName } |
                    ForEach-Object {
                        $installedApp = [PSCustomObject]@{
                            Package   = '{0}.{1}.{2}' -f $_.Publisher, $_.Name, $_.AppId -replace ' '
                            Name      = $_.Name
                            Publisher = $_.Publisher
                            Id        = $_.AppId
                            Version   = $_.Version
                        }

                        Write-Host "Use app file as installed app: $($installedApp.Package) (version: $($installedApp.Version))"
                        $downloadParameters.installedApps += $installedApp
                    }
            }

            foreach ($predefinedPackage in $PredefinedPackages) {
                # Ignore predefined package if it matches the requrested package
                if ($predefinedPackage.Package -eq $Package) {
                    continue
                }

                # Ignore predefined package if not matches the name pattern
                if ($predefinedPackage.Package -notmatch $namePattern) {
                    continue
                }

                # Ignore predefined package if name does not contain the id
                if (! $matches.id) {
                    continue
                }

                # Ignore predefined package if it matches an installed app
                if ($downloadParameters.installedApps | Where-Object { $_.Id.ToString() -eq $matches.id; Write-Host "Check: $($_.Id.ToString()) -eq $($matches.id) = $($_.Id.ToString() -eq $matches.id)" }) {
                    continue
                }

                # Use predefined package as installed app
                $installedApp = [PSCustomObject]@{
                    Package   = $predefinedPackage.Package
                    Name      = $matches.name
                    Publisher = $matches.publisher
                    Id        = $matches.id
                    Version   = $null
                }

                # Normalize version to 4 segements and use maximum for missing parts
                if (! $predefinedPackage.Version) {
                    $versionParts = ( @([int32]::MaxValue) * 3 ) + ( [int32]::MaxValue - 1 ) 
                    $installedApp.Version = $versionParts[0..3] -join '.'
                } elseif ($predefinedPackage.Version -match $versionPattern) {
                    $versionParts = $matches.version.Split('.') + ( @([int]::MaxValue) * 3 )
                    $installedApp.Version = '{0}{1}{2}' -f ($versionParts[0..3] -join '.'), $matches.prerelease, $matches.metadata
                }

                # Ignore predefined package if it has no valid version (e.g. version range)
                if (! $installedApp.Version) {
                    continue
                }

                Write-Host "Use predefined package as installed app: $($installedApp.Package) (version: $($installedApp.Version)))"
                $downloadParameters.installedApps += $installedApp
            }

            New-Item -ItemType Directory -Path $Destination -ErrorAction SilentlyContinue -Force | Out-Null
            Download-BcNuGetPackageToFolder @downloadParameters
        } finally {
            if ($nuGetPackageDownloadLockFileStream) {
                $nuGetPackageDownloadLockFileStream.Close()
            }
        }
    }
}
Export-ModuleMember -Function Invoke-NuGetPackageDownload