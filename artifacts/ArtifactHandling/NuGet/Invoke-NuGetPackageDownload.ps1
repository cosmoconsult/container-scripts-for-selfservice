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
        [PSCustomObject[]]$PredefinedPackages = @(),
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Retries = 0,
        [ValidateSet('Earliest', 'EarliestMatching', 'Latest', 'LatestMatching', 'Exact', 'Any')]
        [string]$Select = $( if ($env:nuGetFeedSelectMode) { $env:nuGetFeedSelectMode } else { 'LatestMatching' } ),
    )

    begin {
        $namePattern = '^(?<publisher>[^\.]+)\.(?<name>[^\.]+)(?:\.(?<country>[^\.][^\.]))?(?:\.(?<symbols>symbols))?(?:\.(?<id>[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12}))?$' # <publisher>.<name>[.<country>][.<symbols>][.<id>]

        $versionStablePattern     = '\d+(?:\.\d+){0,3}'     # <major>[.<minor>[.<patch>[.<revision>]]]
        $versionPrereleasePattern = '(?:-[0-9A-Za-z.-]+)?'  # [-<prerelease>]
        $versionMetadataPattern   = '(?:\+[0-9A-Za-z.-]+)?' # [+<metadata>]

        $versionPattern       = '^\s*(?<version>{0})(?<prerelease>{1})(?<metadata>{2})\s*$' -f $versionStablePattern, $versionPrereleasePattern, $versionMetadataPattern # <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>][+<metadata>]

        $versionRangeLowerVersionPattern = '(?<versionLower>{0})(?<prereleaseLower>{1})' -f $versionStablePattern, $versionPrereleasePattern # <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>][,]
        $versionRangeUpperVersionPattern = '(?<versionUpper>{0})(?<prereleaseUpper>{1})' -f $versionStablePattern, $versionPrereleasePattern # [,]<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>]
        $versionRangePatterns = @(
            '(?<rangeStart>\[)\s*{0}\s*(?<rangeEnd>\])' -f $versionRangeUpperVersionPattern # Exact -> <[> <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] <]>
            '(?<rangeStart>\[|\()\s*{0},{1}\s*(?<rangeEnd>\)|\])'   -f $versionRangeLowerVersionPattern, $versionRangeUpperVersionPattern # Range (both bounds) -> <[(> <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>,<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] <)]>
            '(?<rangeStart>\()\s*(?:{0})?,{1}\s*(?<rangeEnd>\)|\])' -f $versionRangeLowerVersionPattern, $versionRangeUpperVersionPattern # Range (upper bound) -> <(> [<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>],<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] <)]>
            '(?<rangeStart>\[|\()\s*{0},(?:{1})?\s*(?<rangeEnd>\))' -f $versionRangeLowerVersionPattern, $versionRangeUpperVersionPattern # Range (lower bound) -> <[(> <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>,[<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>]] <)>
        )
        $versionRangePattern  = '^\s*(?:{0})\s*$' -f ($versionRangePatterns -join '|')

        $appInfosCacheFileName = ".nuget.apps.cache.json"

        $maxAttempts = $Retries + 1
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
                select               = $Select
                downloadDependencies = 'allButMicrosoft'
            }

            if ($Version) {
                if ($Select -eq 'Exact') {
                    Write-Host "Use NuGet version '$Version' for select mode 'Exact'"

                    # Validate NuGet version (error if parsing fails)
                    Write-Host "Validate NuGet version '$Version'"
                    if ($Version -notmatch $versionPattern) {
                        throw "Invalid NuGet version '$Version'"
                    }

                    $downloadParameters.version = $Version -replace '\s+'
                } else {
                    if ($Version -match $versionPattern) {
                        Write-Host "Convert NuGet version '$Version' to NuGet version range for select mode '$Select'"

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

                        Write-Host "Use converted NuGet version range '$versionRange'"
                    } else {
                        Write-Host "Use NuGet version range '$Version' for select mode '$Select'"

                        $versionRange = $Version
                    }

                    # Validate NuGet version range (error if parsing fails)
                    Write-Host "Validate NuGet version range '$versionRange'"
                    if ($versionRange -notmatch $versionRangePattern) {
                        throw "Invalid NuGet version range '$versionRange'"
                    }

                    $downloadParameters.version = $versionRange -replace '\s+'
                }
            }

            if ($InstalledAppsPath -and (Test-Path -Path $InstalledAppsPath)) {
                Write-Host "Collecting app files from '$InstalledAppsPath'"
                $installedAppFiles = Get-ChildItem -Path $InstalledAppsPath -Filter '*.app' -Recurse
                Write-Host "Found $($installedAppFiles.Count) app files in '$InstalledAppsPath'"

                if ($installedAppFiles) {
                    $appInfosCache = @{}
                    $appInfosCacheUpdated = $false
                    $appInfosCachePath = Join-Path $InstalledAppsPath $appInfosCacheFileName
                    if (Test-Path $appInfosCachePath) {
                        Write-Host "Loading cached app infos from '$appInfosCachePath'"
                        $appInfosCacheObj = Get-Content $appInfosCachePath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if ($appInfosCacheObj) {
                            $appInfosCacheObj.PSObject.Properties | ForEach-Object { $appInfosCache[$_.Name] = $_.Value }
                        }
                    }

                    Write-Host "Collecting apps infos from app files (only highest version per app id)"
                    $installedAppsHash = @{}
                    foreach ($installedAppFile in $installedAppFiles) {
                        $appInfoCacheKey = $installedAppFile.FullName
                        if ($appInfosCache.ContainsKey($appInfoCacheKey)) {
                            $appInfo = $appInfosCache[$appInfoCacheKey]
                        } else {
                            $appInfoObj = Get-NavAppInfo -Path $installedAppFile.FullName
                            $appInfo = [PSCustomObject]@{
                                Package   = '{0}.{1}.{2}' -f $appInfoObj.Publisher, $appInfoObj.Name, $appInfoObj.AppId -replace ' '
                                Name      = [string] $appInfoObj.Name
                                Publisher = [string] $appInfoObj.Publisher
                                Id        = [string] $appInfoObj.AppId
                                Version   = [string] $appInfoObj.Version
                            }
                            $appInfosCache[$appInfoCacheKey] = $appInfo
                            $appInfosCacheUpdated = $true
                        }
                        if ($installedAppsHash.ContainsKey($appInfo.Id)) {
                            if ([Version]$appInfo.Version -gt [Version]$installedAppsHash[$appInfo.Id].Version) {
                                $installedAppsHash[$appInfo.Id] = $appInfo
                            }
                        } else {
                            $installedAppsHash[$appInfo.Id] = $appInfo
                        }
                    }
                    $installedApps = $installedAppsHash.Values

                    if ($appInfosCacheUpdated) {
                        Write-Host "Caching app infos to '$appInfosCachePath'"
                        $appInfosCache | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $appInfosCachePath
                    }

                    foreach ($installedApp in $installedApps) {
                        Write-Host "Use app file as installed app: $($installedApp.Package) (version: $($installedApp.Version))"
                    }
                    $downloadParameters.installedApps = @($installedApps)
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
                $versionParts = @([int32]::MaxValue, [int32]::MaxValue, [int32]::MaxValue, ([int32]::MaxValue - 1))
                if (! $predefinedPackage.Version) {
                    # If no version is specified, assume the highest possible version (e.g. <max>.<max>.<max>.<max - 1>)
                    $packageVersion = $versionParts[0..3] -join '.'
                } elseif ($predefinedPackage.Version -match $versionPattern) {
                    $versionMatches = $matches
                    # If a specific version is specified, use the upper limit of this version (e.g. 1.2 -> 1.2.<max>.<max>)
                    $versionParts = $versionMatches.version.Split('.') + $versionParts
                    $packageVersion = '{0}{1}{2}' -f ($versionParts[0..3] -join '.'), $versionMatches.prerelease, $versionMatches.metadata
                } elseif ($predefinedPackage.Version -match $versionRangePattern) {
                    $versionRangeMatches = $matches
                    # If a version range is specified, use the upper limit of this range
                    # If the upper limit is exclusive, get the highest possible previous version (e.g. 1.2 -> 1.1.<max>.<max>, 2.0 -> 1.<max>.<max>.<max>)
                    # If the upper limit is inclusive, use the upper limit version as-is (e.g. 1.2 -> 1.2.0.0)
                    # If no upper limit is specified, use the highest possible version (e.g. <max>.<max>.<max>.<max - 1>)
                    if ($versionRangeMatches.versionUpper) {
                        $versionMaxParts = @($versionRangeMatches.versionUpper -replace '(\.0+)+$', '' -split '\.')
                        if ($versionRangeMatches.rangeEnd -eq ')') {
                            # Exclusive upper limit
                            $versionMaxParts[-1] = [int]$versionMaxParts[-1] - 1
                            $versionParts = $versionMaxParts + $versionParts
                        } else {
                            # Inclusive upper limit
                            $versionParts = $versionMaxParts + @(0, 0, 0, 0)
                        }
                    }
                    $packageVersion = '{0}{1}' -f ($versionParts[0..3] -join '.'), $versionRangeMatches.prereleaseUpper
                } else {
                    # If the version is neither a specific version nor a version range, throw an error
                    throw "Invalid NuGet version or version range '$($predefinedPackage.Version)' for predefined package '$($predefinedPackage.Package)'"
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
            foreach($attempt in 1..$maxAttempts) {
                try {
                    Write-Verbose -Message "Download NuGet package $Package (attempt $attempt of $maxAttempts)"
                    Download-BcNuGetPackageToFolder @downloadParameters
                    break
                } catch {
                    if ($attempt -ge $maxAttempts) {
                        throw
                    }

                    Write-Warning "Download NuGet package $Package failed (attempt $attempt of $maxAttempts): $($_.Exception.Message)"
                    $waitSeconds = [Math]::Pow(2, $attempt - 1)
                    Write-Host "Retrying after $waitSeconds second(s)..."
                    Start-Sleep -Seconds $waitSeconds
                }
            }
        } finally {
            if ($nuGetPackageDownloadLockFileStream) {
                $nuGetPackageDownloadLockFileStream.Close()
            }
        }
    }
}
Export-ModuleMember -Function Invoke-NuGetPackageDownload