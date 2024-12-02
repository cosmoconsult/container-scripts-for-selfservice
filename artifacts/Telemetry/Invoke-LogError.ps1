function Invoke-LogError {
    [CmdletBinding()]
    param (
        [System.Exception]$exception,
        [hashtable]$properties = @{},
        [System.Object]$telemetryClient = $null,
        [Parameter(Mandatory = $false)]
        [Alias("Event", "Name")]
        [string]$operation = $null
    )

    $exceptionTelemetry = New-ExceptionTelemetry -Exception $exception -Properties $properties
    Push-Telemetry -Data $exceptionTelemetry -TelemetryClient $telemetryClient
}
Set-Alias -Name Invoke-LogException -Value Invoke-LogError
Export-ModuleMember -Function Invoke-LogError -Alias Invoke-LogException