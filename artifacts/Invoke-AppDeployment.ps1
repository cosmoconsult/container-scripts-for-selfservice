[CmdletBinding()]
param (
    [string]$AppToDeploy, 
    [string]$Username,
    [string]$Password
)

c:\run\prompt.ps1
try {
    $started = Get-Date -Format "o"
    
    $ServerInstance = "BC"
    $Path = $AppToDeploy
    $app     = (Get-NAVAppInfo -Path $Path) 

    # Check if app is already published with another version
    $oldApp = (Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -ErrorAction SilentlyContinue) | Select-Object -First 1
    
    # Uninstall old NAVApp, when present
    if($oldApp -and $oldApp.IsInstalled) {
        try {
            $started1 = Get-Date -Format "o"
            Uninstall-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $oldApp.Name -Publisher $oldApp.Publisher -Version $oldApp.Version -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            $info | foreach { Write-Host "$_" }
            $warn | foreach { Write-Host "$_" }
            $err  | foreach { Write-Error "$_" }
            $success = ! $err
            if ($success) { Write-Host "Uninstall old App successful" }
            $runDataUpgrade = $true
        } catch {
            Write-Error "Uninstall old App $($oldApp.Name) $($oldApp.Publisher) $($oldApp.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
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
            Write-Host "Publish App $($app.Name) $($app.Publisher) $($app.Version) Scope: $Scope ..."
            Publish-NavApp -ServerInstance $ServerInstance -Path $Path -SkipVerification -Scope tenant -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            $info | foreach { Write-Host "$_" }
            $warn | foreach { Write-Host "$_" }
            $err  | foreach { Write-Error "$_" }
            $success = ! $err
            if ($success) { Write-Host "Publish App successful" }
        } catch {
            Write-Error "Publish App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
            $success = $false
        }
    }

    # Sync NAVApp
    if ($success) {
        $skipInstall = ! $success
        try {
            $started2 = Get-Date -Format "o"
            Write-Host "Sync App $($app.Name) $($app.Publisher) $($app.Version)..."
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

    # Check for Data Upgrade
    if ((! $skipInstall) -and ($runDataUpgrade)) {
        try {
            $started2 = Get-Date -Format "o"
            Write-Host "Start App Data Upgrade $($app.Name) $($app.Publisher) $($app.Version)..."
            
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
            Write-Host "Install App $($app.Name) $($app.Publisher) $($app.Version)..."
            Install-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
            $info | foreach { Write-Host "$_" -lowerCase }
            $warn | foreach { Write-Host "$_" -lowerCase }
            $err  | foreach { Write-Error "$_" -severity Error -lowerCase }
            $success = ! $err
            if ($success) { Write-Host "Install App ... successful" }
        } catch {        
            Write-Error "Install App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)"
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
        Write-Error "Import App $($app.Name) $($app.Publisher) $($app.Version) failed"
    }
}
catch {
    Write-Error "$_"
}