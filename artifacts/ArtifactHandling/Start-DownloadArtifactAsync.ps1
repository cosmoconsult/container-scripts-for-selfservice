function Start-DownloadArtifactAsync {
    [CmdletBinding()]
    param (
        # Artifact Parameter
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Artifact,
        # Download Parameter
        [Parameter(Mandatory = $false)]
        [string]$Destination = "$($env:TEMP)/$([System.IO.Path]::GetRandomFileName())",
        [Parameter(Mandatory = $false)]
        [string]$BaseUrl = "https://$($env:publicdnsname)",
        [Parameter(Mandatory = $false)]
        [string]$AccessToken = "$($env:AZURE_DEVOPS_EXT_PAT)",
        # Async Parameter
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )
    
    begin {
        $serviceTierFolder = "$((Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service" -ErrorAction SilentlyContinue).FullName)"
        if (! $serviceTierFolder) {
            Write-Warning "Service Tier Folder not found at 'C:\Program Files\Microsoft Dynamics NAV\*\Service'"
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

        $apiFeatures = ""
        try {
            $apiFeaturesResult = Invoke-WebRequest -Method Get -uri "$BaseUrl/api/automation/release/Features" -UseBasicParsing
            if ($apiFeaturesResult.StatusCode -eq 200) {
                $apiFeatures = ConvertFrom-Json $apiFeaturesResult.Content
            }
        }
        catch {}

        $scriptBlock = {
            param(
                [object]$Artifact, 
                [string]$Destination,
                [string]$BaseUrl,
                [string]$AccessToken,
                [string]$ApiFeatures,
                [string]$ServiceTierFolder,
                [int]$FolderIdx
            )

            $Artifact | 
                Invoke-DownloadArtifact `
                    -destination $Destination `
                    -baseUrl $BaseUrl `
                    -accessToken $AccessToken `
                    -ApiFeatures $ApiFeatures `
                    -serviceTierFolder $ServiceTierFolder `
                    -folderIdx $FolderIdx
        }

        $parameters = @{
            Artifact = $null
            Destination = $Destination
            BaseUrl = $BaseUrl
            AccessToken = $AccessToken
            ApiFeatures = $ApiFeatures
            ServiceTierFolder = $serviceTierFolder
            FolderIdx = 0
        }
    }
    
    process {
        $parameters.Artifact = $Artifact
        $parameters.FolderIdx ++

        return Invoke-AsyncScript `
            -RunspacePool $RunspacePool `
            -ScriptBlock $scriptBlock `
            -Parameters $paramters
    }
    
    end {
    }
}
Export-ModuleMember -Function Start-DownloadArtifactAsync