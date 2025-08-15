function New-EventTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [DateTime]$Timestamp = [DateTime]::Now,
        [hashtable]$Properties = @{},
        [hashtable]$Metrics = @{}
    )
    
    process {
        try {
            $eventTelemetry = [Microsoft.ApplicationInsights.DataContracts.EventTelemetry]::new()
        }
        catch {
            return
        }

        $eventTelemetry.Name = $Name
        $eventTelemetry.Timestamp = $Timestamp
        if ($Properties) {
            $Properties.Keys | 
                ForEach-Object { $eventTelemetry.Properties[$_] = $Properties[$_] }
        }
        if ($Metrics) {
            $Metrics.Keys    | 
                ForEach-Object { $eventTelemetry.Metrics[$_] = $Metrics[$_] }
        }

        $eventTelemetry
    }
}
Export-ModuleMember -Function New-EventTelemetry