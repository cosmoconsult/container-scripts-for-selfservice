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
        try {
            $request = [Microsoft.ApplicationInsights.DataContracts.EventTelemetry]::new()
            $request.Name = $name
        }
        catch {
            $request = $null
        }
        if ($request) {            
            $request.Timestamp = Get-Date            
        }
    }
    
    process {
        if (! $telemetryClient -or ! $request) { return }
        try {
            $request.Name = "$operation"
            $properties.Keys | ForEach-Object { $request.Properties[$_] = $properties[$_] }
            $metrics.Keys    | ForEach-Object { $request.Metrics[$_] = $metrics[$_] }
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