function Wait-DownloadArtifactAsync {
    [CmdletBinding()]
    param (
        # Async Parameter
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$RunspaceInfo,
        [Parameter(Mandatory = $false)]
        [System.Object]$TelemetryClient = $null,
        [Parameter(Mandatory = $false)]
        [ref]$End = [ref]$null
    )

    begin {
        if (! (Get-Module 'PPIAsyncUtils')) {
            throw "PPI Async Utils not loaded"
        }
    }
    
    process {
        Wait-Async -RunspaceInfo $RunspaceInfo -TimeoutSeconds 60 |
            Resolve-DownloadArtifact -TelemetryClient $TelementryClient -End $End | 
            Out-Null
    }
}
Export-ModuleMember -Function Wait-DownloadArtifactAsync