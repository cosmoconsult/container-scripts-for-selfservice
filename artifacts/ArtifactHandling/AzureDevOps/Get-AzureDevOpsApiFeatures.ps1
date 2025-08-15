function Get-AzureDevOpsApiFeatures {
    [CmdletBinding()]
    param (
        [string]$BaseUrl = "https://$($env:publicdnsname)"
    )
    
    begin {
        if ("$BaseUrl" -eq "https://" -or "$BaseUrl".ToLower() -contains "localhost") {
            $BaseUrl = "https://cosmo-alpaca-enterprise.westeurope.cloudapp.azure.com"
        }

        $apiFeatures = @()
    }
    
    process {
        # Get the API Features
        try {
            $apiFeaturesResult = Invoke-WebRequest -Method Get -uri "$BaseUrl/api/automation/release/Features" -UseBasicParsing
            if ($apiFeaturesResult.StatusCode -eq 200) {
                $apiFeatures = ConvertFrom-Json $apiFeaturesResult.Content
            }
        }
        catch {}
    }

    end {
        return $apiFeatures
    }
}
Export-ModuleMember -Function Get-AzureDevOpsApiFeatures