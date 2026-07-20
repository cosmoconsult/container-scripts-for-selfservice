function Get-NuGetAppInfos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppFilesPath
    )

    if (! (Test-Path -Path $AppFilesPath)) {
        return @()
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

    $appInfos = foreach ($appFile in $appFiles) {
        $appInfoCacheKey = $appFile.FullName
        if ($appInfosCache.ContainsKey($appInfoCacheKey)) {
            $appInfo = $appInfosCache[$appInfoCacheKey]
        } else {
            $appInfoObj = Get-NAVAppInfo -Path $appFile.FullName
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

        [PSCustomObject]@{
            Package   = $appInfo.Package
            Name      = $appInfo.Name
            Publisher = $appInfo.Publisher
            Id        = $appInfo.Id
            Version   = $appInfo.Version
            Path      = $appFile.FullName
        }
    }

    if ($appInfosCacheUpdated) {
        Write-Host "Caching app infos to '$appInfosCachePath'"
        $appInfosCache | ConvertTo-Json -Depth 10 -Compress | Set-Content -Path $appInfosCachePath
    }

    return @($appInfos)
}