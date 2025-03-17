function Resolve-DownloadArtifactInternal {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $Object,

        [System.Object]$TelemetryClient = $null,
        [ref]$End = $null
    )
    
    process {
        switch ($true) {
            ($Object.GetType() -in @([Microsoft.ApplicationInsights.DataContracts.EventTelemetry], [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry], [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry])) {
                Push-Telemetry -Operation "Download Artifact" -Telemetry $Object -TelemetryClient $TelemetryClient
            }
            ($Object.GetType() -eq [ArtifactsLogEntry]) {
                Push-ArtifactsLogEntry -Entry $Object
            }
            ($Object.GetType() -eq [DateTime]) {
                if ($End -and $Object -gt $End.Value) {
                    $End.Value = $Object
                }
            }
            else {
                $Object
            }
        }
    }
}
Export-ModuleMember -Function Resolve-DownloadArtifactInternal