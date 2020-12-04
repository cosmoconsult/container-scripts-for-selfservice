function Invoke-LogError {
    [CmdletBinding()]
    param (
        [System.Exception]$exception,
        [hashtable]$properties = @{},
        [System.Object]$telemetryClient = $null,
        [Parameter(Mandatory=$false)]
        [Alias("Event", "Name")]
        [string]$operation = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
        if ($telemetryClient -and $operation) {
            $telemetryClient.Context.Operation.Id   = $operation
            $telemetryClient.Context.Operation.Name = $operation
        }
    }
    
    process {
        if (! $telemetryClient) { return }
        try {
            $dict = New-Object 'System.Collections.Generic.Dictionary[String,String]'
            if ($properties) { $properties.Keys | ForEach-Object { $dict[$_] = $properties[$_] } }
            $telemetryClient.TrackException($exception, $dict, $null)
        }
        catch {
            Write-Warning "Invoke-LogError failed"
        }
    }
    
    end {
        if ($telemetryClient) {
            try {
                $telemetryClient.Flush()
            }
            catch {
                Write-Warning "Invoke-LogError failed"
            }
        }
    }
}
Set-Alias -Name Invoke-LogException -Value Invoke-LogError
Export-ModuleMember -Function Invoke-LogError -Alias Invoke-LogException