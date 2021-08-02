function Invoke-DownloadArtifact {
    [CmdletBinding()]
    param (
        # Artifact Parameter
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$organization  = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$project       = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$feed          = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$name          = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$protocolType  = "upack",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$view          = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$version       = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$scope         = "project",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$url           = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$target        = "",        
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$targetFolder  = "",
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [string]$appImportScope = "",
        # Download Parameter
        [Parameter(Mandatory=$false)]
        [string]$destination   = "$($env:TEMP)/$([System.IO.Path]::GetRandomFileName())",
        [Parameter(Mandatory=$false)]
        [string]$baseUrl       = "https://ppi-devops.germanywestcentral.cloudapp.azure.com/proxy",
        [Parameter(Mandatory=$false)]
        [Alias("pat")]
        [string]$accessToken   = "$($env:AZURE_DEVOPS_EXT_PAT)",
        [Parameter(Mandatory=$false)]
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        Write-Host "url: $url"
        $folderIdx         = 0
        $rootFolder        = $destination
        $tempArchive       = "$([System.IO.Path]::GetTempFileName()).zip"
        $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service" -ErrorAction SilentlyContinue).FullName
        if (! $serviceTierFolder) {
            Add-ArtifactsLog -message "Service Tier Folder not found at 'C:\Program Files\Microsoft Dynamics NAV\*\Service'" -severity Warn
        }
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        if ("$url" -eq "") {
            # Validate or get the PAT, becasue no Download URL is present
            if ("$accessToken" -eq "") {
                # Try get the PAT from environment
                $accessToken = (@("$($env:AZURE_DEVOPS_TOKEN)", "$($env:AZURE_DEVOPS_EXT_PAT)", "$($env:AZP_TOKEN)") | ? { "$_" -ne ""} | select -First 1)            
            }
            if ("$accessToken" -eq "") {
                # Try to convert PAT from Base64, because it is stored in environment
                $accessToken64 = (@("$($env:AZURE_DEVOPS_TOKEN64)", "$($env:AZURE_DEVOPS_EXT_PAT64)", "$($env:AZP_TOKEN64)", "$($env:AZURE_DEVOPS_PAT64)") | ? { "$_" -ne ""} | select -First 1)
                if ("" -ne "$accessToken64" -and "" -eq "$accessToken") {
                    try {
                        $accessToken = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String("$accessToken64"))
                    } catch {}                    
                }
                if ("" -ne "$accessToken64" -and "" -eq "$accessToken") {
                    try {
                        $accessToken = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String("$accessToken64"))
                    } catch {}
                }
            }
            if ("" -eq "$accessToken") {
                Add-ArtifactsLog -message "PAT not present" -severity Warn
            }
        }
        $headers = @{ "Authorization" = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("vsts:$($accessToken)")))"; }
        # Ensure TSL12
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12                
    }
    
    process {
        # Download from given URL
        if (Test-Path "$tempArchive" -ErrorAction SilentlyContinue) { Remove-Item "$tempArchive" -Force -ErrorAction SilentlyContinue }

        $sourceUri = $url
        if ("$sourceUri" -eq "") {
            $artifactVersion = $version
            if ("$artifactVersion" -ne "") {
                Add-ArtifactsLog -message "Get Artifact Version for $($name) ... skipped, because version is set to v $($artifactVersion)"
            } else {
                Add-ArtifactsLog -message "Get Artifact Version for $($name)..."
                $artifactVersion = Get-PackageVersion `
                    -organization    $organization `
                    -project         $project `
                    -feed            $feed `
                    -name            $name `
                    -scope           $scope `
                    -view            $view `
                    -protocolType    $protocolType `
                    -accessToken     $accessToken `
                    -telemetryClient $telemetryClient
            } 

            if ("$artifactVersion" -eq "") {
                Add-ArtifactsLog -message "Artiact $name (View: '$view') skipped (no version / release found)" -severity Warn
                Invoke-LogEvent -name "Download Artifact - no Artifact found" -properties $properties -telemetryClient $telemetryClient
                $url     = ""
            } else {
                Add-ArtifactsLog -message "`Artifact $name (View: '$view') has Version v $artifactVersion"

                $scope      = $scope
                if ("$scope" -eq "") { $scope = "project"}
                $project    = $project
                if ("$scope" -ne "project" -and "" -eq "$project") { $project = "dummy" }
                $sourceUri  = "$baseUrl/Artifact/$($organization)/$($project)/$($feed)/$($name)/$($artifactVersion)?scope=$($scope)&pat=$($accessToken)"
            }
        }

        $isDownload = "$sourceUri".StartsWith("http")
        $isArchive  = $isDownload -or "$sourceUri".EndsWith(".zip")
        Write-Host "status: $sourceUri $isDownload $isArchive"
        Test-Path $sourceUri
        if ("$sourceUri" -ne "") {
            if ($isDownload) {
                $url_output = "$sourceUri".replace('&pat=', "$([System.Environment]::NewLine)").split("$([System.Environment]::NewLine)")
                if ($url_output.Length -gt 1) {
                    Add-ArtifactsLog -message "Download Artifact from $($url_output[0])&pat=***"
                } else {
                    Add-ArtifactsLog -message "Download Artifact from $($sourceUri)"
                }
            } else {
                Add-ArtifactsLog -message "Get Artifact from $sourceUri"
            }

            try {
                $started = Get-Date -Format "o"
                if ("$sourceUri".StartsWith("http")) {  
                    try {
                        Invoke-WebRequest -Method Get -uri $sourceUri -OutFile "$tempArchive" -Headers $headers
                    } catch {
                        Invoke-WebRequest -Method Get -uri $sourceUri -OutFile "$tempArchive"
                    }
                } else {
                    if (Test-Path $sourceUri) {
                        Add-ArtifactsLog -message "Get Artifact from $sourceUri"
                    } else {
                        Add-ArtifactsLog -message "No Artifact found at $sourceUri"
                    }                    
                }

                if ($isDownload) {
                    $archive = $tempArchive
                } elseif ($isArchive) {
                    $archive = $sourceUri
                } else {
                    $archive = ""
                }

                if (($archive -and (Test-Path $archive)) -or ($sourceUri -and (Test-Path $sourceUri))) {
                    # Setup correct folder
                    $folderIdx = $folderIdx + 1
                    if ("$targetFolder" -eq "") {
                        $folderSuffix = "$($folderIdx.ToString().PadLeft(3, '0'))"                        
                    } else {
                        $folderSuffix = "$targetFolder"
                    }
                    $folder    = Join-Path $rootFolder "$folderSuffix"

                    # Overrule the Target Folder, when a special target (app, dll, font) is set
                    switch ("$target".ToLower()) {
                        "dll"     { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        "add-ins" { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        #"app"     { $folder = "c:/apps" }
                        "font"    { $folder = "c:/fonts" }
                        "fonts"   { $folder = "c:/fonts" }
                    }

                    if ($isArchive) {
                        Add-ArtifactsLog -message "Extract Artifact $name v $artifactVersion to $($folder)..."
                        Expand-Archive -Path "$archive" -DestinationPath "$folder" -Force
                    } else {
                        Add-ArtifactsLog -message "Copy Artifact '$sourceUri' ($name v $artifactVersion) to $($folder)..."
                        New-Item -ItemType Directory -Path "$folder" -ErrorAction SilentlyContinue -Force
                        Copy-Item -Path "$sourceUri" -Destination "$folder" -Force
                    }
                    if ($appImportScope) {
                        # Store the Artifact Specific Import Scope Information
                        $artifactJson = Get-ChildItem -LiteralPath "$folder" -Filter "artifact.json" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 | Get-Content -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue
                        if (! $artifactJson) { $artifactJson = ConvertFrom-Json "{}" }
                        $artifactJson  | add-member -Name "appImportScope" -value "$appImportScope" -MemberType NoteProperty -ErrorAction Ignore
                        $artifactJson.appImportScope = $appImportScope
                        $artifactJson | ConvertTo-Json -Depth 50 -ErrorAction SilentlyContinue | Set-Content -LiteralPath "$folder/artifact.json" -ErrorAction SilentlyContinue
                    }
                    Add-ArtifactsLog -message "  Downloaded Files ($folder):"
                    Add-ArtifactsLog -message "$((Get-ChildItem $folder -Recurse) | Select-Object FullName, Length | Format-Table -AutoSize -Wrap:$false | Out-String -Width 1024)"

                    $success = $true
                } else {
                    Add-ArtifactsLog -message "No content available from source: '$sourceUri'" -severity Warn -success skip
                    $success = $false
                }

                $properties = @{"organization" = $organization; "project" = $project; "feed" = $feed; "name" = $name; "scope" = $scope; "view" = $view; "protocolType" = $type; "url" = $url_output}
                Invoke-LogOperation -name "Download Artifact" -success $success -started $started -properties $properties -telemetryClient $telemetryClient
            } catch { 
                Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -operation "Download Artifact"
            } finally {
                if (Test-Path $tempArchive) {
                    Remove-Item -Path $tempArchive -Force -ErrorAction SilentlyContinue
                }
                $sourceUri = ""
            }
        } else {
            Add-ArtifactsLog -message "Artifact $name skipped - no Url found." -severity Warn -success skip
        }
    }
    
    end {
        $artifactVersion = ""
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifact