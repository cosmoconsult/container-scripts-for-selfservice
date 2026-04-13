function Get-DemoDataFiles {
    [cmdletbinding()]
    PARAM
    (
    )
    PROCESS {
        $files = @()
        if (Test-Path -Path "c:\demodata") {
            $files = Get-ChildItem "c:\demodata" -Filter *.xml |
            Where-Object {
                if ($env:IsBuildContainer -and !$_.Name.Contains('Test Automation')) {
                    "Skipping XML file {0} as it's no Test Automation database and it seems to be a build container" -f $_.FullName | Write-Host
                    return $false
                }
                return $true
            } | Sort-Object Name -Descending
        }

        if ($files.Count -gt 0) {
            return $files
        }

        try {
            # Get repository information from environment
            $organization = "$($env:CcOrgName)"
            $projectId = "$($env:CcProjectId)"
            $repository = "$($env:CcRepoId)"
            $branch = "$($env:CcBranch)"

            if ([string]::IsNullOrWhiteSpace($organization) -or [string]::IsNullOrWhiteSpace($projectId) -or [string]::IsNullOrWhiteSpace($repository)) {
                Write-Host "Skipping config fallback for demodata: missing CcOrgName, CcProjectId, or CcRepoId environment variables"
                return @()
            }

            $baseUrl = if (![string]::IsNullOrWhiteSpace("$($env:publicdnsname)")) { "https://$($env:publicdnsname)" } else { "https://fps-alpaca.westeurope.cloudapp.azure.com" }
            $query = "PATValidationProject=$([Uri]::EscapeDataString($organization))"
            if (![string]::IsNullOrWhiteSpace($branch)) {
                $query = "$query&branch=$([Uri]::EscapeDataString($branch))"
            }

            $configUri = "$baseUrl/automation/0.11/repository/$([Uri]::EscapeDataString($organization))/$([Uri]::EscapeDataString($projectId))/$([Uri]::EscapeDataString($repository))/config?$query"
            Write-Host "Resolve demo data from repository config: $configUri"

            $headers = @{}
            $accessToken = Get-AzureDevOpsAccessToken -Artifacts @()
            if (![string]::IsNullOrWhiteSpace($accessToken)) {
                $headers['Authorization'] = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($accessToken)")))"
            }

            $webRequestParams = @{
                Uri = $configUri
                Method = 'Get'
                UseBasicParsing = $true
            }
            if ($headers.Count -gt 0) {
                $webRequestParams['Headers'] = $headers
            }

            $response = Invoke-WebRequest @webRequestParams
            if ($response.StatusCode -ne 200 -or [string]::IsNullOrWhiteSpace("$($response.Content)")) {
                Write-Host "No repository config response for demodata fallback (status: $($response.StatusCode))"
                return @()
            }

            $configObject = $response.Content | ConvertFrom-Json -Depth 50
            $demoDataItems = @()

            # Look for demo data in bcArtifacts.current.ipArtifacts
            if ($configObject.bcArtifacts -and $configObject.bcArtifacts.current -and $configObject.bcArtifacts.current.ipArtifacts) {
                $demoDataItems = @($configObject.bcArtifacts.current.ipArtifacts | Where-Object { $_.azFsType -eq 'AzFSPackageDemoData' })
            }

            # Fallback: look for demo data at top-level ipArtifacts
            if ($demoDataItems.Count -eq 0 -and $configObject.ipArtifacts) {
                $demoDataItems = @($configObject.ipArtifacts | Where-Object { $_.azFsType -eq 'AzFSPackageDemoData' })
            }

            if ($demoDataItems.Count -eq 0) {
                Write-Host "No demo data items found in repository config"
                return @()
            }

            $files = @($demoDataItems | ForEach-Object {
                [pscustomobject]@{
                    Name = $_.name
                    FullName = "resolved://demodata/$($_.name)"
                    AssetName = $_.name
                    Source = 'repository-config'
                }
            } | Where-Object {
                if ($env:IsBuildContainer -and !$_.Name.Contains('Test Automation')) {
                    "Skipping demo data artifact {0} as it's no Test Automation database and it seems to be a build container" -f $_.Name | Write-Host
                    return $false
                }
                return $true
            } | Sort-Object Name -Descending)

            Write-Host "Found $($files.Count) demo data files from repository config"
            return $files
        }
        catch {
            Write-Host "Failed to resolve demo data from repository config: $($_.Exception.Message)"
            return @()
        }
    }

}

Export-ModuleMember -Function Get-DemoDataFiles