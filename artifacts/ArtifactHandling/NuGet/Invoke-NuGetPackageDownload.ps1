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
                    # Increment the last version part to create upper bound
                    $versionParts = $matches.version.Split('.')
                    $toVersionParts = $versionParts.Clone()
                    $toVersionParts[-1] = [string]([int]$toVersionParts[-1] + 1)
                    
                    # Normalize both from and to versions to ensure at least major.minor format for System.Version compatibility
                    $fromVersionNormalized = if ($versionParts.Count -eq 1) { "{0}.0" -f $versionParts[0] } else { $matches.version }
                    $toVersionNormalized = if ($toVersionParts.Count -eq 1) { "{0}.0" -f $toVersionParts[0] } else { $toVersionParts -join '.' }
                    
                    $fromVersion  = '{0}{1}' -f $fromVersionNormalized, $matches.prerelease
                    $toVersion    = '{0}{1}' -f $toVersionNormalized, $matches.prerelease
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
                # Ignore predefined package if it matches the requested package
                if ($predefinedPackage.Package -eq $Package) {
                    continue
                }

                # Ignore predefined package if not matches the name pattern
                if (! ($predefinedPackage.Package -match $namePattern)) {
                    continue
                }

                $packageNameMatches = $matches

                # Ignore predefined package if name does not contain the id
                if (! $packageNameMatches.id) {
                    continue
                }

                # Ignore predefined package if it matches an installed app
                if ($downloadParameters.installedApps | Where-Object { $_.Id.ToString() -eq $packageNameMatches.id }) {
                    continue
                }

                # Determine highest possible version of predefined package
                $packageVersion = $null
                if (! $predefinedPackage.Version) {
                    $versionParts = @([int32]::MaxValue, [int32]::MaxValue, [int32]::MaxValue, ([int32]::MaxValue - 1))
                    $packageVersion = $versionParts[0..3] -join '.'
                } elseif ($predefinedPackage.Version -match $versionPattern) {
                    $versionMatches = $matches
                    $versionParts = $versionMatches.version.Split('.') + @([int32]::MaxValue, [int32]::MaxValue, [int32]::MaxValue)
                    $packageVersion = '{0}{1}{2}' -f ($versionParts[0..3] -join '.'), $versionMatches.prerelease, $versionMatches.metadata
                }

                # Ignore predefined package if no version could be determined (e.g. version range)
                if (! $packageVersion) {
                    continue
                }

                # Create installed app object from predefined package
                $installedApp = [PSCustomObject]@{
                    Package   = $predefinedPackage.Package
                    Name      = $packageNameMatches.name
                    Publisher = $packageNameMatches.publisher
                    Id        = $packageNameMatches.id
                    Version   = $packageVersion
                }

                Write-Host "Use predefined package as installed app: $($installedApp.Package) (version: $($installedApp.Version))"
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