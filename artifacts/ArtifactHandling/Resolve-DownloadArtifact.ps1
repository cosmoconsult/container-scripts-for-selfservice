function Resolve-DownloadArtifact {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $Object,

        [System.Object]$TelemetryClient,
        [ref]$End
    )

    begin {
        if (! $TelemetryClient) {
            $TelemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }

        $logEntries = @()
    }
    
    process {
        switch ($true) {
            ($Object.GetType() -in @([Microsoft.ApplicationInsights.DataContracts.EventTelemetry], [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry], [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry])) {
                Push-Telemetry -Operation "Download Artifact" -Telemetry $Object -TelemetryClient $TelemetryClient
            }
            ($Object.GetType() -eq [ArtifactsLogEntry]) {
                $logEntries += $Object
            }
            ($Object.GetType() -eq [DateTime]) {
                if ($End -and $Object -gt $End.Value) {
                    $End.Value = $Object
                }
            }
            default {
                $Object
            }
        }
    }

    end {
        $logEntries | Push-ArtifactsLogEntry
    }
}
Export-ModuleMember -Function Resolve-DownloadArtifact