function Invoke-DownloadArtifactCore {
    [CmdletBinding()]
    param (
        # Artifact Parameters
        [Parameter(ValueFromPipelineByPropertyName)][string]  $organization,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $project,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $feed,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $name,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $type,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $view,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $version,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $scope,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $url,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $target,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $targetFolder,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $appImportScope,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $appImportSyncMode,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $pat,
        [Parameter(ValueFromPipelineByPropertyName)][string[]]$cosmoArtifactType,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $dependsOn,

        # Artifacts Parameter
        [object[]] $allArtifacts = @(),

        # Download Parameters
        [string]  $destination,
        [switch]  $groupByDependency,
        [string]  $baseUrl,
        [string]  $accessToken,
        [string[]]$apiFeatures,
        [string]  $serviceTierFolder,
        [int]     $folderIdx,
        [ValidateRange(0, [int]::MaxValue)]
        [int]     $retries
    )

    begin {
        if ("$baseUrl" -eq "https://" -or "$baseUrl".ToLower() -contains "localhost") {
            $baseUrl = "https://cosmo-alpaca-enterprise.westeurope.cloudapp.azure.com"
        }

        $headers = @{ "Authorization" = "Bearer $($accessToken)"; "Collection-URI" = "https://dev.azure.com/$($env:CcOrgName)/" }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $rootFolder = $destination
        $tempArchive = "$([System.IO.Path]::GetTempFileName()).zip"
        $tempApp = "$([System.IO.Path]::GetTempFileName()).app"

        $singleFileTargets = @{ rapidstart = ".rapidstart"; fob = ".fob" }

        $predefinedNuGetPackages = @( $allArtifacts |
            Where-Object { $_.Type -eq 'nuget' } |
            ForEach-Object {
                [PSCustomObject]@{
                    Package = $_.Name
                    Version = $_.Version
                }
            }
        )

        $maxAttempts = $retries + 1
    }

    process {
        # check restart
        if (($env:cosmoServiceRestart -eq $true) -and @("bak", "saasbak", "fob", "app", "rapidstart", "").Contains("$target".ToLower())) {
            New-ArtifactsLogEntry -Message "Skipping $target download because this seems to be a service restart" -Success Skip
            return
        }

        # Download from given URL
        if (Test-Path "$tempArchive" -ErrorAction SilentlyContinue) { Remove-Item "$tempArchive" -Force -ErrorAction SilentlyContinue }
        $tempFile = ""

        $artifactRequest = $null
        $sourceUri = $url
        if ("$sourceUri" -eq "") {
            if ("$pat" -eq "") {
                $pat = $accessToken
            }
            if (($type.ToLower() -eq "upack") -OR (!$type)) {
                if ("$scope" -eq "") { $scope = "project" }
                $artifactRequest = @{
                    scope        = $scope
                    organization = $organization
                    project      = $project
                    feed         = $feed
                    name         = $name
                    version      = $version
                    view         = $view
                    pat          = $pat
                }
                $sourceUri = "$baseUrl/api/alpaca/release/AzureDevOps/Artifact"
            }
        }

        $isNuGet = $type.ToLower() -eq "nuget"
        $isDownload = "$sourceUri" -match '^https?://'
        $isArchive = "$sourceUri".EndsWith(".zip")
        if ($sourceUri -or $isNuGet) {
            $safeUri = Get-SafeArtifactUri -Uri $sourceUri
            if ($isNuGet) {
                Write-Host "##[section]Download Artifact from NuGet package $name"
                New-ArtifactsLogEntry -Message "Download Artifact from NuGet package $name"
            }
            elseif ($isDownload) {
                Write-Host "##[section]Download Artifact $name from $safeUri"
                New-ArtifactsLogEntry -Message "Download Artifact $name from $safeUri"
            }
            else {
                Write-Host "##[section]Copy Artifact $name from $sourceUri"
                New-ArtifactsLogEntry -Message "Copy Artifact $name from $sourceUri"
            }

            try {
                $startTime = Get-Date
                if (! $isNuGet) {
                    if ($isDownload) {
                        $invokeWebRequestSplat = @{
                            Uri             = $sourceUri
                            UseBasicParsing = $true
                        }
                        if ($artifactRequest) {
                            $invokeWebRequestSplat += @{
                                Headers     = $headers
                                Method      = 'Post'
                                ContentType = 'application/json'
                                Body        = ($artifactRequest | ConvertTo-Json -Compress)
                            }
                        }
                        else {
                            $invokeWebRequestSplat += @{ Method = 'Get' }
                            New-ArtifactsLogEntry -Message "External artifact URL detected, ignoring Authorization header" -Severity Debug
                        }
                        foreach ($attempt in 1..$maxAttempts) {
                            try {
                                New-ArtifactsLogEntry -Message "Download artifact (attempt $attempt of $maxAttempts)"
                                $response = Invoke-WebRequest @invokeWebRequestSplat
                                break
                            } catch {
                                if ($attempt -ge $maxAttempts) {
                                    throw
                                }

                                New-ArtifactsLogEntry -Message "Download artifact failed (attempt $attempt of $maxAttempts): $($_.Exception.Message)" -Severity Warn
                                $waitSeconds = [Math]::Pow(2, $attempt - 1)
                                New-ArtifactsLogEntry -Message "Retrying after $waitSeconds second(s)..."
                                Start-Sleep -Seconds $waitSeconds
                            }
                        }

                        # Determine file type based on Content-Disposition header or content signature
                        $fileType = ''
                        $fileExtension = ''
                        $contentDisposition = $response.Headers["Content-Disposition"]
                        if ($contentDisposition -is [string[]]) {
                            # If it's an array, take the first element. This is required for compatibility with PowerShell 5.1. Headers are return as array in pwsh 7 and return as string in Windows PowerShell 5.1
                            $contentDisposition = $contentDisposition[0]
                        }
                        if ("$contentDisposition" -match 'filename\*?="?([^";]+)') {
                            $fileExtension = [System.IO.Path]::GetExtension($Matches[1].Trim()).ToLower()
                        }
                        switch ($true) {
                            { $fileExtension -eq ".zip" } {
                                $fileType = 'zip'
                                break
                            }
                            { $fileExtension -eq ".app" } {
                                $fileType = 'app'
                                break
                            }
                            { $singleFileTargets.Values -contains $fileExtension } {
                                $fileType = 'file'
                                break
                            }
                            { [string]::new([char[]]($response.Content[0..3])) -eq "NAVX" } {
                                $fileType = 'app'
                                break
                            }
                            { [string]::new([char[]]($response.Content[0..1])) -eq "PK" } {
                                $fileType = 'zip'
                                break
                            }
                            { $singleFileTargets.ContainsKey("$target".ToLower()) } {
                                $fileType = 'file'
                                $fileExtension = $singleFileTargets["$target".ToLower()]
                                break
                            }
                            Default {
                                New-ArtifactsLogEntry -Message "Unknown file type detected" -Severity Warn
                                $fileType = 'unknown'
                            }
                        }
                        switch ($fileType) {
                            'app' {
                                $destinationPath = $tempApp
                                $isArchive = $false
                            }
                            'file' {
                                New-ArtifactsLogEntry -Message "Detected single file artifact ($fileExtension)" -Severity Debug
                                $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "$([guid]::NewGuid())$fileExtension"
                                $destinationPath = $tempFile
                                $isArchive = $false
                            }
                            Default {
                                # also zip, do this to not break existing implementations
                                $destinationPath = $tempArchive
                                $isArchive = $true
                            }
                        }

                        [System.IO.File]::WriteAllBytes($destinationPath, $response.Content)
                        $sourceUri = $destinationPath
                    }
                    else {
                        if (Test-Path $sourceUri) {
                            New-ArtifactsLogEntry -Message "Found Artifact at $sourceUri"
                        }
                        else {
                            New-ArtifactsLogEntry -Message "No Artifact found at $sourceUri"
                        }
                    }

                    if ($isArchive) {
                        $archive = $sourceUri
                    }
                    else {
                        $archive = ""
                    }
                }

                if (($isNuGet) -or ($archive -and (Test-Path $archive)) -or ($sourceUri -and (Test-Path $sourceUri))) {
                    # Setup correct folder
                    $folderSuffix = $targetFolder
                    if (! $folderSuffix) {
                        if ($name.StartsWith("sortorder")) {
                            $folderSuffix = $name.Split(" ")[0]
                        }
                    }
                    if (! $folderSuffix) {
                        $folderIdx ++
                        $folderSuffix = "$($folderIdx.ToString().PadLeft(3, '0'))"
                    }

                    switch ("$target".ToLower()) {
                        "dll"      { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        "add-ins"  { $folder = "$serviceTierFolder/Add-Ins/$folderSuffix" }
                        "font"     { $folder = "c:/fonts" }
                        "fonts"    { $folder = "c:/fonts" }
                        "demodata" { $folder = "c:/demodata" }
                        default    {
                            if (! $groupByDependency) {
                                $folder = Join-Path $rootFolder "/$folderSuffix"
                            } elseif ($dependsOn) {
                                $folder = Join-Path $rootFolder "/dependent-on-$($dependsOn.ToLower())/$folderSuffix"
                            } else {
                                $folder = Join-Path $rootFolder "/general/$folderSuffix"
                            }
                        }
                    }

                    $versionStr = if ("$version" -ne "") { " v$version" } else { "" }

                    if ($isNuGet) {
                        $nuGetParameters = @{
                            Destination        = $folder
                            Package            = $name
                            Version            = $version
                            InstalledAppsPath  = $folder -replace "[\/\\]$folderSuffix`$" # Isolate general and dependent-on folders
                            ServiceTierFolder  = $serviceTierFolder
                            PredefinedPackages = $predefinedNuGetPackages
                            Retries            = $retries
                        }
                        Invoke-NuGetPackageDownload @nuGetParameters *>&1 |
                            Where-Object { $_ -ne $null } |
                            ForEach-Object {
                                $output = $_
                                switch($output.GetType()) {
                                    ( [System.Management.Automation.ErrorRecord] )       { throw $output }
                                    ( [System.Management.Automation.WarningRecord] )     { New-ArtifactsLogEntry -Message $output.ToString() -Severity Warn }
                                    ( [System.Management.Automation.VerboseRecord] )     { Write-Verbose $output }
                                    ( [System.Management.Automation.DebugRecord] )       { New-ArtifactsLogEntry -Message $output.ToString() -Severity Debug }
                                    ( [System.Management.Automation.InformationRecord] ) { New-ArtifactsLogEntry -Message $output.ToString() -Severity Info }
                                }
                            }
                    } elseif ($isArchive) {
                        New-ArtifactsLogEntry -Message "Extract Artifact $name$versionStr to $($folder)..."
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
                        New-ArtifactsLogEntry -Message "Copy Artifact '$sourceUri' ($name$versionStr) to $($folder)..."
                        New-Item -ItemType Directory -Path "$folder" -ErrorAction SilentlyContinue -Force | Out-Null
                        Copy-Item -Path "$sourceUri" -Destination "$folder" -Force
                    }

                    if ($appImportScope -or $appImportSyncMode) {
                        # Store the Artifact Specific Import Scope Information
                        $artifactJson = Get-ChildItem -LiteralPath "$folder" -Filter "artifact.json" -Recurse -ErrorAction SilentlyContinue |
                            Select-Object -First 1 |
                            Get-Content -ErrorAction SilentlyContinue |
                            ConvertFrom-Json -ErrorAction SilentlyContinue
                        if (! $artifactJson) { $artifactJson = ConvertFrom-Json "{}" }

                        if($appImportSyncMode) {
                            $artifactJson |
                                add-member -Name "appImportSyncMode" -value "$appImportSyncMode" -MemberType NoteProperty -ErrorAction Ignore
                            $artifactJson.appImportSyncMode = $appImportSyncMode
                        }
                        if($appImportScope) {
                            $artifactJson  |
                                add-member -Name "appImportScope" -value "$appImportScope" -MemberType NoteProperty -ErrorAction Ignore
                            $artifactJson.appImportScope = $appImportScope
                        }
                        $artifactJson |
                            ConvertTo-Json -Depth 50 -ErrorAction SilentlyContinue |
                            Set-Content -LiteralPath "$folder/artifact.json" -ErrorAction SilentlyContinue
                    }

                    New-ArtifactsLogEntry -Message "  Downloaded Files ($folder):"
                    New-ArtifactsLogEntry -Message "$((Get-ChildItem $folder -Recurse -File) |
                        Select-Object FullName, Length |
                        Format-Table -AutoSize -Wrap:$false |
                        Out-String -Width 1024)"

                    $success = $true
                }
                else {
                    New-ArtifactsLogEntry -Message "No content available from source: '$sourceUri'" -Severity Warn -Success Skip
                    $success = $false
                }

                $properties = @{"organization" = $organization; "project" = $project; "feed" = $feed; "name" = $name; "scope" = $scope; "view" = $view; "protocolType" = $type; "url" = $safeUri }
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
                if ($tempFile -and (Test-Path $tempFile)) {
                    Remove-Item -Path $tempFile -Force -ErrorAction SilentlyContinue
                }
                $sourceUri = ""
            }
        }
        else {
            New-ArtifactsLogEntry -Message "Artifact $name skipped - no Url found." -Severity Warn -Success Skip
        }
    }
}