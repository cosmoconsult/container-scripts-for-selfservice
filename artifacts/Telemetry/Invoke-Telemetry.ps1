function Invoke-Telemetry {
    [CmdletBinding()]
    param (
        [string]$operation,
        [object]$data,
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        if ($telemetryClient -and $operation) {
            $telemetryClient.Context.Operation.Id = $operation
            $telemetryClient.Context.Operation.Name = $operation
        }
    }
    
    process {
        if (! $telemetryClient -or ! $data) { return }
        try {
            $telemetryClient.Track($data)
        }
        catch {
            Write-Warning "Invoke-Telemetry failed"
            Invoke-LogError -telemetryClient $telemetryClient -exception $_.Exception
        }
    }
    
    end {
        if ($telemetryClient) {
            try {
                $telemetryClient.Flush()
            }
            catch {
                Write-Warning "Invoke-Telemetry failed"
            }
        }
    }
}
Export-ModuleMember -Function Invoke-Telemetry