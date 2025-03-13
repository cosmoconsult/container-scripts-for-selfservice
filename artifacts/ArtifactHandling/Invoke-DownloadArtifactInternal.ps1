function Invoke-DownloadArtifactInternal {
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
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$dependsOn = "",

        # Download Parameter
        [Parameter(Mandatory = $false)]
        [string]$destination = "$($env:TEMP)/$([System.IO.Path]::GetRandomFileName())",
        [Parameter(Mandatory = $false)]
        [switch]$groupByDependency = $false,
        [Parameter(Mandatory = $false)]
        [string]$baseUrl = "https://$($env:publicdnsname)",
        [Parameter(Mandatory = $false)]
        [string]$accessToken = "$($env:AZURE_DEVOPS_EXT_PAT)",
        [Parameter(Mandatory = $false)]
        [string[]]$apiFeatures = @(),
        [Parameter(Mandatory = $false)]
        [string]$serviceTierFolder,
        [Parameter(Mandatory = $false)]
        [int]$folderIdx = 0
    )
    
    begin {
        . c:\run\Prompt.ps1 -silent

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

        $getVersionFromAPI = $apiFeatures -contains "GetArtifactLatest"

        $nugetParams = $null
    }
    
    process {
        # check restart
        if (($env:cosmoServiceRestart -eq $true) -and @("bak", "saasbak", "fob", "app", "rapidstart", "").Contains("$target".ToLower())) {
            New-ArtifactsLogEntry -Message "Skipping $target download because this seems to be a service restart" -Success Skip
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
                        New-ArtifactsLogEntry -Message "Get Artifact Version for $($name)... skipped, because version is set to v $($artifactVersion)" -Success Skip
                    }
                    else {
                        New-ArtifactsLogEntry -Message "Get Artifact Version for $($name)..."
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
                    New-ArtifactsLogEntry -Message "Get Artifact $($name)..."
                }

                if ("$artifactVersion" -eq "" -and !$getVersionFromAPI) {
                    New-ArtifactsLogEntry -Message "Artifact $name (View: '$view') skipped (no version / release found)" -Severity Warn -Success Skip
                    New-EventTelemetry -Name "Download Artifact - no Artifact found" -Properties $properties
                    $url = ""
                }
                else {
                    if (!$getVersionFromAPI) {
                        New-ArtifactsLogEntry -Message "`Artifact $name (View: '$view') has Version v $artifactVersion"
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
                New-ArtifactsLogEntry -Message "Download $name from nuget feed" 

                if (! $nugetParams) {
                    $nugetParams = @{
                        installedPlatform = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
                        installedApps     = @()
                    }
                    # Collect already downloaded apps
                    Get-ChildItem -Path $destination -Filter '*.app' -Recurse |
                        ForEach-Object { Get-NavAppInfo -Path $_.FullName } |
                        ForEach-Object {
                            $nugetParams.installedApps += [PSCustomObject]@{
                                Name      = $_.Name
                                Publisher = $_.Publisher
                                id        = $_.AppId
                                Version   = $_.version
                            }
                        }
                }
                
                Download-BcNuGetPackageToFolder -packageName $name `
                                                -folder $tempFolder `
                                                -version $version `
                                                -downloadDependencies 'allButMicrosoft' `
                                                -select 'EarliestMatching' `
                                                @nugetParams

                Get-ChildItem -Path $tempFolder -Filter '*.app' -Recurse |
                    ForEach-Object {
                        Invoke-DownloadArtifactInternal `
                            -name $_.Name `
                            -type "url" `
                            -url $_.FullName `
                            -target $target `
                            -targetFolder $targetFolder `
                            -destination $destination `
                            -dependsOn $dependsOn `
                            -groupByDependency:$groupByDependency `
                            -baseUrl $baseUrl `
                            -accessToken $accessToken `
                            -apiFeatures $apiFeatures `
                            -serviceTierFolder $serviceTierFolder
                        
                        # Collect downloaded app
                        Get-NavAppInfo -Path $_.FullName |
                            ForEach-Object {
                                $nugetParams.installedApps += [PSCustomObject]@{
                                    Name      = $_.Name
                                    Publisher = $_.Publisher
                                    id        = $_.AppId
                                    Version   = $_.version
                                }
                            }
                    }

                $success = $true
                New-RequestTelemetry -Name "Download Artifact" -Success $success -StartTime $startTime -properties $properties
                return
            }
        }

        $isDownload = "$sourceUri".StartsWith("http")
        $isArchive = $isDownload -or "$sourceUri".EndsWith(".zip")
        if ("$sourceUri" -ne "") {
            if ($isDownload) {
                $url_output = "$sourceUri".replace('&pat=', "$([System.Environment]::NewLine)").split("$([System.Environment]::NewLine)")
                if ($url_output.Length -gt 1) {
                    New-ArtifactsLogEntry -Message "Download Artifact from $($url_output[0])&pat=***"
                }
                else {
                    New-ArtifactsLogEntry -Message "Download Artifact from $($sourceUri)"
                }
            }
            else {
                New-ArtifactsLogEntry -Message "Copy Artifact from $sourceUri"
            }

            try {
                $startTime = Get-Date
                if ($isDownload) { 
                    if ("$sourceUri".StartsWith("$baseUrl")) {
                        Invoke-WebRequest -Method Get -uri $sourceUri -OutFile "$tempArchive" -Headers $headers
                    }
                    else {
                        New-ArtifactsLogEntry -Message "External artifact URL detected, ignoring Authorization header" -Severity Debug
                        Invoke-WebRequest -Method Get -uri $sourceUri -OutFile "$tempArchive"
                    }
                }
                else {
                    if (Test-Path $sourceUri) {
                        New-ArtifactsLogEntry -Message "Found Artifact at $sourceUri"
                    }
                    else {
                        New-ArtifactsLogEntry -Message "No Artifact found at $sourceUri"
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

                    switch ("$target".ToLower()) {
                        "dll"      { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        "add-ins"  { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        "font"     { $folder = "c:/fonts" }
                        "fonts"    { $folder = "c:/fonts" }
                        "demodata" { $folder = "c:/demodata" }
                        default    {
                            if (!$groupByDependency) {
                                $folder = Join-Path $rootFolder "/$folderSuffix"
                            } elseif ($dependsOn) {
                                $folder = Join-Path $rootFolder "/dependent-on-$($dependsOn.ToLower())/$folderSuffix"
                            } else {
                                $folder = Join-Path $rootFolder "/general/$folderSuffix"
                            }
                        }
                    }

                    if ($isArchive) {
                        New-ArtifactsLogEntry -Message "Extract Artifact $name v $artifactVersion to $($folder)..."
                        Expand-Archive -Path "$archive" -DestinationPath "$folder" -Force 
                        if ($cosmoArtifactType.Count -gt 0) {
                            New-ArtifactsLogEntry -Message "Artifact has type selection: $([string]::Join(",", $cosmoArtifactType))"
                            $subfolders = Get-ChildItem -Path "$folder" -Directory
                            $subfolders | ForEach-Object {
                                if (-not $cosmoArtifactType.Contains($_.Name)) {
                                    New-ArtifactsLogEntry -Message "Artifact has subfolder $($_.Name), which doesn't exist in type selection, therefore removing it: $($_.FullName)"
                                    Remove-Item -Force -Recurse -Path $_.FullName
                                }
                            }
                        }
                    }
                    else {
                        New-ArtifactsLogEntry -Message "Copy Artifact '$sourceUri' ($name v $artifactVersion) to $($folder)..."
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
                    New-ArtifactsLogEntry -Message "  Downloaded Files ($folder):"
                    New-ArtifactsLogEntry -Message "$((Get-ChildItem $folder -Recurse) | 
                        Select-Object FullName, Length | 
                        Format-Table -AutoSize -Wrap:$false | 
                        Out-String -Width 1024)"

                    if ($nugetParams) {
                        # Collect downloaded apps
                        Get-ChildItem -Path $folder -Filter '*.app' -Recurse |
                            ForEach-Object { Get-NavAppInfo -Path $_.FullName } |
                            ForEach-Object {
                                $nugetParams.installedApps += [PSCustomObject]@{
                                    Name      = $_.Name
                                    Publisher = $_.Publisher
                                    id        = $_.AppId
                                    Version   = $_.version
                                }
                            }
                    }

                    $success = $true
                }
                else {
                    New-ArtifactsLogEntry -Message "No content available from source: '$sourceUri'" -Severity Warn -Success Skip
                    $success = $false
                }

                $properties = @{"organization" = $organization; "project" = $project; "feed" = $feed; "name" = $name; "scope" = $scope; "view" = $view; "protocolType" = $type; "url" = $url_output }
                New-RequestTelemetry -Name "Download Artifact" -Success $success -StartTime $startTime -Properties $properties
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

                New-ArtifactsLogEntry -Message "Download Artifact $($name) failed: $($errorMessage)" -Severity Error -Success Fail
                New-ExceptionTelemetry -Exception $_.Exception -Properties $properties
            }
            finally {
                if (Test-Path $tempArchive) {
                    Remove-Item -Path $tempArchive -Force -ErrorAction SilentlyContinue
                }
                $sourceUri = ""
            }
        }
        else {
            New-ArtifactsLogEntry -Message "Artifact $name skipped - no Url found." -Severity Warn -Success Skip
        }
    }
    
    end {
        $artifactVersion = ""
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifactInternal