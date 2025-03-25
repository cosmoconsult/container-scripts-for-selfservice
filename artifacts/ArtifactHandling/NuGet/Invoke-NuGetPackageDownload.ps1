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
            select               = 'Latest'
            downloadDependencies = 'allButMicrosoft'
        }
        
        if ($Version) {
            $downloadParameters.version = $Version
        }

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

    }
}
Export-ModuleMember -Function Invoke-NuGetPackageDownload