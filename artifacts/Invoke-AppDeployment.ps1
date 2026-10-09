[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AppPath,
    [ValidateSet('Global', 'Tenant', 'Dev')]
    [string]$Scope = 'Tenant',
    [ValidateSet('Add', 'ForceSync')]
    [string]$SyncMode = 'Add',
    [string]$PublicDnsName = '',
    [string]$ContainerId = '',
    [string]$ContainerUser = '',
    [string]$ContainerPassword = ''
)

C:\run\prompt.ps1 -silent

$serverInstance = 'BC'
$tenant = 'default'

function Get-TenantAppInfo {
    param (
        [Parameter(Mandatory = $true)]
        [Guid]$AppId,
        [Version]$Version
    )

    $apps = @(Get-NAVAppInfo -ServerInstance $serverInstance -Id $AppId -Tenant $tenant -TenantSpecificProperties -ErrorAction SilentlyContinue)
    if ($Version) {
        return @($apps | Where-Object { [Version]$_.Version -eq $Version })[0]
    }

    return $apps
}

function Invoke-DevelopmentDeployment {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$PackageApp
    )

    if ([string]::IsNullOrWhiteSpace($PublicDnsName) -or [string]::IsNullOrWhiteSpace($ContainerId) -or
        [string]::IsNullOrWhiteSpace($ContainerUser) -or [string]::IsNullOrWhiteSpace($ContainerPassword)) {
        throw 'Dev deployment requires PublicDnsName, ContainerId, ContainerUser, and ContainerPassword'
    }

    $schemaUpdateMode = if ($SyncMode -eq 'ForceSync') { 'forcesync' } else { 'synchronize' }
    $endpoint = "https://$PublicDnsName/$($ContainerId)dev/dev/apps?SchemaUpdateMode=$schemaUpdateMode&tenant=$tenant"
    Write-Host "[AppDeployment] Publishing to the development endpoint with schema mode '$schemaUpdateMode'"

    Import-Module 'C:\run\helper\k8s-bc-helper.psd1'
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler = New-Object System.Net.Http.HttpClientHandler
    $client = [System.Net.Http.HttpClient]::new($handler)
    $fileStream = [System.IO.File]::OpenRead($Path)
    $content = [System.Net.Http.MultipartFormDataContent]::new()
    try {
        $credentials = [System.Text.Encoding]::ASCII.GetBytes("${ContainerUser}:$ContainerPassword")
        $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Basic', [Convert]::ToBase64String($credentials))
        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan

        $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
        $fileContent.Headers.ContentDisposition = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new('form-data')
        $fileContent.Headers.ContentDisposition.Name = [System.IO.Path]::GetFileName($Path)
        $fileContent.Headers.ContentDisposition.FileName = [System.IO.Path]::GetFileName($Path)
        $content.Add($fileContent)

        $response = $client.PostAsync($endpoint, $content).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            throw "Dev endpoint returned $([int]$response.StatusCode) ($($response.ReasonPhrase)): $responseBody"
        }
    }
    finally {
        $content.Dispose()
        $fileStream.Dispose()
        $client.Dispose()
        $handler.Dispose()
    }
}

