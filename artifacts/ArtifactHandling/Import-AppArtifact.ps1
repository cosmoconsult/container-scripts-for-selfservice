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
        [string]$PublicDnsName = "",
        [string]$ContainerId = "",
        [string]$ContainerUser = "",
        [string]$ContainerPassword = "",
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

            $apps = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Id $AppId -Tenant $Tenant -TenantSpecificProperties -ErrorAction Stop)
            if ($Version) {
                return $apps | Where-Object { [Version]$_.Version -eq $Version } | Select-Object -First 1
            }
            return $apps
        }

        function Invoke-AppImportStep {
            param ([string]$Name, [scriptblock]$Action)

            $stepStarted = Get-Date -Format "o"
            $stepSuccess = $false
            try {
                Add-ArtifactsLog -kind App -message "$Name $($app.Name) $($app.Publisher) $($app.Version)..." -data $app
                try {
                    & $Action | Out-Null
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
                    if ([string]::IsNullOrWhiteSpace($PublicDnsName) -or [string]::IsNullOrWhiteSpace($ContainerId) -or
                        [string]::IsNullOrWhiteSpace($ContainerUser) -or [string]::IsNullOrWhiteSpace($ContainerPassword)) {
                        throw "Dev deployment requires PublicDnsName, ContainerId, ContainerUser, and ContainerPassword"
                    }
                    if ([Uri]::CheckHostName($PublicDnsName) -eq [UriHostNameType]::Unknown) {
                        throw "PublicDnsName must be a hostname without a scheme or path"
                    }
                    $schemaUpdateMode = if ($SyncMode -eq "ForceSync") { "forcesync" } else { "synchronize" }
                    $endpoint = "https://$PublicDnsName/$([Uri]::EscapeDataString($ContainerId))dev/dev/apps?SchemaUpdateMode=$schemaUpdateMode&tenant=$([Uri]::EscapeDataString($Tenant))"
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
                        $credentials = [System.Text.Encoding]::UTF8.GetBytes("${ContainerUser}:$ContainerPassword")
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
                if (-not $needsUpgrade -and -not $hasNewerData -and $installedApp.SyncState -eq "Synced" -and
                    ([Version]$installedApp.Version -gt [Version]$app.Version -or $SyncMode -ne "ForceSync")) {
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

            if ($SyncMode -eq "ForceSync" -or $targetApp.SyncState -ne "Synced") {
                if ($SyncMode -eq "ForceSync" -and $installedApp) {
                    Invoke-AppImportStep -Name "Uninstall App for ForceSync" -Action {
                        Uninstall-NAVApp -ServerInstance $ServerInstance -Name $installedApp.Name -Publisher $installedApp.Publisher -Version $installedApp.Version -Tenant $Tenant -Force -ErrorAction Stop
                    }
                }
                Invoke-AppImportStep -Name "Sync App" -Action {
                    # The sync of dependencies with mode Add as standard - Forcesync could damage the schema of dependencies - is this right Ole?
                    Sync-AppDependencies -App $app -ServerInstance $ServerInstance -Tenant $Tenant -SyncMode Add
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