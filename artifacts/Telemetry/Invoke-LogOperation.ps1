function Invoke-LogOperation {
    [CmdletBinding()]
    param (
        [Alias("Operation")]
        [string]$name,
        [string]$started = $null,
        [string]$ended = $null,
        [hashtable]$properties = @{},
        [hashtable]$metrics = @{},        
        [bool]$success = $true,
        [System.Object]$telemetryClient = $null        
    )
        
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        if ($telemetryClient -and $name) {
            $telemetryClient.Context.Operation.Id = $name
            $telemetryClient.Context.Operation.Name = $name
        }
        try {
            $request = [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry]::new()
            $request.Name = $name
        }
        catch {
            $request = $null
        }
        try {
            $started = Get-Date -Date "$started" -Format "o"
        }
        catch {
            $started = Get-Date -Format "o"
        }
        try {
            $ended = Get-Date -Date "$ended" -Format "o"
        }
        catch {
            $ended = Get-Date -Format "o"
        }
        if ($started -and $ended -and $request) {
            $duration = (Get-Date -Date $ended) - (Get-Date -Date $started)
            $request.StartTime = $started            
            $request.Duration = $duration            
        }
    }
    
    process {
        if (! $telemetryClient -or ! $request) { return }
        try {
            $request.Success = $success
            $properties.Keys | ForEach-Object { $request.Properties[$_] = $properties[$_] }
            $metrics.Keys    | ForEach-Object { $request.Metrics[$_] = $metrics[$_] }
            $telemetryClient.Track($request)
        }
        catch {
            Write-Warning "Invoke-LogOperation failed"
            Invoke-LogError -telemetryClient $telemetryClient -exception $_.Exception
        }
    }
    
    end {
        if ($telemetryClient) {
            try {
                $telemetryClient.Flush()
            }
            catch {
                Write-Warning "Invoke-LogOperation failed"
            }
        }
    }
}
Set-Alias -Name Invoke-LogRequest -Value Invoke-LogOperation
Export-ModuleMember -Function Invoke-LogOperation -Alias Invoke-LogRequest