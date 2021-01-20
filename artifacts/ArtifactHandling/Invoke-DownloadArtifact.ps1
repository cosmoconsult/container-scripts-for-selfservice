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
        $folderIdx         = 0
        $rootFolder        = $destination
        $archive           = "$([System.IO.Path]::GetTempFileName()).zip"
        $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
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
        if (Test-Path "$archive" -ErrorAction SilentlyContinue) { Remove-Item "$archive" -Force -ErrorAction SilentlyContinue }

        $downlodUrl = $url
        if ("$downlodUrl" -eq "") {
            Add-ArtifactsLog -message "Get Artifact Version for $($name)..."
            $version = Get-PackageVersion `
                -organization    $organization `
                -project         $project `
                -feed            $feed `
                -name            $name `
                -scope           $scope `
                -view            $view `
                -protocolType    $protocolType `
                -accessToken     $accessToken `
                -telemetryClient $telemetryClient
                
            if ("$version" -eq "") {
                Add-ArtifactsLog -message "Artiact $name (View: '$view') skipped (no version / release found)" -severity Warn
                Invoke-LogEvent -name "Download Artifact - no Artifact found" -properties $properties -telemetryClient $telemetryClient
                $url     = ""
            } else {
                Add-ArtifactsLog -message "`Artifact $name (View: '$view') has Version v $version"

                $scope      = $scope
                if ("$scope" -eq "") { $scope = "project"}
                $project    = $project
                if ("$scope" -ne "project" -and "" -eq "$project") { $project = "dummy" }
                $downlodUrl = "$baseUrl/Artifact/$($organization)/$($project)/$($feed)/$($name)/$($version)?scope=$($scope)&pat=$($accessToken)"
            }
        }

        if ("$downlodUrl" -ne "") {
            if ($downlodUrl.StartsWith("http")) {
                $url_output = "$downlodUrl".replace('&pat=', "$([System.Environment]::NewLine)").split("$([System.Environment]::NewLine)")
                if ($url_output.Length -gt 1) {
                    Add-ArtifactsLog -message "Download Artifact from $($url_output[0])&pat=***"
                } else {
                    Add-ArtifactsLog -message "Download Artifact from $($downlodUrl)" 
                }
            } else {
                Add-ArtifactsLog -message "Get Artifact from $downlodUrl"
            }

            try {
                $started = Get-Date -Format "o"
                if ($downlodUrl.StartsWith("http")) {
                    $actionMessage = "downloaded"
                    try {
                        Invoke-WebRequest -Method Get -uri $downlodUrl -OutFile "$archive" -Headers $headers
                    } catch {
                        Invoke-WebRequest -Method Get -uri $downlodUrl -OutFile "$archive"
                    }
                } else {
                    $actionMessage = "copied"
                    if (! (Test-Path -Path $downlodUrl)) {
                        Add-ArtifactsLog -message "Artifact '$downlodUrl' does not exist" -severity Warn -success skip
                    } else {
                        Copy-Item -Path $downlodUrl -Destination "$archive"
                    }                    
                }

                if (Test-Path $archive) {
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

                    if ($downlodUrl.StartsWith("http") -or "$downlodUrl".EndsWith(".zip")) {
                        Add-ArtifactsLog -message "Extract Artifact $name v $version to $($folder)..."
                        Expand-Archive -Path $archive -DestinationPath "$folder" -Force
                    } else {
                        Add-ArtifactsLog -message "Copy Artifact '$downlodUrl' ($name v $version) to $($folder)..."
                        New-Item -ItemType Directory -Path "$folder" -ErrorAction SilentlyContinue -Force
                        Copy-Item -Path "$downlodUrl" -Destination "$folder" -Force
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
                    Add-ArtifactsLog -message "$((Get-ChildItem $folder -Recurse) | Select FullName, Length | Format-Table -AutoSize -Wrap:$false | Out-String -Width 1024)"

                    $success = $true
                } else {
                    Add-ArtifactsLog -message "No content $actionMessage from '$downlodUrl' to '$archive'" -severity Warn -success skip
                    $success = $false
                }

                $properties = @{"organization" = $organization; "project" = $project; "feed" = $feed; "name" = $name; "scope" = $scope; "view" = $view; "protocolType" = $type; "url" = $url_output}
                Invoke-LogOperation -name "Download Artifact" -success $success -started $started -properties $properties -telemetryClient $telemetryClient
            } catch { 
                Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -operation "Download Artifact"
            } finally {
                Remove-Item -Path $archive -Force -ErrorAction SilentlyContinue
                $downlodUrl = ""
            }
        } else {
            Add-ArtifactsLog -message "Artifact $name skipped - no Url found." -severity Warn -success skip
        }
    }
    
    end {
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifact