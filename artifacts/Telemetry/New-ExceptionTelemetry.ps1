function New-ExceptionTelemetry {
    [CmdletBinding()]
    param (
        [System.Exception]$exception,
        [hashtable]$properties = @{},
        [hashtable]$metrics = @{}
    )
    
    process {
        try {
            $data = [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]::new()
        }
        catch {
            return
        }

        $data.Timestamp = Get-Date
        $data.Exception = $exception
        $properties.Keys | 
            ForEach-Object { $data.Properties[$_] = $properties[$_] }
        $metrics.Keys    | 
            ForEach-Object { $data.Metrics[$_] = $metrics[$_] }

        return $data
    }
}
Export-ModuleMember -Function New-ExceptionTelemetry