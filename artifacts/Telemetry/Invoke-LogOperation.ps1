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

    $requestTelemetry = New-RequestTelemetry -name $name -started $started -ended $ended -properties $properties -metrics $metrics -success $success
    Push-Telemetry -Operation $name -Telemetry $requestTelemetry -TelemetryClient $telemetryClient
}
Set-Alias -Name Invoke-LogRequest -Value Invoke-LogOperation
Export-ModuleMember -Function Invoke-LogOperation -Alias Invoke-LogRequest