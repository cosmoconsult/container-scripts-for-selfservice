function Wait-DownloadArtifactAsync {
    [CmdletBinding()]
    param (
        # Async Parameter
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [powershell]$Runspace,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.IAsyncResult]$Result,
        [Parameter(Mandatory = $false)]
        [System.Object]$TelemetryClient = $null
    )

    begin {
        if (! (Get-Module 'PPIAsyncUtils')) {
            throw "PPI Async Utils not loaded"
        }
    }
    
    process {
        Wait-Async `
            -Runspace $Runspace `
            -Result $Result |
        ForEach-Object {
            if ($_.GetType() -in @([Microsoft.ApplicationInsights.DataContracts.EventTelemetry], [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry], [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry])) {
                Push-Telemetry -Operation "Download Artifact" -Telemetry $_ -TelemetryClient $TelemetryClient
            }
            if ($_.GetType() -eq [ArtifactsLogEntry]) {
                Push-ArtifactsLogEntry -Entry $_
            }
        } |
        Out-Null
    }
}
Export-ModuleMember -Function Wait-DownloadArtifactAsync