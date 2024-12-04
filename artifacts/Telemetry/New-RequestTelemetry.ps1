function New-RequestTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [DateTime]$Timestamp = [DateTime]::Now,
        [DateTime]$StartTime = $Timestamp,
        [DateTime]$EndTime = $Timestamp,
        [hashtable]$Properties = @{},
        [hashtable]$Metrics = @{},
        [bool]$Success = $true
    )
    
    process {
        try {
            $requestTelemetry = [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry]::new()
        } catch {
            return
        }

        $requestTelemetry.Name = $Name
        $requestTelemetry.Timestamp = $Timestamp
        $requestTelemetry.StartTime = $StartTime            
        $requestTelemetry.Duration = $EndTime - $StartTime
        $requestTelemetry.Success = $Success
        if ($Properties) {
            $Properties.Keys | 
                ForEach-Object { $requestTelemetry.Properties[$_] = $Properties[$_] }
        }
        if ($Metrics) {
            $Metrics.Keys    | 
                ForEach-Object { $requestTelemetry.Metrics[$_] = $Metrics[$_] }
        }

        $requestTelemetry
    }
}
Export-ModuleMember -Function New-RequestTelemetry