function Invoke-DownloadArtifact {
    [CmdletBinding()]
    param (
        # Artifact Parameter
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$organization = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$project = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$feed = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$name = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$type = "upack",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$view = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$version = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$scope = "project",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$url = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$target = "",        
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$targetFolder = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$appImportScope = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$pat = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string[]]$cosmoArtifactType = @(),
        # Download Parameter
        [Parameter(Mandatory = $false)]
        [string]$destination = "$($env:TEMP)/$([System.IO.Path]::GetRandomFileName())",
        [Parameter(Mandatory = $false)]
        [string]$baseUrl = "https://$($env:publicdnsname)",
        [Parameter(Mandatory = $false)]
        [string]$accessToken = "$($env:AZURE_DEVOPS_EXT_PAT)",
        # Async Parameter
        [Parameter(Mandatory = $false)]
        [string]$apiFeatures = $null,
        [Parameter(Mandatory = $false)]
        [string]$serviceTierFolder = $null,
        [Parameter(Mandatory = $false)]
        [int]$folderIdx = 0
    )
    
    begin {
        if ($null -eq $serviceTierFolder) {
            $serviceTierFolder = "$((Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service" -ErrorAction SilentlyContinue).FullName)"
            if (! $serviceTierFolder) {
                Write-Warning "Service Tier Folder not found at 'C:\Program Files\Microsoft Dynamics NAV\*\Service'"
            }
        }

        if ((! $AccessToken) -and ($Artifact | Where-Object { ! $_.url })) {
            # Validate or get the PAT, because artifact without Download URL is present
            if (! $AccessToken) {
                # Try get the PAT from environment
                $AccessToken = @($env:AZURE_DEVOPS_TOKEN, $env:AZURE_DEVOPS_EXT_PAT, $env:AZP_TOKEN) | 
                    Where-Object { $_ } | 
                    Select-Object -First 1
            }
            if (! $AccessToken) {
                # Try to convert PAT from Base64, because it is stored in environment
                $accessToken64 = @($env:AZURE_DEVOPS_TOKEN64, $env:AZURE_DEVOPS_EXT_PAT64, $env:AZP_TOKEN64, $env:AZURE_DEVOPS_PAT64) | 
                    Where-Object { $_ } | 
                    Select-Object -First 1
                if (! $accessToken64) {
                    try {
                        $AccessToken = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String("$accessToken64"))
                    }
                    catch {}

                    if (! $AccessToken) {
                        try {
                            $AccessToken = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String("$accessToken64"))
                        }
                        catch {}
                    }
                }
            }
            if (! $AccessToken) {
                Write-Warning "PAT not present"
            }
        }

        if ($null -eq $ApiFeatures) {
            try {
                $apiFeaturesResult = Invoke-WebRequest -Method Get -uri "$BaseUrl/api/automation/release/Features" -UseBasicParsing
                if ($apiFeaturesResult.StatusCode -eq 200) {
                    $apiFeatures = ConvertFrom-Json $apiFeaturesResult.Content
                }
            }
            catch {}
        }

        if ("$baseUrl" -eq "https://" -or "$baseUrl".ToLower() -contains "localhost") {
            $baseUrl = "https://cosmo-alpaca-enterprise.westeurope.cloudapp.azure.com"
        }

        $headers = @{ "Authorization" = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($accessToken)")))"; }
        # Ensure TSL12
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12                

        $rootFolder = $destination
        $tempArchive = "$([System.IO.Path]::GetTempFileName()).zip"
        
        $tempFolder = [System.IO.Path]::GetTempFileName()
        if (Test-Path $tempFolder) { Remove-Item $tempFolder }
        New-Item -Path $tempFolder -ItemType "Directory" | Out-Null

        $getVersionFromAPI = $ApiFeatures -contains "GetArtifactLatest"
    }
    
    process {
        # check restart
        if (($env:cosmoServiceRestart -eq $true) -and @("bak", "saasbak", "fob", "app", "rapidstart", "").Contains("$target".ToLower())) {
            Write-Host "Skipping $target download because this seems to be a service restart"
            return
        }

        # Download from given URL
        if (Test-Path "$tempArchive" -ErrorAction SilentlyContinue) { Remove-Item "$tempArchive" -Force -ErrorAction SilentlyContinue }

        $sourceUri = $url
        if ("$sourceUri" -eq "") {
            if ("$pat" -eq "") {
                $pat = $accessToken
            }
            if (($type -eq "upack") -OR (!$type)) {
                $artifactVersion = $version
                if (!$getVersionFromAPI) {
                    if ("$artifactVersion" -ne "") {
                        Write-Host "Get Artifact Version for $($name)... skipped, because version is set to v $($artifactVersion)"
                    }
                    else {
                        Write-Host "Get Artifact Version for $($name)..."
                        $artifactVersion = Get-PackageVersion `
                            -organization    $organization `
                            -project         $project `
                            -feed            $feed `
                            -name            $name `
                            -scope           $scope `
                            -view            $view `
                            -protocolType    $type `
                            -accessToken     $pat `
                            -artifactVersion $artifactVersion
                    }
                }
                else {
                    Write-Host "Get Artifact $($name)..."
                }

                if ("$artifactVersion" -eq "" -and !$getVersionFromAPI) {
                    Write-Warning "Artifact $name (View: '$view') skipped (no version / release found)"
                    New-EventTelemetry -name "Download Artifact - no Artifact found" -properties $properties
                    $url = ""
                }
                else {
                    if (!$getVersionFromAPI) {
                        Write-Host "`Artifact $name (View: '$view') has Version v $artifactVersion"
                    }

                    $scope = $scope
                    if ("$scope" -eq "") { $scope = "project" }
                    $project = $project
                    if ("$scope" -ne "project" -and "" -eq "$project") { $project = "dummy" }
                    $sourceUri = "$baseUrl/api/automation/release/Artifact/$($organization)/$($project)/$($feed)/$($name)/$($artifactVersion)?PATValidationProject=$($env:CcOrgName)&scope=$($scope)&view=$($view)&pat=$($pat)"
                }
            }
            elseif ($type -eq "nuget") {
                Import-NugetTools
                Write-Host "Download $name from nuget feed" 
                Download-BcNuGetPackageToFolder -packageName $name -folder $tempFolder

                foreach ($file in Get-ChildItem -Path $tempFolder -Recurse) {
                    if ($file.Name -like "*.app") {
                        Invoke-DownloadArtifact -name $file.Name -url $file.FullName -target $target -destination $destination
                    }
                }
                $success = $true
                return
            }
        }

        $isDownload = "$sourceUri".StartsWith("http")
        $isArchive = $isDownload -or "$sourceUri".EndsWith(".zip")
        if ("$sourceUri" -ne "") {
            if ($isDownload) {
                $url_output = "$sourceUri".replace('&pat=', "$([System.Environment]::NewLine)").split("$([System.Environment]::NewLine)")
                if ($url_output.Length -gt 1) {
                    Write-Host "Download Artifact from $($url_output[0])&pat=***"
                }
                else {
                    Write-Host "Download Artifact from $($sourceUri)"
                }
            }
            else {
                Write-Host "Copy Artifact from $sourceUri"
            }

            try {
                $started = Get-Date -Format "o"
                if ($isDownload) { 
                    if ("$sourceUri".StartsWith("$baseUrl")) {
                        Invoke-WebRequest -Method Get -uri $sourceUri -OutFile "$tempArchive" -Headers $headers
                    }
                    else {
                        Write-Debug "External artifact URL detected, ignoring Authorization header"
                        Invoke-WebRequest -Method Get -uri $sourceUri -OutFile "$tempArchive"
                    }
                }
                else {
                    if (Test-Path $sourceUri) {
                        Write-Host "Found Artifact at $sourceUri"
                    }
                    else {
                        Write-Host "No Artifact found at $sourceUri"
                    }                    
                }

                if ($isDownload) {
                    $archive = $tempArchive
                }
                elseif ($isArchive) {
                    $archive = $sourceUri
                }
                else {
                    $archive = ""
                }

                if (($archive -and (Test-Path $archive)) -or ($sourceUri -and (Test-Path $sourceUri))) {
                    # Setup correct folder
                    $folderIdx = $folderIdx + 1
                    if ("$targetFolder" -eq "") {
                        if ($name.StartsWith("sortorder")) {
                            $folderSuffix = $name.Split(" ")[0]
                        }
                        else {
                            $folderSuffix = "$($folderIdx.ToString().PadLeft(3, '0'))"                        
                        }
                    }
                    else {
                        $folderSuffix = "$targetFolder"
                    }
                    $folder = Join-Path $rootFolder "$folderSuffix"

                    # Overrule the Target Folder, when a special target (app, dll, font) is set
                    switch ("$target".ToLower()) {
                        "dll" { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        "add-ins" { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        #"app"     { $folder = "c:/apps" }
                        "font" { $folder = "c:/fonts" }
                        "fonts" { $folder = "c:/fonts" }
                        "demodata" { $folder = "c:/demodata" }
                    }

                    if ($isArchive) {
                        Write-Host "Extract Artifact $name v $artifactVersion to $($folder)..."
                        Expand-Archive -Path "$archive" -DestinationPath "$folder" -Force 
                        if ($cosmoArtifactType.Count -gt 0) {
                            Write-Host "Artifact has type selection: $([string]::Join(",", $cosmoArtifactType))"
                            $subfolders = Get-ChildItem -Path "$folder" -Directory
                            $subfolders | ForEach-Object {
                                if (-not $cosmoArtifactType.Contains($_.Name)) {
                                    Write-host "Artifact has subfolder $($_.Name), which doesn't exist in type selection, therefore removing it: $($_.FullName)"
                                    Remove-Item -Force -Recurse -Path $_.FullName
                                }
                            }
                        }
                    }
                    else {
                        Write-Host "Copy Artifact '$sourceUri' ($name v $artifactVersion) to $($folder)..."
                        New-Item -ItemType Directory -Path "$folder" -ErrorAction SilentlyContinue -Force | Out-Null
                        Copy-Item -Path "$sourceUri" -Destination "$folder" -Force
                    }
                    if ($appImportScope) {
                        # Store the Artifact Specific Import Scope Information
                        $artifactJson = Get-ChildItem -LiteralPath "$folder" -Filter "artifact.json" -Recurse -ErrorAction SilentlyContinue | 
                            Select-Object -First 1 | 
                            Get-Content -ErrorAction SilentlyContinue | 
                            ConvertFrom-Json -ErrorAction SilentlyContinue
                        if (! $artifactJson) { $artifactJson = ConvertFrom-Json "{}" }
                        $artifactJson  | 
                            add-member -Name "appImportScope" -value "$appImportScope" -MemberType NoteProperty -ErrorAction Ignore
                        $artifactJson.appImportScope = $appImportScope
                        $artifactJson | 
                            ConvertTo-Json -Depth 50 -ErrorAction SilentlyContinue | 
                            Set-Content -LiteralPath "$folder/artifact.json" -ErrorAction SilentlyContinue
                    }
                    Write-Host "  Downloaded Files ($folder):"
                    Write-Host "$((Get-ChildItem $folder -Recurse) | 
                        Select-Object FullName, Length | 
                        Format-Table -AutoSize -Wrap:$false | 
                        Out-String -Width 1024)"

                    $success = $true
                }
                else {
                    Write-Warning "No content available from source: '$sourceUri'" #TODO: success: skip
                    $success = $false
                }

                $properties = @{"organization" = $organization; "project" = $project; "feed" = $feed; "name" = $name; "scope" = $scope; "view" = $view; "protocolType" = $type; "url" = $url_output }
                New-RequestTelemetry -name "Download Artifact" -success $success -started $started -properties $properties
            }
            catch { 
                $errorMessage = $_.ToString()
                # Try to parse the JSON object from the error message and extract the details
                if ($errorMessage -match '{.*}') {
                    try {
                        $jsonError = $errorMessage | ConvertFrom-Json
                        if ($jsonError.detail) {
                            $errorMessage = $($jsonError.detail)
                        }
                    }
                    catch { }
                }

                Write-Error "Download Artifact $($name) failed: $($errorMessage)"
                New-ExceptionTelemetry -exception $_.Exception -properties $properties
            }
            finally {
                if (Test-Path $tempArchive) {
                    Remove-Item -Path $tempArchive -Force -ErrorAction SilentlyContinue
                }
                $sourceUri = ""
            }
        }
        else {
            Write-Warning "Artifact $name skipped - no Url found." #TODO: success: skip
        }
    }
    
    end {
        $artifactVersion = ""
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifact