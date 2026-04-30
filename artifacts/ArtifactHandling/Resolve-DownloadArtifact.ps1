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
        $logBatch = [System.Collections.Generic.List[ArtifactsLogEntry]]::new()

        $flushLog = {
            if ($logBatch.Count) {
                $logBatch | Add-ArtifactsLog -Quiet
                $logBatch.Clear()
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
                Push-Telemetry -Operation "Download Artifact" -Telemetry $Object -TelemetryClient $TelemetryClient
            }
            ($Object.GetType() -eq [ArtifactsLogEntry]) {
                $Object | Write-ArtifactsLog
                $logBatch.Add($Object)
            }
            default {
                & $flushLog
                $Object
            }
        }
    }

    end {
        try {
            & $flushLog
        } catch {
            Write-Warning "Resolve-DownloadArtifact: Failed to flush remaining entries: $_"
        }
    }
}
Export-ModuleMember -Function Resolve-DownloadArtifact