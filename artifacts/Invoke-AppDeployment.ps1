[CmdletBinding()]
param (
    [string]$AppToDeploy,
    [string]$Username,  # ignored
    [string]$Password,  # ignored
    [string]$BearerToken = "",
    [string]$PathInZip = "",
    [Parameter(Mandatory=$false)]
    [ValidateSet('Global','Tenant','Dev')]
    [string] $Scope = "Tenant"
)

c:\run\prompt.ps1
try {
    $started = Get-Date -Format "o"

    if ($Scope -eq 'Dev') {
        Write-Host "Deployment to the dev endpoint is not yet supported"
        return
    }

    if ($AppToDeploy.StartsWith("http")) {
        # given a URL, so need to download
        $basePath = "c:\downloadedBuildArtifacts"
        $headers = @{}
        $headers.Add("authorization", "Bearer $BearerToken")
        if (-not (Test-Path $basePath)) {
            New-Item "$basePath" -ItemType Directory
        }
        $subfolder = $([convert]::tostring((get-random 65535),16).padleft(8,'0'))
        $folder = Join-Path $basePath $subfolder
        New-Item "$folder" -ItemType Directory
        $filename = "downloadedapp.app"
        if ($AppToDeploy.EndsWith("zip")) {
            $filename = "downloadedapp.zip"
        }
        $fullPath = Join-Path $folder $filename
        Invoke-WebRequest -Uri $AppToDeploy -Method GET -Headers $headers -OutFile $fullPath
        if (-not (Test-Path $fullPath)) {
            Write-Host "Failed to download the file from $AppToDeploy"
            exit
        }

        if ($AppToDeploy.EndsWith("zip")) {
            Expand-Archive $fullPath -DestinationPath $folder
            $AppToDeploy = Join-Path $folder $PathInZip
            if (-not (Test-Path $AppToDeploy)) {
                Write-Host "Couldn't find $PathInZip in $AppToDeploy"
                exit
            }
        } else {
            $AppToDeploy = $fullPath
        }
    }
    
    $ServerInstance = "BC"
    $Path = $AppToDeploy
    $app     = (Get-NAVAppInfo -Path $Path) 

    # Check if app is already published with another version
    $oldApp = (Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -ErrorAction SilentlyContinue) | Select-Object -First 1
    
    # Uninstall old NAVApp, when present
    if($oldApp -and $oldApp.IsInstalled) {
        try {
            $started1 = Get-Date -Format "o"
            Write-Host "Uninstall-NAVApp -ServerInstance $ServerInstance -Tenant default -Name $($oldApp.Name) -Publisher $($oldApp.Publisher) -Version $($oldApp.Version) -Force"
            Uninstall-NAVApp -ServerInstance $ServerInstance -Tenant default -Name $oldApp.Name -Publisher $oldApp.Publisher -Version $oldApp.Version -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            $info | foreach { Write-Host "$_" }
            $warn | foreach { Write-Host "$_" }
            $err  | foreach { Write-Host "$_" }
            $success = ! $err
            if ($success) { Write-Host "Uninstall old App successful" }
            $runDataUpgrade = $true
        } catch {
            Write-Host "Uninstall old App $($oldApp.Name) $($oldApp.Publisher) $($oldApp.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
            $success = $false
        }
    } else {
        if ($oldApp) {
            $runDataUpgrade = $true
        } else {
            $runDataUpgrade = $false
        } 
        $success = $true
    }

    # Publish NAVApp
    if ($success) {
        try {
            $started2 = Get-Date -Format "o"
            
            if ($Scope -eq "Global") {
                Write-Host "Publish-NavApp -ServerInstance $ServerInstance -Path $Path -SkipVerification -Scope $Scope"
                Publish-NavApp -ServerInstance $ServerInstance -Path $Path -SkipVerification -Scope $Scope -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            } elseif ($Scope -eq "Tenant") {
                Write-Host "Publish-NavApp -ServerInstance $ServerInstance -Path $Path -SkipVerification -Scope $Scope -Tenant default"
                Publish-NavApp -ServerInstance $ServerInstance -Path $Path -SkipVerification -Scope $Scope -Tenant default -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            }
            $info | foreach { Write-Host "$_" }
            $warn | foreach { Write-Host "$_" }
            $err  | foreach { Write-Host "$_" }
            $success = ! $err
            if ($success) { Write-Host "Publish App successful" }
        } catch {
            Write-Host "Publish App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
            $success = $false
        }
    }

    # Sync NAVApp
    if ($success) {
        $skipInstall = ! $success
        try {
            $started2 = Get-Date -Format "o"
            Write-Host "Sync-NAVApp -ServerInstance $ServerInstance -Name $($app.Name) -Publisher $($app.Publisher) -Version $($app.Version) -Force"
            Sync-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            $info | foreach { Write-Host "$_" }
            $warn | foreach { Write-Host "$_" }
            $err  | foreach { Write-Host "$_" }
            $success = ! $err
            if ($success) { Write-Host "Sync App ... successful" }
        } catch {
            Write-Host "Sync App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
            $success = $false
        }
        $skipInstall = ! $success
    }

    # If extension data version is older than extension version, that should also trigger the data upgrade
    $appInfo = (Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant default -TenantSpecificProperties -ErrorAction SilentlyContinue) | Select-Object -First 1
    if ((! $skipInstall) -and ($appInfo.ExtensionDataVersion) -and [System.Version]$appInfo.ExtensionDataVersion -lt [System.Version]$appInfo.Version) {
        Write-Host "Identified lower extension data version ($($appInfo.ExtensionDataVersion)) than extension version ($($appInfo.Version)), need to run data upgrade"
        $runDataUpgrade = $true
    }

    # Check for Data Upgrade
    if ((! $skipInstall) -and ($runDataUpgrade)) {
        try {
            $started2 = Get-Date -Format "o"
            Write-Host "Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Name $($app.Name) -Publisher $($app.Publisher) -Version $($app.Version) -Force"
            
            Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            $info | foreach { Write-Host "$_" }
            $warn | foreach { Write-Host "$_" }
            $err  | foreach { Write-Host "$_" }
            $success     = ! $err
            if ($success) { Write-Host "App Data Upgrade ... successful" }
            # Check, if the new App is correct installed
            $result = (Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -ErrorAction SilentlyContinue) | Select-Object -First 1
            $skipInstall = $result -and $result.IsInstalled  
        } catch {
            Write-Host "Start App Data Upgrade $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
            $success     = $false
            $skipInstall = $true
        }
    }

    # Install NAVApp
    if (! $skipInstall) {
        try {
            $started3 = Get-Date -Format "o"
            Write-Host "Install-NAVApp -ServerInstance $ServerInstance -Name $($app.Name) -Publisher $($app.Publisher) -Version $($app.Version)"
            Install-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            $info | foreach { Write-Host "$_" }
            $warn | foreach { Write-Host "$_" }
            $err  | foreach { Write-Host "$_" }
            $success = ! $err
            if ($success) { Write-Host "Install App ... successful" }
        } catch {        
            Write-Host "Install App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
            $success = $false
        }
    }
    # Check Result
    $result = Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -ErrorAction SilentlyContinue
    if ($result) { 
        Write-Host "$(($result | Select-Object Name, Publisher, Version, IsPublished, IsInstalled, SyncState, NeedsUpgrade, ExtensionDataVersion | Format-Table -AutoSize | Out-String -Width 1024).Trim())"
        $result = $result | Select-Object -First 1
        Write-Host "App Status $($app.Name) $($app.Publisher) $($app.Version) ... Published: $($result.IsPublished) Installed: $($result.IsInstalled) SyncState: $($result.SyncState) "
    } else {
        Write-Host "Import App $($app.Name) $($app.Publisher) $($app.Version) failed"
    }
}
catch {
    Write-Host "$_"
}
