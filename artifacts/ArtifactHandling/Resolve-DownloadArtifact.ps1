function Resolve-DownloadArtifact {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        $Object,

        [System.Object]$TelemetryClient
    )

    begin {
        if (! $TelemetryClient) {
            $TelemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        $logBatch       = [System.Collections.Generic.List[ArtifactsLogEntry]]::new()
        $telemetryBatch = [System.Collections.Generic.List[Microsoft.ApplicationInsights.Channel.ITelemetry]]::new()

        $flushLog = {
            if ($logBatch.Count) {
                $logBatch | Push-ArtifactsLogEntry
                $logBatch.Clear()
            }
        }
        $flushTelemetry = {
            if ($telemetryBatch.Count) {
                $telemetryBatch | ForEach-Object { Push-Telemetry -Operation "Download Artifact" -Telemetry $_ -TelemetryClient $TelemetryClient }
                $telemetryBatch.Clear()
            }
        }
    }

    process {
        if (! $Object) {
            return
        }

        switch ($true) {
            ($Object.GetType() -in @([Microsoft.ApplicationInsights.DataContracts.EventTelemetry], [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry], [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry])) {
                & $flushLog
                $telemetryBatch.Add($Object)
            }
            ($Object.GetType() -eq [ArtifactsLogEntry]) {
                & $flushTelemetry
                $logBatch.Add($Object)
            }
            default {
                & $flushLog
                & $flushTelemetry
                $Object
            }
        }
    }

    end {
        & $flushLog
        & $flushTelemetry
    }
}
Export-ModuleMember -Function Resolve-DownloadArtifact