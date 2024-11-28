function New-EventTelemetry {
    [CmdletBinding()]
    param (
        [string]$name,
        [hashtable]$properties = @{},
        [hashtable]$metrics = @{}
    )
    
    process {
        try {
            $data = [Microsoft.ApplicationInsights.DataContracts.EventTelemetry]::new()
        }
        catch {
            return
        }

        $data.Name = $name
        $data.Timestamp = Get-Date
        $properties.Keys | 
            ForEach-Object { $data.Properties[$_] = $properties[$_] }
        $metrics.Keys    | 
            ForEach-Object { $data.Metrics[$_] = $metrics[$_] }

        return $data
    }
}
Export-ModuleMember -Function New-EventTelemetry