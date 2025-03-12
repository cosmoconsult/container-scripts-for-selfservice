function Invoke-DownloadArtifactAsync {
    [CmdletBinding()]
    param (
        # Artifact Parameter
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Artifact,

        # Async Parameter
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        [ValidateSet("automatic", "single", "multiple")]
        [string]$RunspaceMode = "automatic",

        # Download Parameter
        [Parameter(Mandatory = $false)]
        [string]$Destination = "$($env:TEMP)/$([System.IO.Path]::GetRandomFileName())",
        [Parameter(Mandatory = $false)]
        [switch]$GroupByDependency = $false,
        [Parameter(Mandatory = $false)]
        [string]$BaseUrl = "https://$($env:publicdnsname)",
        [Parameter(Mandatory = $false)]
        [string]$AccessToken = "$($env:AZURE_DEVOPS_EXT_PAT)"
    )
    
    begin {
        if (! (Get-Module 'PPIAsyncUtils')) {
            throw "PPI Async Utils not loaded"
        }

        if ($RunspaceMode -eq "automatic") {
            $RunspaceMode = "multiple"
            if ($RunspacePool.GetMaxRunspaces() -eq 1) {
                $RunspaceMode = "single"
            }
        }

        $scriptBlock = {
            param(
                [object[]]$Artifacts, 
                [string]$Destination,
                [bool]$GroupByDependency,
                [string]$BaseUrl,
                [string]$AccessToken,
                [string[]]$ApiFeatures,
                [int]$FolderIdx,
                [string]$ServiceTierFolder
            )

            $Artifacts | 
                Invoke-DownloadArtifactInternal `
                    -destination $Destination `
                    -groupByDependency:$GroupByDependency `
                    -baseUrl $BaseUrl `
                    -accessToken $AccessToken `
                    -apiFeatures $ApiFeatures `
                    -serviceTierFolder $ServiceTierFolder `
                    -folderIdx $FolderIdx

        }

        $parameters = @{
            Artifacts = $null
            Destination = $Destination
            GroupByDependency = $GroupByDependency
            BaseUrl = $BaseUrl
            AccessToken = $AccessToken
            ApiFeatures = @()
            ServiceTierFolder = ""
            FolderIdx = 0
        }

        $artifacts = @()
    }
    
    process {
        # Collect given artifacts
        $artifacts += $Artifact
    }
    
    end {
        # Get the Service Tier Folder
        $parameters.ServiceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service" -ErrorAction SilentlyContinue).FullName
        if (! $parameters.ServiceTierFolder) {
            Add-ArtifactsLog -message "Service Tier Folder not found at 'C:\Program Files\Microsoft Dynamics NAV\*\Service'" -severity Warn
        }

        # Get the API Features
        try {
            $apiFeaturesResult = Invoke-WebRequest -Method Get -uri "$BaseUrl/api/automation/release/Features" -UseBasicParsing
            if ($apiFeaturesResult.StatusCode -eq 200) {
                $parameters.ApiFeatures = ConvertFrom-Json $apiFeaturesResult.Content
            }
        }
        catch {}

        # Get the PAT, if an artifact without Download URL is present
        if ((! $parameters.AccessToken) -and ($artifacts | Where-Object { ! $_.url } | Where-Object { $_.type -ne "nuget" })) {
            if (! $parameters.AccessToken) {
                # Try get the PAT from environment
                $parameters.AccessToken = @($env:AZURE_DEVOPS_TOKEN, $env:AZURE_DEVOPS_EXT_PAT, $env:AZP_TOKEN) | 
                    Where-Object { $_ } | 
                    Select-Object -First 1
            }
            if (! $parameters.AccessToken) {
                # Try to convert PAT from Base64, because it is stored in environment
                $accessToken64 = @($env:AZURE_DEVOPS_TOKEN64, $env:AZURE_DEVOPS_EXT_PAT64, $env:AZP_TOKEN64, $env:AZURE_DEVOPS_PAT64) | 
                    Where-Object { $_ } | 
                    Select-Object -First 1
                if (! $accessToken64) {
                    try {
                        $parameters.AccessToken = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String("$accessToken64"))
                    }
                    catch {}

                    if (! $parameters.AccessToken) {
                        try {
                            $parameters.AccessToken = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String("$accessToken64"))
                        }
                        catch {}
                    }
                }
            }
            if (! $parameters.AccessToken) {
                Add-ArtifactsLog -message "PAT not present" -severity Warn
            }
        }

        if ($RunspaceMode -eq "single") {
            # Start the download for all artifacts in one runspace
            $parameters.Artifacts = @( $artifacts )

            Invoke-Async `
                -RunspacePool $RunspacePool `
                -ScriptBlock $scriptBlock `
                -Parameters $parameters
        } else {
            # Start the download for each artifact in a separate runspace
            $artifacts | ForEach-Object {
                $parameters.Artifacts = @( $_ )

                Invoke-Async `
                    -RunspacePool $RunspacePool `
                    -ScriptBlock $scriptBlock `
                    -Parameters $parameters
                
                $parameters.FolderIdx ++
            }
        }
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifactAsync