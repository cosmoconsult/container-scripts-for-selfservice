function Wait-DownloadArtifactAsync {
    [CmdletBinding()]
    param (
        # Async Parameter
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [powershell]$Runspace,
        [Parameter(Mandatory = $false)]
        [System.Object]$TelemetryClient = $null,
        [Parameter(Mandatory = $false)]
        [ref]$End = $null
    )

    begin {
        if (! (Get-Module 'PPIAsyncUtils')) {
            throw "PPI Async Utils not loaded"
        }
    }
    
    process {
        Wait-Async -Runspace $Runspace |
            Resolve-DownloadArtifactInternal |
            Out-Null
    }
}
Export-ModuleMember -Function Wait-DownloadArtifactAsync