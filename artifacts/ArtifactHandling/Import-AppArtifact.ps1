function Import-AppArtifact {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias("FullName")]    
        [string]$Path,
        [Parameter(Mandatory=$false)]
        [string]$ServerInstance = "NAV",
        [Parameter(Mandatory=$false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory=$false)]
        [string]$DatabaseServer = "localhost\sqlexpress",
        [Parameter(Mandatory=$false)]
        [string]$Filter = "*.app",
        [Parameter(Mandatory=$false)]
        [ValidateSet("Add", "ForceSync")]
        [string]$SyncMode = "Add",
        [Parameter(Mandatory=$false)]
        [ValidateSet("Global", "Tenant")]
        [string]$Scope = "Global",        
        [Parameter(Mandatory=$false)]
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }

        $importFiles = $false
    }
    
    process {
        # Initialize, if files are present
        if (! $importFiles -and (Get-Item -Path $Path -Filter $Filter -ErrorAction SilentlyContinue)) {
            $importFiles = $true
            Add-ArtifactsLog -message "Import App Artifacts..."           
        }
        
        $properties = @{"path" = $Path; "DatabaseName" = $DatabaseName; "NavServiceName" = $NavServiceName; "ServerInstance" = $ServerInstance; SyncMode = $SyncMode; Scope = $Scope}
        try {
            $started = Get-Date -Format "o"
            
            $app     = (Get-NAVAppInfo -Path $Path)            
            $properties["Name"]       = $app.Name
            $properties["Publisher"]  = $app.Publisher
            $properties["AppId"]      = $app.Id
            $properties["Version"]    = $app.Version

            Add-ArtifactsLog -kind App -message "$([System.Environment]::NewLine)Import App $($app.Name) $($app.Publisher) $($app.Version)..." -data $app

            $scopeParameters = @{ Scope = "$Scope" }
            # Add tenant specific parameter only for tenant scope
            if ("$Scope" -eq "Tenant") {
                $scopeParameters["Tenant"] = $Tenant
            }            

            # Publish NAVApp
            try {
                $started2 = Get-Date -Format "o"
                Add-ArtifactsLog -kind App -message "Publish App $($app.Name) $($app.Publisher) $($app.Version) Scope: $Scope ..." -data $app
                Publish-NavApp -ServerInstance $ServerInstance -Path $Path @scopeParameters -SkipVerification -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app }
                $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app }
                $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app }
                $success = ! $err
                if ($success) { Add-ArtifactsLog -kind App -message "Publish App successful" -data $app -success success }
            } catch {
                Add-ArtifactsLog -kind App -message "Publish App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                $success = $false
            } finally {
                Invoke-LogOperation -name "Publish App" -started $started2 -properties $properties -success $success -telemetryClient $telemetryClient
            }

            # Sync NAVApp
            if ($success) {
                $successInstall = $success
                try {
                    $started2 = Get-Date -Format "o"
                    Add-ArtifactsLog -kind App -message "Sync App $($app.Name) $($app.Publisher) $($app.Version)..." -data $app
                    Sync-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Mode $SyncMode -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                    $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app }
                    $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app }
                    $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind App -message "Sync App ... successful" -data $app -success success }
                } catch {
                    Add-ArtifactsLog -kind App -message "Sync App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                    $success = $false
                } finally {
                    Invoke-LogOperation -name "Publish App" -started $started2 -properties $properties -success $success -telemetryClient $telemetryClient
                }
            }

            # Install NAVApp
            if ($successInstall) {
                try {
                    $started2 = Get-Date -Format "o"
                    Add-ArtifactsLog -kind App -message "Install App $($app.Name) $($app.Publisher) $($app.Version)..." -data $app
                    Install-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Force -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info
                    $info | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Info  -data $app }
                    $warn | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Warn  -data $app }
                    $err  | foreach { Add-ArtifactsLog -kind App -message "$_" -severity Error -data $app }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind App -message "Install App ... successful" -data $app -success success }
                } catch {        
                    Add-ArtifactsLog -kind App -message "Install App $($app.Name) $($app.Publisher) $($app.Version) FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $app -success fail -severity Error
                    $success = $false
                } finally {                
                    Invoke-LogOperation -name "Install App" -started $started2 -properties $properties -success $success -telemetryClient $telemetryClient
                }
            }
            # Check Result
            $result = Get-NAVAppInfo -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -TenantSpecificProperties -Tenant $Tenant -ErrorAction SilentlyContinue
            if ($result) { 
                Add-ArtifactsLog -kind App -message "$(($result | Select-Object Name, Publisher, Version, IsPublished, IsInstalled, SyncState, ExtensionDataVersion | Format-Table -AutoSize | Out-String -Width 1024).Trim())"
                $result = $result | Select-Object -First 1
                Add-ArtifactsLog -kind App -message "App Status $($app.Name) $($app.Publisher) $($app.Version) ... Published: $($result.IsPublished) Installed: $($result.IsInstalled) SyncState: $($result.SyncState) " -data $result
            } else {
                Add-ArtifactsLog -kind App -message "Import App $($app.Name) $($app.Publisher) $($app.Version) failed" -data $app -severity Error -success fail
            }

            if ($result) {
                $properties["IsPublished"]          = $result.IsPublished
                $properties["IsInstalled"]          = $result.IsInstalled
                $properties["SyncState"]            = $result.SyncState
                $properties["ExtensionDataVersion"] = $result.ExtensionDataVersion
            }
            Add-ArtifactsLog -message " "
            Invoke-LogOperation -name "Import App Artifact" -started $started -properties $properties -telemetryClient $telemetryClient
        }
        catch {
            Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Import App Artifact"
        }
    }
    
    end {
        if ($importFiles) {
            Add-ArtifactsLog -message "Import App Artifacts done."
        }
    }
}
Export-ModuleMember -Function Import-AppArtifact