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
    }

    process {
        if (! $Object) {
            return
        }

        switch ($true) {
            ($Object.GetType() -in @([Microsoft.ApplicationInsights.DataContracts.EventTelemetry], [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry], [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry])) {
                Write-ArtifactsLogBatch
                Push-Telemetry -Operation "Download Artifact" -Telemetry $Object -TelemetryClient $TelemetryClient
            }
            ($Object.GetType() -eq [ArtifactsLogEntry]) {
                $Object | Write-ArtifactsLog
                Push-ArtifactsLogBatch $Object
            }
            default {
                Write-ArtifactsLogBatch
                $Object
            }
        }
    }

    end {
        Write-ArtifactsLogBatch
    }
}
Export-ModuleMember -Function Resolve-DownloadArtifact