try {
    if (-not (Test-Path -LiteralPath $AppPath -PathType Leaf)) {
        throw "App '$AppPath' does not exist"
    }

    $packageApp = Get-NAVAppInfo -Path $AppPath
    Write-Host "[AppDeployment] Deploying '$($packageApp.Name)' $($packageApp.Version) with scope '$Scope'"

    if ($Scope -eq 'Dev') {
        Invoke-DevelopmentDeployment -Path $AppPath -PackageApp $packageApp
        Write-Host "[AppDeployment] Dev deployment of '$($packageApp.Name)' succeeded"
        return
    }

    $existingApps = @(Get-TenantAppInfo -AppId $packageApp.AppId)
    $installedApps = @($existingApps | Where-Object { $_.IsInstalled } | Sort-Object { [Version]$_.Version } -Descending)
    $installedApp = $installedApps[0]
    # Matching package versions do not guarantee that tenant data is current. NeedsUpgrade is set by Business Central
    # when an app upgrade is still pending, while a lower ExtensionDataVersion means the tenant data uses an older
    # schema. Either state must continue through deployment so that Start-NAVAppDataUpgrade can complete the upgrade.
    $hasPendingDataUpgrade = $installedApp -and ($installedApp.NeedsUpgrade -or
        ($installedApp.ExtensionDataVersion -and [Version]$installedApp.ExtensionDataVersion -lt [Version]$installedApp.Version))
    if ($installedApp -and ([Version]$installedApp.Version -gt [Version]$packageApp.Version -or
        ([Version]$installedApp.Version -eq [Version]$packageApp.Version -and -not $hasPendingDataUpgrade))) {
        Write-Host "[AppDeployment] '$($packageApp.Name)' version $($installedApp.Version) is already installed"
        return
    }

    $targetApp = $existingApps | Where-Object { $_.IsPublished -and [Version]$_.Version -eq [Version]$packageApp.Version } | Select-Object -First 1
    if (-not $targetApp) {
        Write-Host "[AppDeployment] Publishing version $($packageApp.Version)"
        $publishParameters = @{
            ServerInstance = $serverInstance
            Path = $AppPath
            Scope = $Scope
            SkipVerification = $true
            Force = $true
            ErrorAction = 'Stop'
        }
        if ($Scope -eq 'Tenant') {
            $publishParameters.Tenant = $tenant
        }
        Publish-NAVApp @publishParameters
        $targetApp = Get-TenantAppInfo -AppId $packageApp.AppId -Version $packageApp.Version
    }
    else {
        Write-Host "[AppDeployment] Version $($packageApp.Version) is already published"
    }
    if (-not $targetApp -or -not $targetApp.IsPublished) {
        throw "App '$($packageApp.Name)' version $($packageApp.Version) was not published"
    }

    if ($targetApp.ExtensionDataVersion -and [Version]$targetApp.ExtensionDataVersion -gt [Version]$targetApp.Version) {
        throw "App '$($packageApp.Name)' has an extension data version higher than the app version"
    }

    # A synced app needs no Add sync, but ForceSync is an explicit request to reapply the schema.
    if ($SyncMode -eq 'ForceSync' -or $targetApp.SyncState -ne 'Synced') {
        Write-Host "[AppDeployment] Synchronizing schema with mode '$SyncMode'"
        Sync-AppDependencies -App $packageApp -ServerInstance $serverInstance -Tenant $tenant -SyncMode $SyncMode
        Sync-NAVApp -ServerInstance $serverInstance -Name $packageApp.Name -Publisher $packageApp.Publisher `
            -Version $packageApp.Version -Tenant $tenant -Mode $SyncMode -Force -ErrorAction SilentlyContinue -ErrorVariable syncErrors
        $targetApp = Get-TenantAppInfo -AppId $packageApp.AppId -Version $packageApp.Version
    }
    else {
        Write-Host "[AppDeployment] No synchronization needed for version $($packageApp.Version)"
    }
    if ($targetApp.SyncState -ne 'Synced') {
        throw "App '$($packageApp.Name)' version $($packageApp.Version) was not synchronized"
    }

    # The installed app describes the upgrade path: a newer package must migrate tenant data, while an equal
    # package version only needs migration when a previous data upgrade was left pending.
    $requiresDataUpgrade = $installedApp -and (
        [Version]$installedApp.Version -lt [Version]$packageApp.Version -or
        ([Version]$installedApp.Version -eq [Version]$packageApp.Version -and $hasPendingDataUpgrade))
    # Sync can change NeedsUpgrade and ExtensionDataVersion, so the refreshed tenant state is authoritative.
    # Only data behind the app version requires an upgrade; a newer data version is rejected before this point.
    $requiresDataUpgrade = $requiresDataUpgrade -or $targetApp.NeedsUpgrade -or
        ($targetApp.ExtensionDataVersion -and [Version]$targetApp.ExtensionDataVersion -lt [Version]$targetApp.Version)

    if ($requiresDataUpgrade) {
        Write-Host "[AppDeployment] Starting data upgrade for version $($packageApp.Version)"
        Start-NAVAppDataUpgrade -ServerInstance $serverInstance -Name $packageApp.Name -Publisher $packageApp.Publisher `
            -Version $packageApp.Version -Tenant $tenant -Force -ErrorAction Stop
    }
    elseif (-not $targetApp.IsInstalled) {
        Write-Host "[AppDeployment] Installing version $($packageApp.Version)"
        Install-NAVApp -ServerInstance $serverInstance -Name $packageApp.Name -Publisher $packageApp.Publisher `
            -Version $packageApp.Version -Tenant $tenant -Force -ErrorAction Stop
    }
    else {
        Write-Host "[AppDeployment] Version $($packageApp.Version) is already installed"
    }

    Write-Host '[AppDeployment] Verifying installed app state'
    $targetApp = Get-TenantAppInfo -AppId $packageApp.AppId -Version $packageApp.Version
    if (-not $targetApp -or -not $targetApp.IsInstalled) {
        throw "App '$($packageApp.Name)' version $($packageApp.Version) was not installed"
    }

    Write-Host "[AppDeployment] '$($packageApp.Name)' version $($packageApp.Version) is installed"
}
catch {
    Write-Host "[AppDeployment] Deployment failed: $($_.Exception.Message)"
    throw
}