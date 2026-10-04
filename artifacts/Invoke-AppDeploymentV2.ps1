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

C:\run\prompt.ps1

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
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($PublicDnsName) -or [string]::IsNullOrWhiteSpace($ContainerId) -or
        [string]::IsNullOrWhiteSpace($ContainerUser) -or [string]::IsNullOrWhiteSpace($ContainerPassword)) {
        throw 'Dev deployment requires PublicDnsName, ContainerId, ContainerUser, and ContainerPassword'
    }

    $schemaUpdateMode = if ($SyncMode -eq 'ForceSync') { 'forcesync' } else { 'synchronize' }
    $endpoint = "https://$PublicDnsName/$($ContainerId)dev/dev/apps?SchemaUpdateMode=$schemaUpdateMode&tenant=$tenant"
    Write-Host "[AppDeploymentV2] Publishing to the development endpoint with schema mode '$schemaUpdateMode'"
    $handler = [System.Net.Http.HttpClientHandler]::new()
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
    Write-Host "[AppDeploymentV2] Deploying '$($packageApp.Name)' $($packageApp.Version) with scope '$Scope'"

    if ($Scope -eq 'Dev') {
        Invoke-DevelopmentDeployment -Path $AppPath
        Write-Host "[AppDeploymentV2] Dev deployment of '$($packageApp.Name)' succeeded"
        return
    }

    $existingApps = @(Get-TenantAppInfo -AppId $packageApp.AppId)
    $installedApps = @($existingApps | Where-Object { $_.IsInstalled } | Sort-Object { [Version]$_.Version } -Descending)
    $installedApp = $installedApps[0]
    if ($installedApp -and [Version]$installedApp.Version -ge [Version]$packageApp.Version) {
        Write-Host "[AppDeploymentV2] '$($packageApp.Name)' version $($installedApp.Version) is already installed"
        return
    }

    $targetApp = @($existingApps | Where-Object { $_.IsPublished -and [Version]$_.Version -eq [Version]$packageApp.Version })[0]
    if (-not $targetApp) {
        Write-Host "[AppDeploymentV2] Publishing version $($packageApp.Version)"
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
        Write-Host "[AppDeploymentV2] Version $($packageApp.Version) is already published"
    }
    if (-not $targetApp -or -not $targetApp.IsPublished) {
        throw "App '$($packageApp.Name)' version $($packageApp.Version) was not published"
    }

    Write-Host "[AppDeploymentV2] Synchronizing schema with mode '$SyncMode'"
    $syncErrors = @()
    try {
        Sync-NAVApp -ServerInstance $serverInstance -Name $packageApp.Name -Publisher $packageApp.Publisher `
            -Version $packageApp.Version -Tenant $tenant -Mode $SyncMode -Force -ErrorAction SilentlyContinue -ErrorVariable syncErrors
    }
    catch {
        $syncErrors += $_
    }
    $targetApp = Get-TenantAppInfo -AppId $packageApp.AppId -Version $packageApp.Version
    if (-not $targetApp -or $targetApp.SyncState -ne 'Synced') {
        $syncErrors | ForEach-Object { Write-Host $_ }
        throw "App '$($packageApp.Name)' version $($packageApp.Version) was not synchronized"
    }

    $requiresDataUpgrade = $installedApp -and [Version]$installedApp.Version -lt [Version]$packageApp.Version

    if ($requiresDataUpgrade) {
        Write-Host "[AppDeploymentV2] Starting data upgrade from version $($installedApp.Version)"
        Start-NAVAppDataUpgrade -ServerInstance $serverInstance -Name $packageApp.Name -Publisher $packageApp.Publisher `
            -Version $packageApp.Version -Tenant $tenant -Force -ErrorAction Stop
    }
    elseif (-not $targetApp.IsInstalled) {
        Write-Host "[AppDeploymentV2] Installing version $($packageApp.Version)"
        Install-NAVApp -ServerInstance $serverInstance -Name $packageApp.Name -Publisher $packageApp.Publisher `
            -Version $packageApp.Version -Tenant $tenant -Force -ErrorAction Stop
    }
    else {
        Write-Host "[AppDeploymentV2] Version $($packageApp.Version) is already installed"
    }

    Write-Host '[AppDeploymentV2] Verifying installed app state'
    $targetApp = Get-TenantAppInfo -AppId $packageApp.AppId -Version $packageApp.Version
    if (-not $targetApp -or -not $targetApp.IsInstalled) {
        throw "App '$($packageApp.Name)' version $($packageApp.Version) was not installed"
    }

    Write-Host "[AppDeploymentV2] '$($packageApp.Name)' version $($packageApp.Version) is installed"
}
catch {
    Write-Host "[AppDeploymentV2] Deployment failed: $($_.Exception.Message)"
    throw
}