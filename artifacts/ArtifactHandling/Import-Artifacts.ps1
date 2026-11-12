function Import-Artifacts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [Alias("Folder", "TargetFolder")]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$NavServiceName,
        [Parameter(Mandatory = $false)]
        [string]$ServerInstance = "NAV",
        [Parameter(Mandatory = $false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory = $false)]
        [string]$DatabaseServer = "localhost\sqlexpress",
        [Parameter(Mandatory = $false)]
        [string]$OperationScope = "AdditionalSetup",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Add", "ForceSync")]
        [string]$SyncMode = "Add",
        [Parameter(Mandatory = $false)]
        [ValidateSet("Global", "Tenant", "Dev")]
        [string]$Scope = "Global",    
        [Parameter(Mandatory = $false)]
        [System.Object]$telemetryClient = $null,
        [Parameter(Mandatory = $false)]
        [bool]$SkipFontImport = $false,
        [Parameter(Mandatory = $false)]
        [bool]$ExcludeApps = $true,
        [Parameter(Mandatory = $false)]
        [string]$AppExcludeExpr = $env:AppExcludeExpr,
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
        $started = Get-Date -Format "o"
        $properties = @{ NavServiceName = $NavServiceName; ServerInstance = $ServerInstance; Tenant = $Tenant; Path = $Path; DatabaseServer = $DatabaseServer; SyncMode = $SyncMode }
    }
    
    process {
        $maxDepth = 4 # max recurse folder depth for searching Apps, FOBs, RIMs, ...

        if (!$ExcludeApps) {
            $AppExcludeExpr = ""
        }
        $appFiles = @()
        if (Test-Path -LiteralPath $Path) {
            Write-Host "Working on apps sorted by dependency"
            $appFiles = @(Get-AppFilesSortedByDependencies -Path $Path -Depth $maxDepth -Filter '*.app' -ExcludeExpr $AppExcludeExpr -ErrorAction $ErrorActionPreference)
        }
        else {
            Write-Error "Artifact path '$Path' does not exist"
            return
        }
        
        # Import FOBs
        $items = @()
        if (Test-Path -LiteralPath "$Path") {
            $items = @() + (Get-ChildItem -LiteralPath "$Path" -Filter "*.fob" -Recurse -Depth $maxDepth -ErrorAction SilentlyContinue)
        }
        if ($items) {
            try {
                $started = Get-Date -Format "o"
                Write-Host "Import $($items.Length) FOBs..."

                # Import all FOBs
                $items | Import-FobArtifact -NavServiceName $NavServiceName -ServerInstance $ServerInstance -Tenant $Tenant -DatabaseServer $DatabaseServer -telemetryClient $telemetryClient -SkipServiceRestartCheck:$SkipServiceRestartCheck -ErrorAction $ErrorActionPreference

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import FOBs" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import FOBs Error: $($_.Exception.Message)" -f Red  | Out-String
                $PSCmdlet.WriteError($_)
            }
            finally {
                Write-Host "Import FOBs done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        }
        else {
            Write-Host "No FOBs to import."
        }

        # Publish apps
        $items = $appFiles
        if ($items) {
            try {
                $started = Get-Date -Format "o"
                Write-Host "Import $($items.Length) Apps..."
                
                Add-ArtifactsLog -message "Install Apps:$([System.Environment]::NewLine)$($items | Format-Table -AutoSize -Wrap:$false | Out-String -Width 1024)"

                # Figure out whether we are also importing the Application app, as that might indicate that we are importing a modified base app. If yes, try to
                # identify the modified base app by looking at the dependencies 
                $modifiedBaseAppName = ""
                $applicationApp = $items | Where-Object { $_.Publisher -eq "4PS B.V." -and $_.Name -eq "Application" } | Select-Object -First 1
                if ($applicationApp) {
                    Write-Host "Found Application app: $($applicationApp.Path) - trying to identify modified base app..."
                    $applicationAppInfo = Get-NAVAppInfo -Path $applicationApp.Path -ErrorAction Stop
                    $modifiedBaseAppInfo = $applicationAppInfo.Dependencies | Where-Object { $_.Publisher -eq "4PS B.V." -and $_.Name.StartsWith("4PS Construct ") }
                    if ($modifiedBaseAppInfo -is [array]) {
                        throw "Multiple potential modified base apps found. Unable to choose."
                    }
                    elseif ($modifiedBaseAppInfo) {
                        Write-Host "Found modified base app: $($modifiedBaseAppInfo.Name)"
                        $modifiedBaseAppName = $modifiedBaseAppInfo.Name
                    }
                }
                
                # Import all Apps
                foreach ($item in $items) {
                    # Try to Find the App-Specific Import Scope stored during download in "artifact.json" (Global setup is used, when no app specific information are present in the parent folders)
                    $importScope = $Scope
                    $importSyncMode = $SyncMode
                    if (Test-Path -LiteralPath $item.Path) {
                        $artifactJson = Get-ArtifactJson -path $item.Path -ErrorAction SilentlyContinue
                        if ($artifactJson -and $artifactJson.appImportScope) {
                            $importScope = $artifactJson.appImportScope
                        }
                        if ($artifactJson -and $artifactJson.appImportSyncMode) {
                            $importSyncMode = $artifactJson.appImportSyncMode
                        }
                    }

                    $IsModifiedBaseApp = $item.Publisher -eq "4PS B.V." -and $item.Name -eq $modifiedBaseAppName
                        
                    $importParameters = @{
                        ServerInstance = $ServerInstance
                        Tenant = $Tenant
                        DatabaseServer = $DatabaseServer
                        Scope = $importScope
                        SyncMode = $importSyncMode
                        telemetryClient = $telemetryClient
                        ErrorAction = $ErrorActionPreference
                        IsModifiedBaseApp = $IsModifiedBaseApp
                        PublicDnsName = $PublicDnsName
                        ContainerId = $ContainerId
                        ContainerUser = $ContainerUser
                        ContainerPassword = $ContainerPassword
                        SkipServiceRestartCheck = $SkipServiceRestartCheck
                    }
                    @($item) | Import-AppArtifact @importParameters
                }                

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import Apps" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import Apps Error: $($_.Exception.Message)" -f Red
                $PSCmdlet.WriteError($_)
            }
            finally {
                Write-Host "Import Apps done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        }
        else {
            Write-Host "No Apps to import."
        }

        # Import RapidStart packages
        $items = @()
        if (Test-Path -LiteralPath "$Path") {
            $items = @() + (Get-ChildItem -LiteralPath "$Path" -Depth $maxDepth -Filter "*.rapidstart" -Recurse -ErrorAction SilentlyContinue)
        }
        if ($items) {
            try {
                $started = Get-Date -Format "o"
                Write-Host "Import $($items.Length) RapidStart packages..."

                # Import all RIMs
                $items | Import-RIMArtifact -ServerInstance $ServerInstance -Tenant $Tenant -telemetryClient $telemetryClient -SkipServiceRestartCheck:$SkipServiceRestartCheck -ErrorAction $ErrorActionPreference

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import RapidStart Packages" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import RapidStart packages Error: $($_.Exception.Message)" -f Red
                $PSCmdlet.WriteError($_)
            }
            finally {
                Write-Host "Import RapidStart packages done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        }
        else {
            Write-Host "No RapidStart packages to import."
        }

        # Import Fonts
        $items = @()
        $fontPaths = @(@($Path, 'c:/fonts') | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -Unique)
        if (-not $SkipFontImport) {
            $items = @($fontPaths | ForEach-Object {
                Get-ChildItem -LiteralPath $_ -Recurse -File -Depth $maxDepth -ErrorAction Stop |
                    Where-Object { $_.Extension -in @('.fon', '.fnt', '.ttf', '.ttc', '.otf') }
            })
        }
        if ($items) {
            try {
                $started = Get-Date -Format "o"
                Write-Host "Import $($items.Length) Fonts..."
                # Import all Fonts
                Import-Fonts -Path $items.FullName -NavServiceName $NavServiceName -ServerInstance $ServerInstance -Tenant $Tenant -telemetryClient $telemetryClient -ErrorAction $ErrorActionPreference

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import Fonts" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import Fonts Error: $($_.Exception.Message)" -f Red  | Out-String
                $PSCmdlet.WriteError($_)
            }
            finally {
                Write-Host "Import Fonts done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        }
        else {
            Write-Host "No Fonts to import."
        }
    }
    
    end {
        Invoke-LogOperation -name "$OperationScope - Import Artifacts" -started $started -properties $properties -telemetryClient $telemetryClient
    }
}
Export-ModuleMember -Function Import-Artifacts
