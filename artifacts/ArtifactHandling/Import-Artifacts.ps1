function Import-Artifacts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [Alias("Folder", "TargetFolder")]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$NavServiceName,
        [Parameter(Mandatory=$false)]
        [string]$ServerInstance = "NAV",
        [Parameter(Mandatory=$false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory=$false)]
        [string]$DatabaseServer = "localhost\sqlexpress",
        [Parameter(Mandatory=$false)]
        [string]$OperationScope = "AdditionalSetup",
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
        $started    = Get-Date -Format "o"
        $properties = @{ NavServiceName = $NavServiceName; ServerInstance = $ServerInstance; Tenant = $Tenant; Path = $Path; DatabaseServer = $DatabaseServer; SyncMode = $SyncMode }
    }
    
    process {
        $maxDepth = 4 # max recurse folder depth for searching Apps, FOBs, RIMs, ...
        
        # Import FOBs
        $items = @()
        if (Test-Path -LiteralPath "$Path") {
            $items = @() + (Get-ChildItem -LiteralPath "$Path" -Filter "*.fob" -Recurse -Depth $maxDepth -ErrorAction SilentlyContinue)
        }
        if ($items) {
            try {
                $started   = Get-Date -Format "o"
                Write-Host "Import $($items.Length) FOBs..."

                # Import all FOBs
                $items | Import-FobArtifact -NavServiceName $NavServiceName -ServerInstance $ServerInstance -Tenant default -telemetryClient $telemetryClient -ErrorAction SilentlyContinue

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import FOBs" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import FOBs Error: $($_.Exception.Message)" -f Red  | Out-String
            }
            finally {
                Write-Host "Import FOBs done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        } else {
            Write-Host "No FOBs to import."
        }

        # Publish apps
        $items = @()
        $params = @{
            Depth = $maxDepth
            Filter = "*.app"            
        }
        if ($null -ne $env:AppExcludeExpr)
        {
            Write-Host ("Found App expression override {0}" -f $env:AppExcludeExpr)
            $params.Add("ExcludeExpr", $env:AppExcludeExpr)   
        }
        if (Test-Path -LiteralPath "$Path") {
            $params.Add("Path", "$Path")
            Write-Host "Working on apps sorted by dependency"
            $items = @() + (Get-AppFilesSortedByDependencies @params -ErrorAction SilentlyContinue)
        }
        if ($items) {
            try {
                $started   = Get-Date -Format "o"
                Write-Host "Import $($items.Length) Apps..."
                
                Add-ArtifactsLog -message "Install Apps:$([System.Environment]::NewLine)$($items | Format-Table -AutoSize -Wrap:$false | Out-String -Width 1024)" -data $app

                # Import all Apps
                foreach ($item in $items) {
                    # Try to Find the App-Specific Import Scope stored during download in "artifact.json" (Global setup is used, when no app specific information are present in the parent folders)
                    $importScope = $Scope
                    if (Test-Path -Path $item.Path) {
                        $artifactJson = Get-ArtifactJson -path $item.Path -ErrorAction SilentlyContinue
                        if ($artifactJson -and $artifactJson.appImportScope) {
                            $importScope = $artifactJson.appImportScope
                        }
                    }

                    $IsModifiedBaseApp = $item.Path.IndexOf("sortorder01") -gt -1
                        
                    @($item) | Import-AppArtifact -ServerInstance $ServerInstance -Tenant default -Scope $importScope -SyncMode $SyncMode -telemetryClient $telemetryClient -ErrorAction SilentlyContinue -IsModifiedBaseApp:$IsModifiedBaseApp
                }                

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import Apps" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import Apps Error: $($_.Exception.Message)" -f Red
            }
            finally {
                Write-Host "Import Apps done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        } else {
            Write-Host "No Apps to import."
        }

        # Import RapidStart packages
        $items = @()
        if (Test-Path -LiteralPath "$Path") {
            $items = @() + (Get-ChildItem -LiteralPath "$Path" -Depth $maxDepth -Filter "*.rapidstart" -Recurse -ErrorAction SilentlyContinue)
        }
        if ($items) {
            try {
                $started   = Get-Date -Format "o"
                Write-Host "Import $($items.Length) RapidStart packages..."

                # Import all RIMs
                $items | Import-RIMArtifact -ServerInstance $ServerInstance -Tenant default -telemetryClient $telemetryClient -ErrorAction SilentlyContinue

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import RapidStart Packages" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import RapidStart packages Error: $($_.Exception.Message)" -f Red
            }
            finally {
                Write-Host "Import RapidStart packages done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        } else {
            Write-Host "No RapidStart packages to import."
        }
        # Import Fonts
        $items = @()
        if (Test-Path -LiteralPath "c:/fonts") {
            $items = @() + (Get-ChildItem -LiteralPath "c:/fonts" -Recurse -Depth $maxDepth -ErrorAction SilentlyContinue)
        }
        if ($items) {
            try {
                $started   = Get-Date -Format "o"
                Write-Host "Import $($items.Length) Fonts..."
                # Import all Fonts
                Import-Fonts -telemetryClient $telemetryClient -ErrorAction SilentlyContinue

                $properties["files"] = ($items | ForEach-Object { $_.FullName } | ConvertTo-Json -ErrorAction SilentlyContinue)
                Invoke-LogOperation -name "$OperationScope - Import Fonts" -started $started -telemetryClient $telemetryClient -properties $properties
            }
            catch {
                Write-Host "Import Fonts Error: $($_.Exception.Message)" -f Red  | Out-String
            }
            finally {
                Write-Host "Import Fonts done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        } else {
            Write-Host "No Fonts to import."
        }
    }
    
    end {
        Invoke-LogOperation -name "$OperationScope - Import Artifacts" -started $started -properties $properties -telemetryClient $telemetryClient
    }
}
Export-ModuleMember -Function Import-Artifacts