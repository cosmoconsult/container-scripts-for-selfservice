function Invoke-DownloadArtifact {
    [CmdletBinding()]
    param (
        # Artifact Parameters
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Organization,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Project,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Feed,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Name,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Type,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $View,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Version,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Scope,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Url,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Target,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $TargetFolder,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $AppImportScope,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Pat,
        [Parameter(ValueFromPipelineByPropertyName)][string[]]$CosmoArtifactType,
        [Parameter(ValueFromPipelineByPropertyName)][string]  $DependsOn,

        # Download Parameters
        [string]  $Destination       = "$($env:TEMP)/$([System.IO.Path]::GetRandomFileName())",
        [switch]  $GroupByDependency = $false,
        [string]  $BaseUrl           = "https://$($env:publicdnsname)",
        [string]  $AccessToken,
        [string[]]$ApiFeatures,
        [string]  $ServiceTierFolder,
        [int]     $FolderIdx         = 0,

        # Control Parameters
        [switch]$PassThru,
        [System.Object]$TelemetryClient = $null
    )
    
    begin {
        $artifacts = @()

        if (! $PassThru) {
            if (! $TelemetryClient) {
                
            }
        }

        # Collect artifact parameters
        $artifactParameters = 
            $MyInvocation.MyCommand.Parameters.GetEnumerator() | 
            Where-Object { 
                $_.Value.Attributes | 
                    Where-Object { $_.ValueFromPipelineByPropertyName }
            } | 
            Select-Object -ExpandProperty Key
    }
    
    process {
        # Collect given artifacts from bound parameters
        $artifact = @{}
        $PSBoundParameters.GetEnumerator() |
            Where-Object { $_.Key -in @( $artifactParameters ) } |
            ForEach-Object {
                $artifact[$_.Key] = $_.Value
            }
        $artifacts += $Artifact
    }
    
    end {
        if (! $PSBoundParameters.ContainsKey("ServiceTierFolder")) {
            $ServiceTierFolder = Get-NAVServiceTierFolder
        }

        if (! $PSBoundParameters.ContainsKey("ApiFeatures")) {
            $ApiFeatures = Get-AzureDevOpsApiFeatures -BaseUrl $BaseUrl
        }

        if (! $PSBoundParameters.ContainsKey("AccessToken")) {
            $AccessToken = Get-AzureDevOpsAccessToken -Artifacts $artifacts
        }

        $parameters = @{
            Destination = $Destination
            GroupByDependency = $GroupByDependency
            BaseUrl = $BaseUrl
            AccessToken = $AccessToken
            ApiFeatures = $ApiFeatures
            ServiceTierFolder = $ServiceTierFolder
            FolderIdx = $FolderIdx
        }

        $outputs = @(
            try {
                $artifacts | Invoke-DownloadArtifactInternal @parameters
            } catch {
                throw $_
            } finally {
                Get-Date
            }
        )

        if (! $PassThru) {
            $outputs | Resolve-DownloadArtifact -TelemetryClient $TelemetryClient | Out-Null
        } else {
            $outputs
        }
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifact