function Invoke-LogEvent {
    [CmdletBinding()]
    param (
        [Alias("Event", "Operation")]
        [string]$name,
        [hashtable]$properties = @{},
        [hashtable]$metrics = @{},
        [System.Object]$telemetryClient = $null  
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        if ($telemetryClient -and $operation) {
            $telemetryClient.Context.Operation.Id = $name
            $telemetryClient.Context.Operation.Name = $name
        }
        $request = New-EventTelemetry -name $name -properties $properties -metrics $metrics
    }
    
    process {
        if (! $telemetryClient -or ! $request) { return }
        try {
            $telemetryClient.Track($request)
        }
        catch {
            Write-Warning "Invoke-LogEvent failed"
            Invoke-LogError -telemetryClient $telemetryClient -exception $_.Exception
        }
    }
    
    end {
        if ($telemetryClient) {
            try {
                $telemetryClient.Flush()
            }
            catch {
                Write-Warning "Invoke-LogEvent failed"
            }
        }
    }
}
Export-ModuleMember -Function Invoke-LogEvent