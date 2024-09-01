function Get-PackageVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$organization,
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$project = "",
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$feed,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$name,
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$protocolType = "upack",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$view = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [string]$scope = "project",
        [Parameter(Mandatory = $false)]
        [string]$accessToken = "$($env:AZURE_DEVOPS_EXT_PAT)",
        [Parameter(Mandatory = $false)]
        [string]$artifactVersion = "",
        [Parameter(Mandatory = $false)]
        [System.Object]$telemetryClient = $null
    )
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
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
        if ("" -eq "$accessToken") {
            Add-ArtifactsLog -message "PAT not present" -severity Warn
        }
    }
    process {
        try {
            $started = Get-Date -Format "o"

            if ("$scope" -ne "project") { $project = "" }
            $headers = @{ "Authorization" = "Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$($accessToken)")))"; }
            $baseuri = [string]::Join('/', (@($organization, $project) | Where-Object { "$_" -ne "" }))
            $uri = "https://feeds.dev.azure.com/$baseuri/_apis/packaging/feeds/$feed/packages?api-version=5.1-preview.1"
            Add-ArtifactsLog -message "Get Package for $name ... $uri" #$($headers | ConvertTo-Json -Compress)
            $package = (((Invoke-WebRequest -Method Get -uri $uri -Headers $headers -UseBasicParsing).Content | ConvertFrom-Json).value | Where-Object { $_.name -eq $name -and $_.protocolType -eq $protocolType } | Select-Object -first 1)
            $uri = "https://feeds.dev.azure.com/$baseuri/_apis/packaging/feeds/$feed/packages/$($package.id)/versions?isListed=true&isDeleted=false&api-version=5.1-preview.1"
            Add-ArtifactsLog -message "Get Version for $name ... $uri" #$($headers | ConvertTo-Json -Compress)
            if ($artifactVersion -ne "") {
                Add-ArtifactsLog -message "Requested Version: $artifactVersion"
            }
            $artifactVersion = $artifactVersion.Replace("*", "")
            if ($artifactVersion -eq "") {
                $version = ((((Invoke-WebRequest -Method Get -uri $uri -Headers $headers -UseBasicParsing).Content | ConvertFrom-Json).value | Where-Object { $_.views | Where-Object { "$view" -eq "" -or $_.name -eq $view } }) | Select-Object version -First 1).version
            }
            else {
                $version = ((((Invoke-WebRequest -Method Get -uri $uri -Headers $headers -UseBasicParsing).Content | ConvertFrom-Json).value | Where-Object { $_.views | Where-Object { "$view" -eq "" -or $_.name -eq $view } }) | Where-Object { $_.version.StartsWith($artifactVersion) } | Select-Object version -First 1).version
            }
            
            Invoke-LogRequest -name "Get-PakageVersion" -started $started -success $true -telemetryClient $telemetryClient
            return $version            
        }
        catch {
            Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient
        }        
    }
    end {
        
    }
}
Export-ModuleMember -Function Get-PackageVersion