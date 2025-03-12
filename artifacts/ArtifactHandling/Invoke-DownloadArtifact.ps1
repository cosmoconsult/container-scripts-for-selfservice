function Invoke-DownloadArtifact {
    [CmdletBinding()]
    param (
        # Artifact Parameter
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Artifact,

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
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        $artifacts = @()
    }
    
    process {
        # Collect given artifacts
        $artifacts += $Artifact
    }
    
    end {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }

        $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service" -ErrorAction SilentlyContinue).FullName
        if (! $serviceTierFolder) {
            Add-ArtifactsLog -message "Service Tier Folder not found at 'C:\Program Files\Microsoft Dynamics NAV\*\Service'" -severity Warn
        }

        if ($artifacts | Where-Object { ! $_.url } | Where-Object { $_.type -ne "nuget" }) {
            # Validate or get the PAT, because no Download URL is present
            if ("$accessToken" -eq "") {
                # Try get the PAT from environment
                $accessToken = (@("$($env:AZURE_DEVOPS_TOKEN)", "$($env:AZURE_DEVOPS_EXT_PAT)", "$($env:AZP_TOKEN)") | ? { "$_" -ne "" } | select -First 1)            
            }
            if ("$accessToken" -eq "") {
                # Try to convert PAT from Base64, because it is stored in environment
                $accessToken64 = (@("$($env:AZURE_DEVOPS_TOKEN64)", "$($env:AZURE_DEVOPS_EXT_PAT64)", "$($env:AZP_TOKEN64)", "$($env:AZURE_DEVOPS_PAT64)") | ? { "$_" -ne "" } | select -First 1)
                if ("" -ne "$accessToken64" -and "" -eq "$accessToken") {
                    try {
                        $accessToken = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String("$accessToken64"))
                    }
                    catch {}                    
                }
                if ("" -ne "$accessToken64" -and "" -eq "$accessToken") {
                    try {
                        $accessToken = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String("$accessToken64"))
                    }
                    catch {}
                }
            }
            if ("$accessToken" -eq "") {
                Add-ArtifactsLog -message "PAT not present" -severity Warn
            }
        }

        try {
            $apiFeaturesResult = Invoke-WebRequest -Method Get -uri "$baseUrl/api/automation/release/Features" -UseBasicParsing
            if ($apiFeaturesResult.StatusCode -eq 200) {
                $apiFeatures = ConvertFrom-Json $apiFeaturesResult.Content
            }
            Add-ArtifactsLog -message "Api Features enabled: $($apiFeatures -join ', ')"
        }
        catch {}
        
        $artifacts | 
            Invoke-DownloadArtifactInternal `
                -destination $destination `
                -groupByDependency:$groupByDependency `
                -baseUrl $baseUrl `
                -accessToken $accessToken `
                -apiFeatures $apiFeatures `
                -serviceTierFolder $serviceTierFolder |
            ForEach-Object {
                if ($_.GetType() -in @([Microsoft.ApplicationInsights.DataContracts.EventTelemetry], [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry], [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry])) {
                    Push-Telemetry -Operation "Download Artifact" -Telemetry $_ -TelemetryClient $telemetryClient
                }
                if ($_.GetType() -eq [ArtifactsLogEntry]) {
                    Push-ArtifactsLogEntry -Entry $_
                }
            } |
            Out-Null
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifact