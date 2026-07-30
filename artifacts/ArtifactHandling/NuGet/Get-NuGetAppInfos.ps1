function Get-NuGetAppInfos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppFilesPath,
        [string]$ServiceTierFolder,
        [string[]]$AppIds = @()
    )

    if (! (Test-Path -Path $AppFilesPath)) {
        return @()
    }

    # Prefer the image manifest because reading JSON is significantly faster than parsing app files
    $appInfoFinancialsJsonPath = Join-Path $AppFilesPath 'AppInfo.Financials.json'
    if (Test-Path -Path $appInfoFinancialsJsonPath -PathType Leaf) {
        try {
            $appInfoFinancials = Get-Content -Path $appInfoFinancialsJsonPath -Raw | ConvertFrom-Json -ErrorAction Stop
            # Normalize top-level arrays
            $appInfoFinancials = @($appInfoFinancials | ForEach-Object { $_ })
        } catch {
            Write-Warning "Unable to read app info manifest '$appInfoFinancialsJsonPath': $($_.Exception.Message)"
            return @()
        }

        $matchingAppInfoFinancials = @($appInfoFinancials | Where-Object { (! $AppIds) -or ($_.id -in $AppIds) })
        $appInfos = @($matchingAppInfoFinancials |
            ForEach-Object {
                $appInfo = $_
                $appFilePath = Join-Path $AppFilesPath $appInfo.path
                if (Test-Path -Path $appFilePath -PathType Leaf) {
                    [PSCustomObject]@{
                        Package   = '{0}.{1}.{2}' -f $appInfo.publisher, $appInfo.name, $appInfo.id -replace ' '
                        Name      = [string]$appInfo.name
                        Publisher = [string]$appInfo.publisher
                        Id        = [string]$appInfo.id
                        Version   = [string]$appInfo.version
                        Path      = [System.IO.Path]::GetFullPath($appFilePath)
                    }
                }
            })
        Write-Host "Found $($appInfos.Count) matching app files in '$AppFilesPath'"
        return $appInfos
    }

    $appFiles = @(Get-ChildItem -Path $AppFilesPath -Filter '*.app' -Recurse)
    Write-Host "Found $($appFiles.Count) app files in '$AppFilesPath'"
    if (! $appFiles) {
        return @()
    }

    $appInfosCache = @{}
    $appInfosCacheUpdated = $false
    $appInfosCachePath = Join-Path $AppFilesPath '.nuget.apps.cache.json'
    if (Test-Path -Path $appInfosCachePath) {
        Write-Host "Loading cached app infos from '$appInfosCachePath'"
        $appInfosCacheObj = Get-Content -Path $appInfosCachePath -Raw | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($appInfosCacheObj) {
            $appInfosCacheObj.PSObject.Properties | ForEach-Object { $appInfosCache[$_.Name] = $_.Value }
        }
    }

    # Get-NAVAppInfo is much faster in PowerShell Core, so batch the fallback scan there when called from PowerShell
    $pwshCoreAppInfoObjs = @{}
    if ($PSVersionTable.PSEdition -ne 'Core') {
        if (! $ServiceTierFolder) {
            $ServiceTierFolder = Get-NAVServiceTierFolder
        }

        $uncachedAppFile = $appFiles |
            Where-Object { ! $appInfosCache.ContainsKey($_.FullName) } |
            Select-Object -First 1
        if ($uncachedAppFile) {
            $pwshCoreScriptBlock = {
                param($AppFilesPath)

                C:\run\Prompt.ps1 -silent

                $appFiles = @(Get-ChildItem -Path $AppFilesPath -Filter '*.app' -Recurse)
                foreach ($appFile in $appFiles) {
                    $appInfoObj = Get-NAVAppInfo -Path $appFile.FullName
                    [PSCustomObject]@{
                        Path      = $appFile.FullName
                        Publisher = [string]$appInfoObj.Publisher
                        Name      = [string]$appInfoObj.Name
                        AppId     = [string]$appInfoObj.AppId
                        Version   = [string]$appInfoObj.Version
                    }
                }
            }

            $serverVersion = [Version](Get-Item (Join-Path $ServiceTierFolder "Microsoft.Dynamics.Nav.Server.exe")).VersionInfo.FileVersion
            $pwshCoreAppInfos = @(Invoke-CommandInPwshCore `
                -ScriptBlock $pwshCoreScriptBlock `
                -ArgumentList $AppFilesPath `
                -UseRemoteSession ($serverVersion.Major -lt 28)) # see /base/helper/PPIOverrides/public/NavAppManagement.ps1
            foreach ($appInfo in $pwshCoreAppInfos) {
                $pwshCoreAppInfoObjs[[string]$appInfo.Path] = $appInfo
            }
        }
    }

    # Only lookup specified appIds to avoid unnecessary processing of all app files
    $filterByAppIds = $AppIds.Count -gt 0
    $remainingAppIds = @{}
    $AppIds | ForEach-Object { $remainingAppIds[[string]$_] = $true }
    $appInfos = foreach ($appFile in $appFiles) {
        $appInfoCacheKey = $appFile.FullName
        if ($appInfosCache.ContainsKey($appInfoCacheKey)) {
            $appInfo = $appInfosCache[$appInfoCacheKey]
        } elseif ($pwshCoreAppInfoObjs.ContainsKey($appInfoCacheKey)) {
            $appInfoObj = $pwshCoreAppInfoObjs[$appInfoCacheKey]
        } else {
            $appInfoObj = Get-NAVAppInfo -Path $appFile.FullName
        }

        if (! $appInfosCache.ContainsKey($appInfoCacheKey)) {
            $appInfo = [PSCustomObject]@{
                Package   = '{0}.{1}.{2}' -f $appInfoObj.Publisher, $appInfoObj.Name, $appInfoObj.AppId -replace ' '
                Name      = [string]$appInfoObj.Name
                Publisher = [string]$appInfoObj.Publisher
                Id        = [string]$appInfoObj.AppId
                Version   = [string]$appInfoObj.Version
            }
            $appInfosCache[$appInfoCacheKey] = $appInfo
            $appInfosCacheUpdated = $true
        }

        if ($filterByAppIds -and ! $remainingAppIds.ContainsKey([string]$appInfo.Id)) {
            continue
        }

        [PSCustomObject]@{
            Package   = $appInfo.Package
            Name      = $appInfo.Name
            Publisher = $appInfo.Publisher
            Id        = $appInfo.Id
            Version   = $appInfo.Version
            Path      = $appFile.FullName
        }

        if ($filterByAppIds) {
            $remainingAppIds.Remove([string]$appInfo.Id)
            if ($remainingAppIds.Count -eq 0) {
                Write-Host "All specified app ids have been found, skipping remaining app files"
                break
            }
        }
    }

    if ($appInfosCacheUpdated) {
        Write-Host "Caching app infos to '$appInfosCachePath'"
        $appInfosCache | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $appInfosCachePath
    }

    return @($appInfos)
}