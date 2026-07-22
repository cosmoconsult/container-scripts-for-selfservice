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
    
    $testAppFilePath = Join-Path $AppFilesPath 'Microsoft_Intrastat Core_28.0.46665.52773.app'
    if (Test-Path -Path $testAppFilePath -PathType Leaf) {
        Write-Host "Deleting file 'C:\Extensions\Microsoft_Intrastat Core_28.0.46665.52773.app' for testing purposes"
        Remove-Item -Path $testAppFilePath -Force
    }

    $appInfoFinancialsJsonPath = Join-Path $AppFilesPath 'AppInfo.Financials.json'
    if (Test-Path -Path $appInfoFinancialsJsonPath -PathType Leaf) {
        try {
            $appInfoFinancials = Get-Content -Path $appInfoFinancialsJsonPath -Raw | ConvertFrom-Json -ErrorAction Stop
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

    # only lookup specified appIds to avoid unnecessary processing of all app files
    $filterByAppIds = $AppIds.Count -gt 0
    $remainingAppIds = @{}
    $AppIds | ForEach-Object { $remainingAppIds[[string]$_] = $true }
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