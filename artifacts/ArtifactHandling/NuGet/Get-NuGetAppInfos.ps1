function Get-NuGetAppInfos {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$AppFilesPath,
        [string[]]$AppIds = @()
    )

    if (! (Test-Path -Path $AppFilesPath)) {
        return @()
    }

    $appInfoManifestPath = Join-Path $AppFilesPath 'AppInfo.Financials.json'
    if ($AppIds -and (Test-Path -Path $appInfoManifestPath -PathType Leaf)) {
        try {
            $appInfoManifest = @(Get-Content -Path $appInfoManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop)
        } catch {
            Write-Warning "Unable to read app info manifest '$appInfoManifestPath': $($_.Exception.Message)"
            return @()
        }

        $appFiles = @($appInfoManifest |
            Where-Object { $_.id -in $AppIds } |
            ForEach-Object { Join-Path $AppFilesPath $_.path } |
            Where-Object { Test-Path -Path $_ -PathType Leaf } |
            Get-Item)
        Write-Host "Found $($appFiles.Count) matching app files in '$appInfoManifestPath'"
    } else {
        $appFiles = @(Get-ChildItem -Path $AppFilesPath -Filter '*.app' -Recurse)
    }
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