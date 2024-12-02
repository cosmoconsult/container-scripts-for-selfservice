function Push-Telemetry {
    [CmdletBinding()]
    param (
        [string]$Operation,
        [object]$Telemetry,
        [System.Object]$TelemetryClient = $null
    )
    
    begin {
        if (! $TelemetryClient) {
            $TelemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        if ($TelemetryClient -and $Operation) {
            $TelemetryClient.Context.Operation.Id = $Operation
            $TelemetryClient.Context.Operation.Name = $Operation
        }
    }
    
    process {
        if (! $TelemetryClient -or ! $Telemetry) { return }
        try {
            $TelemetryClient.Track($Telemetry)
        }
        catch {
            Write-Warning "Push-Telemetry failed"
            
            if ($Data.GetType() -ne [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]) {
                $exceptionTelemetry = New-ExceptionTelemetry -Exception $_.Exception
                Push-Telemetry -Operation "Push-Telemetry" -Data $exceptionTelemetry -TelemetryClient $TelemetryClient
            }
        }
    }
    
    end {
        if ($TelemetryClient) {
            try {
                $TelemetryClient.Flush()
            }
            catch {
                Write-Warning "Push-Telemetry failed"
            }
        }
    }
}
Export-ModuleMember -Function Push-Telemetry