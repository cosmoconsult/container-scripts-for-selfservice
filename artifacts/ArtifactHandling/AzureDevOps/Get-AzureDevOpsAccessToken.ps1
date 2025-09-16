function Get-AzureDevOpsAccessToken {
    [CmdletBinding()]
    param (
        [object[]]$Artifacts   = @(),
        [string]  $AccessToken = "$($env:AZURE_DEVOPS_EXT_PAT)"
    )
    
    process {
        if (! ($Artifacts | Where-Object { ! $_.Url } | Where-Object { $_.Type -ne "nuget" })) {
            # Skip if all artifacts have a download URL or are nuget packages
            return
        }

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
            # Log warning if PAT is not present
            Add-ArtifactsLog -message "PAT not present" -severity Warn
        }
    }

    end {
        return $AccessToken
    }
}
Export-ModuleMember -Function Get-AzureDevOpsAccessToken