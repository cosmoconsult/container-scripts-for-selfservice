function Invoke-DownloadArtifact {
    [CmdletBinding()]
    param (
        # Artifact Parameters
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Organization      = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Project           = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Feed              = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Name              = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Type              = "upack",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $View              = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Version           = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Scope             = "project",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Url               = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Target            = "",        
        [Parameter(ValueFromPipelineByPropertyName)][string]  $TargetFolder      = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $AppImportScope    = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $AppImportSyncMode = "",
        [Parameter(ValueFromPipelineByPropertyName)][string]  $Pat               = "",
        [Parameter(ValueFromPipelineByPropertyName)][string[]]$CosmoArtifactType = @(),
        [Parameter(ValueFromPipelineByPropertyName)][string]  $DependsOn         = "",

        # Artifacts Parameter
        [object[]] $AllArtifacts = @(),

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
                $TelemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
            }
        }
    }
    
    process {
        # Collect given artifacts
        $artifacts += [pscustomobject]@{
            Organization = $Organization
            Project = $Project
            Feed = $Feed
            Name = $Name
            Type = $Type
            View = $View
            Version = $Version
            Scope = $Scope
            Url = $Url
            Target = $Target
            TargetFolder = $TargetFolder
            AppImportScope = $AppImportScope
            AppImportSyncMode = $AppImportSyncMode
            Pat = $Pat
            CosmoArtifactType = $CosmoArtifactType
            DependsOn = $DependsOn
        }
    }
    
    end {
        if (! $artifacts) {
            return
        }
        
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
            AllArtifacts = $AllArtifacts
            Destination = $Destination
            GroupByDependency = $GroupByDependency
            BaseUrl = $BaseUrl
            AccessToken = $AccessToken
            ApiFeatures = $ApiFeatures
            ServiceTierFolder = $ServiceTierFolder
            FolderIdx = $FolderIdx
        }

        if (! $PassThru) {
            $artifacts | Invoke-DownloadArtifactCore @parameters | Resolve-DownloadArtifact -TelemetryClient $TelemetryClient | Out-Null
        } else {
            $artifacts | Invoke-DownloadArtifactCore @parameters
        }
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifact