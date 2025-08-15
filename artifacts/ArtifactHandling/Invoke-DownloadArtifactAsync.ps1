function Invoke-DownloadArtifactAsync {
    [CmdletBinding(DefaultParameterSetName = 'Sync')]
    param (
        # Artifact Parameter
        [Parameter(ValueFromPipeline)]
        [object]$Artifact,

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

        # Async Parameters
        [Parameter(Mandatory)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        [switch]$OneRunspace
    )
    
    begin {
        $artifacts = @()

        if (! (Get-Module 'PPIAsyncUtils')) {
            throw "PPI Async Utils not loaded"
        }

        if (! $PSBoundParameters.ContainsKey("OneRunspace")) {
            if ($RunspacePool.GetMaxRunspaces() -eq 1) {
                $OneRunspace = $true
            }
        }

        $groupingScriptBlock = { New-Guid }
        if ($OneRunspace) {
            $groupingScriptBlock = { "All" }
        }

        $scriptBlock = {
            param(
                [object[]]$Artifacts, 
                [hashtable]$Parameters
            )
            try {
                $Artifacts | Invoke-DownloadArtifact -PassThru @Parameters
            } catch {
                throw $_
            } finally {
                Get-Date
            }
        }
    }
    
    process {
        # Collect given artifacts
        $artifacts += $Artifact
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

        $artifacts |
            Group-Object $groupingScriptBlock |
            ForEach-Object {
                $scriptBlockParameters = @{
                    Artifacts = @( $_.Group )
                    Parameters = @{
                        AllArtifacts = $AllArtifacts
                        Destination = $Destination
                        GroupByDependency = $GroupByDependency
                        BaseUrl = $BaseUrl
                        AccessToken = $AccessToken
                        ApiFeatures = $ApiFeatures
                        ServiceTierFolder = $ServiceTierFolder
                        FolderIdx = $FolderIdx
                    }
                }

                Invoke-Async `
                    -RunspacePool $RunspacePool `
                    -ScriptBlock $scriptBlock `
                    -Parameters $scriptBlockParameters

                $FolderIdx ++
            }
    }
}
Export-ModuleMember -Function Invoke-DownloadArtifactAsync