function Import-AppArtifact {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName")]    
        [string]$Path,
        [switch]$IsModifiedBaseApp,
        [Parameter(Mandatory = $false)]
        [string]$ServerInstance = "NAV",
        [Parameter(Mandatory = $false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory = $false)]
        [string]$DatabaseServer = "localhost\sqlexpress",
        [Parameter(Mandatory = $false)]
        [string]$Filter = "*.app",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Add", "ForceSync")]
        [string]$SyncMode = "Add",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Global", "Tenant")]
        [string]$Scope = "Global",        
        [Parameter(Mandatory = $false)]
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }

        $importFiles = $false
        $started = Get-Date -Format "o"
    }
    
    process {
        # check restart
        if ($env:cosmoServiceRestart -eq $true) {
            Add-ArtifactsLog -message "Skipping artifact import because this seems to be a service restart"
            return
        }

        # Initialize, if files are present
        if (! $importFiles -and (Get-Item -Path $Path -Filter $Filter -ErrorAction SilentlyContinue)) {
            $importFiles = $true
            Add-ArtifactsLog -message "Import App Artifacts..."           
        }
        
        $properties = @{"path" = $Path; "DatabaseName" = $DatabaseName; "NavServiceName" = $NavServiceName; "ServerInstance" = $ServerInstance; SyncMode = $SyncMode; Scope = $Scope }
        try {
            $started = Get-Date -Format "o"
            
            $app = (Get-NAVAppInfo -Path $Path)            
            Write-Host "##[group]$($app.Name) $($app.Publisher) $($app.Version)"
            $properties["Name"] = $app.Name
            $properties["Publisher"] = $app.Publisher
            $properties["AppId"] = $app.Id
            $properties["Version"] = $app.Version

            Add-ArtifactsLog -kind App -message "$([System.Environment]::NewLine)Import App $($app.Name) $($app.Publisher) $($app.Version)..." -data $app

            $optionalParameters = @{ }
            # Special handling for NAV2018
            # '-Force' is only added, when 'SandboxDatabaseName' (NAV2018) is NOT present, 
            # because parameter '-Force' works only, when 'SandboxDatabaseName' is not empty
            if (! ((Get-Command Publish-NAVApp -All).Parameters.SandboxDatabaseName)) {
                $optionalParameters["Force"] = $true
            }
            # Add scope parameter when available for the command
            if ((Get-Command Publish-NAVApp -All).Parameters.Scope) {
                $optionalParameters["Scope"] = "$Scope"
            }
            # Add tenant specific parameter only for tenant scope
            if (("$Scope" -eq "Tenant") -and ((Get-Command Publish-NAVApp -All).Parameters.Tenant)) {
                $optionalParameters["Tenant"] = $Tenant
            }   

            # Check if app is already published with another version
            $oldApp = (Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -TenantSpecificProperties -Tenant $Tenant -ErrorAction SilentlyContinue) | Select-Object -First 1
            
            # Uninstall old NAVApp, when present
            if ($oldApp -and $oldApp.IsInstalled) {
                try {
                    $started1 = Get-Date -Format "o"
                    Add-ArtifactsLog -kind App -message "Uninstall old App $($oldApp.Name) $($oldApp.Publisher) $($oldApp.Version) ..." -data $app
                    Uninstall-NAVApp -ServerInstance $ServerInstance -Tenant $Tenant -Name $oldApp.Name -Publisher $oldApp.Publisher -Version $oldApp.Version -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                    $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app }
                    $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app }
                    $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind App -message "Uninstall old App successful" -data $app -success success }
                    $runDataUpgrade = $true
                }
                catch {
                    Add-ArtifactsLog -kind App -message "Uninstall old App $($oldApp.Name) $($oldApp.Publisher) $($oldApp.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                    $success = $false
                }
                finally {
                    Invoke-LogOperation -name "Uninstall old App" -started $started1 -properties $properties -success $success -telemetryClient $telemetryClient
                }
            }
            else {
                if ($oldApp) {
                    $runDataUpgrade = $true
                }
                else {
                    $runDataUpgrade = $false
                } 
                $success = $true
            }
    
            # Publish NAVApp
            if ($success) {
                try {
                    $started2 = Get-Date -Format "o"
                    Add-ArtifactsLog -kind App -message "Publish App $($app.Name) $($app.Publisher) $($app.Version) Scope: $Scope ..." -data $app
                    Publish-NavApp -ServerInstance $ServerInstance -Path $Path @optionalParameters -SkipVerification -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                    $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app }
                    $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app }
                    $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind App -message "Publish App successful" -data $app -success success }
                }
                catch {
                    Add-ArtifactsLog -kind App -message "Publish App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                    $success = $false
                }
                finally {
                    Invoke-LogOperation -name "Publish App" -started $started2 -properties $properties -success $success -telemetryClient $telemetryClient
                }
                $skipInstall = ! $success
            }

            # Sync NAVApp
            if ($success) {
                try {
                    $started2 = Get-Date -Format "o"
                    Add-ArtifactsLog -kind App -message "Sync App $($app.Name) $($app.Publisher) $($app.Version)..." -data $app
                    Sync-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Mode $SyncMode -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                    $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app }
                    $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app }
                    $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind App -message "Sync App ... successful" -data $app -success success }
                }
                catch {
                    Add-ArtifactsLog -kind App -message "Sync App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                    $success = $false
                }
                finally {
                    Invoke-LogOperation -name "Sync App" -started $started2 -properties $properties -success $success -telemetryClient $telemetryClient
                }
                $skipInstall = ! $success
            }

            # Check for Data Upgrade
            if ((! $skipInstall) -and ($runDataUpgrade)) {
                try {
                    $started2 = Get-Date -Format "o"
                    Add-ArtifactsLog -kind App -message "Start App Data Upgrade $($app.Name) $($app.Publisher) $($app.Version)..." -data $app
                    
                    Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                    $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app }
                    $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app }
                    $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind App -message "App Data Upgrade ... successful" -data $app -success success }
                    # Check, if the new App is correct installed
                    $result = (Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -TenantSpecificProperties -Tenant $Tenant -ErrorAction SilentlyContinue) | Select-Object -First 1
                    $skipInstall = $result -and $result.IsInstalled  
                }
                catch {
                    Add-ArtifactsLog -kind App -message "Start App Data Upgrade $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                    $success = $false
                    $skipInstall = $true
                }
                finally {
                    Invoke-LogOperation -name "App Data Upgrade" -started $started2 -properties $properties -success $success -telemetryClient $telemetryClient
                }
            }

            # Install NAVApp
            if (! $skipInstall) {
                try {
                    $started3 = Get-Date -Format "o"
                    Add-ArtifactsLog -kind App -message "Install App $($app.Name) $($app.Publisher) $($app.Version)..." -data $app
                    Install-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                    $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app -lowerCase }
                    $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app -lowerCase }
                    $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app -lowerCase }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind App -message "Install App ... successful" -data $app -success success }
                }
                catch {        
                    Add-ArtifactsLog -kind App -message "Install App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                    $success = $false
                }
                finally {                
                    Invoke-LogOperation -name "Install App" -started $started3 -properties $properties -success $success -telemetryClient $telemetryClient
                }
            }

            # Special handling for modified base app
            if ($IsModifiedBaseApp) {
                # remember base app version
                $env:cosmoBaseAppVersion = $app.Version
            }

            # Check Result
            $result = Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -TenantSpecificProperties -Tenant $Tenant -ErrorAction SilentlyContinue
            if ($result) { 
                Add-ArtifactsLog -kind App -message "$(($result | Select-Object Name, Publisher, Version, IsPublished, IsInstalled, SyncState, NeedsUpgrade, ExtensionDataVersion | Format-Table -AutoSize | Out-String -Width 1024).Trim())"
                $result = $result | Select-Object -First 1
                Add-ArtifactsLog -kind App -message "App Status $($app.Name) $($app.Publisher) $($app.Version) ... Published: $($result.IsPublished) Installed: $($result.IsInstalled) SyncState: $($result.SyncState) " -data $result
            }
            else {
                Add-ArtifactsLog -kind App -message "Import App $($app.Name) $($app.Publisher) $($app.Version) failed" -data $app -severity Error -success fail
            }

            if ($result) {
                $properties["IsPublished"] = $result.IsPublished
                $properties["IsInstalled"] = $result.IsInstalled
                $properties["SyncState"] = $result.SyncState
                $properties["NeedsUpgrade"] = $result.NeedsUpgrade
                $properties["ExtensionDataVersion"] = $result.ExtensionDataVersion
            }
            Add-ArtifactsLog -message " "
            Invoke-LogOperation -name "Import App Artifact" -started $started -properties $properties -telemetryClient $telemetryClient
        }
        catch {
            Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Import App Artifact"
        }
        Write-Host "##[endgroup]"
    }
    
    end {
        if ($importFiles) {
            Add-ArtifactsLog -message "Import App Artifacts done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
        }
    }
}
Export-ModuleMember -Function Import-AppArtifact