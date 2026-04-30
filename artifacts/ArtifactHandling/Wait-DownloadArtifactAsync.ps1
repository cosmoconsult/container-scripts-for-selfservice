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
        Wait-Async -RunspaceInfo $RunspaceInfo -TimeoutSeconds 3600 |
            Resolve-DownloadArtifact -TelemetryClient $TelementryClient |
            ForEach-Object {
                if ($_ -is [DateTime]) {
                    if ($End -and $_ -gt $End.Value) {
                        $End.Value = $_
                    }
                }
            }
    }
}
Export-ModuleMember -Function Wait-DownloadArtifactAsync