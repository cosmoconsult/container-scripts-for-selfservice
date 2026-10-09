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
    $installedApp = $existingApps | Where-Object { $_.IsInstalled } | Select-Object -First 1

    if ($installedApp -and ([Version]$installedApp.Version -gt [Version]$packageApp.Version -or ([Version]$installedApp.Version -eq [Version]$packageApp.Version -and $installedApp.NeedsUpgrade))) {
        Write-Host "[AppDeployment] '$($packageApp.Name)' version $($installedApp.Version) is already installed"
        return
    }
#
    $requiresDataUpgrade = $installedApp -and [Version]$installedApp.Version -ne [Version]$packageApp.Version

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

    #here check if data upgrade is required after publishing the app, sync updated the extension data version -> state of the synced app
    #installedversion ne targetversion (requires data upgrade)
    #is there dataversion is lower than the app version (requires data upgrade)
    $requiresDataUpgrade = $requiresDataUpgrade -or ($targetApp.ExtensionDataVersion -and [Version]$targetApp.ExtensionDataVersion -ne [Version]$targetApp.Version)
    
    #sync only relevant if data version lower than the app version
    if($targetApp.SyncState -ne 'Synced') {
        if([Version]$targetApp.ExtensionDataVersion -gt [Version]$targetApp.Version) {
            throw "App '$($packageApp.Name)' has an extension data version higher than the app version"
        }
        Write-Host "[AppDeployment] Synchronizing schema with mode '$SyncMode'"

        Sync-AppDependencies -App $packageApp -ServerInstance $serverInstance -Tenant $tenant -SyncMode $SyncMode
        Sync-NAVApp -ServerInstance $serverInstance -Name $packageApp.Name -Publisher $packageApp.Publisher `
        -Version $packageApp.Version -Tenant $tenant -Mode $SyncMode -Force -ErrorAction SilentlyContinue -ErrorVariable syncErrors
       
        $targetApp = Get-TenantAppInfo -AppId $packageApp.AppId -Version $packageApp.Version
    } else {
        Write-Host "[AppDeployment] No synchronization needed for version $($packageApp.Version)"
    }
    if ($targetApp.SyncState -ne 'Synced') {
        throw "App '$($packageApp.Name)' version $($packageApp.Version) was not synchronized"
    }
    
    #check if the target app requires a data upgrade: is data version lower than the app version 
    #NeedsUpgrade flag if it is set before sync 
    #or prop NeedsUpgrade (only after sync?) is set
    $requiresDataUpgrade = $requiresDataUpgrade -or $targetApp.NeedsUpgrade

    if ($requiresDataUpgrade) {
        Write-Host "[AppDeployment] Starting data upgrade for version $($packageApp.Version)" #fromversion not known always
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