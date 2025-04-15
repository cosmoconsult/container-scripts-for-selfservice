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

    $startTime = try { Get-Date $started } catch { Get-Date }
    $endTime = try { Get-Date $ended } catch { Get-Date }
    
    $requestTelemetry = New-RequestTelemetry -Name $name -StartTime $startTime -EndTime $endTime -Properties $properties -Metrics $metrics -Success $success
    Push-Telemetry -Operation $name -Telemetry $requestTelemetry -TelemetryClient $telemetryClient
}
Set-Alias -Name Invoke-LogRequest -Value Invoke-LogOperation
Export-ModuleMember -Function Invoke-LogOperation -Alias Invoke-LogRequest