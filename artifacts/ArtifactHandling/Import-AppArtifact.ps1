function Import-AppArtifact {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName")]
        [string]$Path,
        [switch]$IsModifiedBaseApp,
        [string]$ServerInstance = "NAV",
        [string]$Tenant = "default",
        [string]$DatabaseServer = "localhost\sqlexpress",
        [string]$Filter = "*.app",
        [ValidateSet("Add", "ForceSync")]
        [string]$SyncMode = "Add",
        [ValidateSet("Global", "Tenant", "Dev")]
        [string]$Scope = "Global",
        [System.Object]$telemetryClient = $null,
        [string]$DevEndpointUrl = "",
        [string]$DevEndpointUser = "",
        [string]$DevEndpointPassword = "",
        [switch]$SkipServiceRestartCheck
    )

    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        $importFiles = $false
        $importStarted = Get-Date -Format "o"

        function Get-ImportTenantAppInfo {
            param ([Guid]$AppId, [Version]$Version)

            if ($Version) {
                return Get-NAVAppInfo -ServerInstance $ServerInstance -Id $AppId -Tenant $Tenant -TenantSpecificProperties -Version $Version -ErrorAction Stop | Select-Object -First 1
            }
            return @(Get-NAVAppInfo -ServerInstance $ServerInstance -Id $AppId -Tenant $Tenant -TenantSpecificProperties -ErrorAction Stop)
        }

        function Invoke-AppImportStep {
            param ([string]$Name, [scriptblock]$Action)

            $stepStarted = Get-Date -Format "o"
            $stepSuccess = $false
            try {
                Add-ArtifactsLog -kind App -message "$Name $($app.Name) $($app.Publisher) $($app.Version)..." -data $app
                try {
                    & $Action 3>&1 6>&1 | ForEach-Object {
                        if ($_ -is [System.Management.Automation.WarningRecord]) {
                            Add-ArtifactsLog -kind App -message "$_" -severity Warn -data $app
                        }
                        elseif ($_ -is [System.Management.Automation.InformationRecord]) {
                            Add-ArtifactsLog -kind App -message "$_" -severity Info -data $app
                        }
                    }
                }
                catch {
                    if ($_ | Remove-PowerShellFlowControlErrors) {
                        throw
                    }
                }
                $stepSuccess = $true
                Add-ArtifactsLog -kind App -message "$Name successful" -data $app -success success
            }
            finally {
                Invoke-LogOperation -name $Name -started $stepStarted -properties $properties -success $stepSuccess -telemetryClient $telemetryClient
            }
        }

        function Unpublish-OldAppVersion {
            param ([object]$OldApp, [Guid]$AppId, [Version]$NewVersion)

            if (-not $OldApp -or -not $OldApp.IsPublished -or [Version]$OldApp.Version -ge $NewVersion) {
                return
            }

            $stepStarted = Get-Date -Format "o"
            $stepSuccess = $false
            try {
                $unpublishParameters = @{
                    ServerInstance = $ServerInstance
                    Name = $OldApp.Name
                    Publisher = $OldApp.Publisher
                    Version = $OldApp.Version
                    ErrorAction = "Stop"
                }
                if ($OldApp.Scope -eq "Tenant") {
                    if (-not (Get-Command Unpublish-NAVApp -ErrorAction Stop).Parameters.ContainsKey("Tenant")) {
                        Add-ArtifactsLog -kind App -message "Cannot unpublish tenant-scoped old App $($OldApp.Name) $($OldApp.Version): Unpublish-NAVApp does not support Tenant" -severity Warn -success skip -data $OldApp
                        $stepSuccess = $true
                        return
                    }
                    $unpublishParameters.Tenant = $Tenant
                }
                elseif ($OldApp.Scope -eq "Global") {
                    $installedTenants = @(Get-NAVAppTenant -ServerInstance $ServerInstance -Id $AppId -Version $OldApp.Version -ErrorAction Stop |
                        Select-Object -ExpandProperty Id)
                    if ($installedTenants) {
                        Add-ArtifactsLog -kind App -message "Keeping globally published old App $($OldApp.Name) $($OldApp.Version): it is still installed in tenant(s) '$($installedTenants -join ', ')'" -severity Warn -success skip -data $OldApp
                        $stepSuccess = $true
                        return
                    }
                }
                else {
                    Add-ArtifactsLog -kind App -message "Cannot safely unpublish old App $($OldApp.Name) $($OldApp.Version): unknown publishing scope '$($OldApp.Scope)'" -severity Warn -success skip -data $OldApp
                    $stepSuccess = $true
                    return
                }

                Add-ArtifactsLog -kind App -message "Unpublish old App $($OldApp.Name) $($OldApp.Publisher) $($OldApp.Version)..." -data $OldApp
                Unpublish-NAVApp @unpublishParameters
                Add-ArtifactsLog -kind App -message "Unpublish old App successful" -data $OldApp -success success
                $stepSuccess = $true
            }
            catch {
                Add-ArtifactsLog -kind App -message "Unpublish old App $($OldApp.Name) $($OldApp.Publisher) $($OldApp.Version) failed: $($_.Exception.Message)" -data $OldApp -severity Error -success fail
                Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Unpublish Old App"
            }
            finally {
                Invoke-LogOperation -name "Unpublish Old App" -started $stepStarted -properties $properties -success $stepSuccess -telemetryClient $telemetryClient
            }
        }
    }

    process {
        if (-not $SkipServiceRestartCheck -and $env:cosmoServiceRestart -eq $true) {
            Add-ArtifactsLog -message "Skipping artifact import because this seems to be a service restart"
            return
        }

        $started = Get-Date -Format "o"
        $properties = @{ Path = $Path; ServerInstance = $ServerInstance; Tenant = $Tenant; SyncMode = $SyncMode; Scope = $Scope }
        $groupStarted = $false
        $success = $false
        $installedApp = $null
        try {
            if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
                throw "App '$Path' does not exist"
            }
            if (-not $importFiles) {
                $importFiles = $true
                Add-ArtifactsLog -message "Import App Artifacts..."
            }

            $app = Get-NAVAppInfo -Path $Path -ErrorAction Stop
            $appId = if ($app.AppId) { $app.AppId } else { $app.Id }
            Write-Host "##[group]$($app.Name) $($app.Publisher) $($app.Version)"
            $groupStarted = $true
            $properties["Name"] = $app.Name
            $properties["Publisher"] = $app.Publisher
            $properties["AppId"] = $appId
            $properties["Version"] = $app.Version

            if ($SyncMode -eq "ForceSync") {
                Write-Warning "ForceSync is intended only for development and testing and can cause data loss."
            }
            if ($Scope -eq "Dev") {
                Invoke-AppImportStep -Name "Publish App to development endpoint" -Action {
                    if ([string]::IsNullOrWhiteSpace($DevEndpointUrl) -or
                        [string]::IsNullOrWhiteSpace($DevEndpointUser) -or [string]::IsNullOrWhiteSpace($DevEndpointPassword)) {
                        throw "Dev deployment requires DevEndpointUrl, DevEndpointUser, and DevEndpointPassword"
                    }
                    $parsedEndpoint = $null
                    if (-not [Uri]::TryCreate($DevEndpointUrl, [UriKind]::Absolute, [ref]$parsedEndpoint) -or
                        $parsedEndpoint.Scheme -notin @("http", "https") -or $parsedEndpoint.Query -or $parsedEndpoint.Fragment) {
                        throw "DevEndpointUrl must be an absolute HTTP(S) URL without a query or fragment"
                    }
                    $schemaUpdateMode = if ($SyncMode -eq "ForceSync") { "forcesync" } else { "synchronize" }
                    $endpoint = "$($DevEndpointUrl.TrimEnd('/'))?SchemaUpdateMode=$schemaUpdateMode&tenant=$([Uri]::EscapeDataString($Tenant))"
                    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
                    $handler = [System.Net.Http.HttpClientHandler]::new()
                    $client = $null
                    $fileStream = $null
                    $content = $null
                    $response = $null
                    try {
                        $client = [System.Net.Http.HttpClient]::new($handler)
                        $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan
                        $client.DefaultRequestHeaders.ExpectContinue = $false
                        $credentials = [System.Text.Encoding]::UTF8.GetBytes("${DevEndpointUser}:$DevEndpointPassword")
                        $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Basic", [Convert]::ToBase64String($credentials))
                        $fileStream = [System.IO.File]::OpenRead($Path)
                        $content = [System.Net.Http.MultipartFormDataContent]::new()
                        $fileContent = [System.Net.Http.StreamContent]::new($fileStream)
                        $content.Add($fileContent, [System.IO.Path]::GetFileName($Path), [System.IO.Path]::GetFileName($Path))
                        $response = $client.PostAsync($endpoint, $content).GetAwaiter().GetResult()
                        if (-not $response.IsSuccessStatusCode) {
                            $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                            throw "Dev endpoint returned $([int]$response.StatusCode) ($($response.ReasonPhrase)): $responseBody"
                        }
                    }
                    finally {
                        if ($response) { $response.Dispose() }
                        if ($content) { $content.Dispose() }
                        if ($fileStream) { $fileStream.Dispose() }
                        if ($client) { $client.Dispose() }
                        $handler.Dispose()
                    }
                }
                $success = $true
                return
            }

            $installedApp = Get-ImportTenantAppInfo -AppId $appId |
                Where-Object { $_.IsInstalled } |
                Sort-Object { [Version]$_.Version } -Descending |
                Select-Object -First 1
            if ($installedApp -and [Version]$installedApp.Version -ge [Version]$app.Version) {
                $needsUpgrade = $installedApp.NeedsUpgrade -or
                    ($installedApp.ExtensionDataVersion -and [Version]$installedApp.ExtensionDataVersion -lt [Version]$installedApp.Version)
                $hasNewerData = $installedApp.ExtensionDataVersion -and [Version]$installedApp.ExtensionDataVersion -gt [Version]$installedApp.Version
                if ([Version]$installedApp.Version -gt [Version]$app.Version -and
                    ($needsUpgrade -or $hasNewerData -or $installedApp.SyncState -ne "Synced")) {
                    throw "Newer installed version $($installedApp.Version) of app '$($app.Name)' has an incomplete synchronization or data upgrade"
                }
                # SyncMode only selects how a pending schema sync runs; it never re-imports an installed, synchronized app.
                if (-not $needsUpgrade -and -not $hasNewerData -and $installedApp.SyncState -eq "Synced") {
                    Add-ArtifactsLog -kind App -message "Skipping App $($app.Name) $($app.Version): version $($installedApp.Version) is already installed." -data $app
                    $success = $true
                    return
                }
            }

            $targetApp = Get-ImportTenantAppInfo -AppId $appId -Version $app.Version
            if (-not $targetApp -or -not $targetApp.IsPublished) {
                Invoke-AppImportStep -Name "Publish App" -Action {
                    $optionalParameters = @{}
                    $commandInfo = Get-Command Publish-NAVApp -ErrorAction Stop
                    if (-not $commandInfo.Parameters.SandboxDatabaseName) {
                        $optionalParameters.Force = $true
                    }
                    if ($commandInfo.Parameters.Scope) {
                        $optionalParameters.Scope = $Scope
                    }
                    if ($Scope -eq "Tenant" -and $commandInfo.Parameters.Tenant) {
                        $optionalParameters.Tenant = $Tenant
                    }
                    Publish-NAVApp -ServerInstance $ServerInstance -Path $Path @optionalParameters -SkipVerification -ErrorAction Stop
                }
                $targetApp = Get-ImportTenantAppInfo -AppId $appId -Version $app.Version
            }
            if (-not $targetApp -or -not $targetApp.IsPublished) {
                throw "App '$($app.Name)' version $($app.Version) was not published"
            }
            if ($targetApp.ExtensionDataVersion -and [Version]$targetApp.ExtensionDataVersion -gt [Version]$targetApp.Version) {
                throw "App '$($app.Name)' has an extension data version higher than the app version"
            }

            if ($targetApp.SyncState -ne "Synced") {
                # Dependencies always use Add so ForceSync cannot drop their schema data.
                Sync-AppDependencies -App $app -ServerInstance $ServerInstance -Tenant $Tenant -SyncMode Add -ErrorAction Stop
                if ($SyncMode -eq "ForceSync" -and $installedApp -and [Version]$installedApp.Version -lt [Version]$app.Version) {
                    Invoke-AppImportStep -Name "Uninstall old App" -Action {
                        Uninstall-NAVApp -ServerInstance $ServerInstance -Name $installedApp.Name -Publisher $installedApp.Publisher -Version $installedApp.Version -Tenant $Tenant -Force -ErrorAction Stop
                    }
                }
                Invoke-AppImportStep -Name "Sync App ($SyncMode)" -Action {
                    Sync-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Mode $SyncMode -Force -ErrorAction Stop
                }
                $targetApp = Get-ImportTenantAppInfo -AppId $appId -Version $app.Version
            }
            if (-not $targetApp -or $targetApp.SyncState -ne "Synced") {
                throw "App '$($app.Name)' version $($app.Version) was not synchronized"
            }

            $requiresDataUpgrade = ($installedApp -and [Version]$installedApp.Version -lt [Version]$app.Version) -or $targetApp.NeedsUpgrade -or
                ($targetApp.ExtensionDataVersion -and [Version]$targetApp.ExtensionDataVersion -lt [Version]$targetApp.Version)
            if ($requiresDataUpgrade) {
                Invoke-AppImportStep -Name "App Data Upgrade" -Action {
                    Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Force -ErrorAction Stop
                }
            }
            elseif (-not $targetApp.IsInstalled) {
                Invoke-AppImportStep -Name "Install App" -Action {
                    Install-NAVApp -ServerInstance $ServerInstance -Name $app.Name -Publisher $app.Publisher -Version $app.Version -Tenant $Tenant -Force -ErrorAction Stop
                }
            }

            $result = Get-ImportTenantAppInfo -AppId $appId -Version $app.Version
            if (-not $result -or -not $result.IsInstalled -or $result.SyncState -ne "Synced" -or $result.NeedsUpgrade -or
                ($result.ExtensionDataVersion -and [Version]$result.ExtensionDataVersion -lt [Version]$result.Version)) {
                throw "App '$($app.Name)' version $($app.Version) did not reach a synchronized, installed state with current tenant data"
            }
            foreach ($property in @("IsPublished", "IsInstalled", "SyncState", "NeedsUpgrade", "ExtensionDataVersion")) {
                $properties[$property] = $result.$property
            }
            Add-ArtifactsLog -kind App -message "App $($app.Name) $($app.Version) is installed and synchronized." -data $result
            Unpublish-OldAppVersion -OldApp $installedApp -AppId $appId -NewVersion ([Version]$app.Version)
            $success = $true
        }
        catch {
            Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Import App Artifact"
            Add-ArtifactsLog -kind App -message "Import App failed: $($_.Exception.Message)" -severity Error -success fail
            $PSCmdlet.WriteError($_)
        }
        finally {
            if ($success -and $IsModifiedBaseApp) {
                $env:cosmoBaseAppVersion = if ($installedApp -and [Version]$installedApp.Version -gt [Version]$app.Version) { $installedApp.Version } else { $app.Version }
            }
            Invoke-LogOperation -name "Import App Artifact" -started $started -properties $properties -success $success -telemetryClient $telemetryClient
            if ($groupStarted) { Write-Host "##[endgroup]" }
        }
    }

    end {
        if ($importFiles) {
            Add-ArtifactsLog -message "Import App Artifacts done. (Duration: $(New-TimeSpan -start $importStarted -end (Get-Date)))"
        }
    }
}
Export-ModuleMember -Function Import-AppArtifact