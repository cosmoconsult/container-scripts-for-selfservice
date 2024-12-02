function Invoke-LogEvent {
    [CmdletBinding()]
    param (
        [Alias("Event", "Operation")]
        [string]$name,
        [hashtable]$properties = @{},
        [hashtable]$metrics = @{},
        [System.Object]$telemetryClient = $null  
    )
    
    $eventTelemetry = New-EventTelemetry -Name $name -Properties $properties -Metrics $metrics
    Push-Telemetry -Operation $name -Data $eventTelemetry -TelemetryClient $telemetryClient
}
Export-ModuleMember -Function Invoke-LogEvent