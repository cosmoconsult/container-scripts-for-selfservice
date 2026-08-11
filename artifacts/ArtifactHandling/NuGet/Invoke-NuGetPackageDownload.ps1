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
        [PSCustomObject[]]$PredefinedPackages = @(),
        [ValidateRange(0, [int]::MaxValue)]
        [int]$Retries = 0,
        [ValidateSet('Earliest', 'EarliestMatching', 'Latest', 'LatestMatching', 'Exact', 'Any')]
        [string]$Select = $( Get-NuGetFeedSelectMode )
    )

    $maxAttempts = $Retries + 1
    try {
        Write-Host "Waiting for other NuGet Package downloads..."
        while (! $nuGetPackageDownloadLockFileStream) {
            try { $nuGetPackageDownloadLockFileStream = [System.IO.File]::Open($script:nuGetPackageDownloadLockFile, 'OpenOrCreate', 'ReadWrite', 'None') }
            catch { Start-Sleep -Milliseconds 250 }
        }

        if (! $PSBoundParameters.ContainsKey("ServiceTierFolder")) {
            $ServiceTierFolder = Get-NAVServiceTierFolder
        }

        Import-NuGetTools

        $downloadParameters = @{
            packageName          = $Package
            folder               = $Destination
            installedApps        = @()
            select               = $Select
            downloadDependencies = 'allButMicrosoft'
        }
        $installedAppsHash = @{}       

        $systemApplicationId = '63ca2fa4-4f03-4f2b-a480-172fef340d3f'
        $applicationId = 'c1335042-3002-4257-bf8a-75c898ccb1b8'
        if (! (Test-Path variable:script:applicationPlatformAppInfos)) {
            Write-Host "Detecting Platform and Application version from Microsoft app files"
            $microsoftAppFilesPath = if (Test-Path -Path 'C:\Extensions') { 'C:\Extensions' } else { 'C:\Applications' }
            $script:applicationPlatformAppInfos = @(Get-NuGetAppInfos -AppFilesPath $microsoftAppFilesPath -ServiceTierFolder $ServiceTierFolder -AppIds @($systemApplicationId, $applicationId))
        }
        $applicationPlatformAppInfos = $script:applicationPlatformAppInfos

        $systemApplicationAppInfo = $applicationPlatformAppInfos | Where-Object { $_.Id.ToString() -eq $systemApplicationId } | Select-Object -First 1
        if ($systemApplicationAppInfo) {
            $platformVersion = [Version]$systemApplicationAppInfo.Version
            Write-Host "Detected Platform version '$platformVersion' from Microsoft System Application app file"
        }
        else {
            $platformVersion = [Version](Get-Item (Join-Path $ServiceTierFolder "Microsoft.Dynamics.Nav.Server.exe")).VersionInfo.FileVersion
            Write-Host "Detected Platform version '$platformVersion' from Microsoft.Dynamics.Nav.Server.exe"
        }
        $downloadParameters.installedPlatform = $platformVersion
            
        $applicationAppInfo = $applicationPlatformAppInfos | Where-Object { $_.Id.ToString() -eq $applicationId } | Select-Object -First 1
        if ($applicationAppInfo) {
            Write-Host "Add $($applicationAppInfo.Publisher) $($applicationAppInfo.Name) with version '$($applicationAppInfo.Version)' as installed app"
            $installedAppsHash[$applicationAppInfo.Id] = $applicationAppInfo
        }

        if (($Select -eq 'Exact') -or $Version) {
            $downloadParameters.version = ConvertTo-NuGetVersionConstraint -Version $Version -Select $Select -ErrorContext "package '$Package'"
            Write-Host "Use NuGet version constraint '$($downloadParameters.version)' for select mode '$Select'"
        }

        if ($InstalledAppsPath -and (Test-Path -Path $InstalledAppsPath)) {
            Write-Host "Collecting app files from '$InstalledAppsPath'"
            $installedAppInfos = @(Get-NuGetAppInfos -AppFilesPath $InstalledAppsPath -ServiceTierFolder $ServiceTierFolder)

            if ($installedAppInfos) {
                Write-Host "Collecting apps infos from app files (only highest version per app id)"
                foreach ($appInfo in $installedAppInfos) {
                    if ($installedAppsHash.ContainsKey($appInfo.Id)) {
                        if ([Version]$appInfo.Version -gt [Version]$installedAppsHash[$appInfo.Id].Version) {
                            $installedAppsHash[$appInfo.Id] = $appInfo
                        }
                    }
                    else {
                        $installedAppsHash[$appInfo.Id] = $appInfo
                    }
                }
                $installedApps = $installedAppsHash.Values

                foreach ($installedApp in $installedApps) {
                    Write-Host "Use app file as installed app: $($installedApp.Package) (version: $($installedApp.Version))"
                }
            }
        }
        $downloadParameters.installedApps = @($installedAppsHash.Values)

        foreach ($predefinedPackage in $PredefinedPackages) {
            # Ignore predefined package if it matches the requested package
            if ($predefinedPackage.Package -eq $Package) {
                continue
            }

            $packageNameInfo = Get-NuGetPackageNameInfo -Package $predefinedPackage.Package

            # Ignore predefined package if name does not contain the id
            if (! $packageNameInfo.Id) {
                continue
            }

            # Ignore predefined package if it matches an installed app
            if ($downloadParameters.installedApps | Where-Object { $_.Id.ToString() -eq $packageNameInfo.Id }) {
                continue
            }

            # Determine highest possible version of predefined package
            $packageVersion = ConvertTo-NuGetMaximumVersion -Version $predefinedPackage.Version -ErrorContext "predefined package '$($predefinedPackage.Package)'"

            # Ignore predefined package if no version could be determined (e.g. version range)
            if (! $packageVersion) {
                continue
            }

            # Create installed app object from predefined package
            $installedApp = [PSCustomObject]@{
                Package   = $predefinedPackage.Package
                Name      = $packageNameInfo.Name
                Publisher = $packageNameInfo.Publisher
                Id        = $packageNameInfo.Id
                Version   = $packageVersion
            }

            Write-Host "Use predefined package as installed app: $($installedApp.Package) (version: $($installedApp.Version))"
            $downloadParameters.installedApps += $installedApp
        }

        New-Item -ItemType Directory -Path $Destination -ErrorAction SilentlyContinue -Force | Out-Null
        foreach ($attempt in 1..$maxAttempts) {
            try {
                Write-Verbose -Message "Download NuGet package $Package (attempt $attempt of $maxAttempts)"
                Download-BcNuGetPackageToFolder @downloadParameters
                break
            }
            catch {
                if ($attempt -ge $maxAttempts) {
                    throw
                }

                Write-Warning "Download NuGet package $Package failed (attempt $attempt of $maxAttempts): $($_.Exception.Message)"
                $waitSeconds = [Math]::Pow(2, $attempt - 1)
                Write-Host "Retrying after $waitSeconds second(s)..."
                Start-Sleep -Seconds $waitSeconds
            }
        }
    }
    finally {
        if ($nuGetPackageDownloadLockFileStream) {
            $nuGetPackageDownloadLockFileStream.Close()
        }
    }
}
Export-ModuleMember -Function Invoke-NuGetPackageDownload