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
        $request = New-RequestTelemetry -name $name -started $started -ended $ended -properties $properties -metrics $metrics -success $success
    }
    
    process {
        if (! $telemetryClient -or ! $request) { return }
        try {
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