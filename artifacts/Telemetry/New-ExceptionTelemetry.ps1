function New-ExceptionTelemetry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception,
        [DateTime]$Timestamp = [DateTime]::Now,
        [hashtable]$Properties = @{},
        [hashtable]$Metrics = @{}
    )
    
    process {
        try {
            $exceptionTelemetry = [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry]::new()
        }
        catch {
            return
        }

        $exceptionTelemetry.Exception = $Exception
        $exceptionTelemetry.Timestamp = $Timestamp
        $Properties.Keys | 
            ForEach-Object { $exceptionTelemetry.Properties[$_] = $Properties[$_] }
        $Metrics.Keys    | 
            ForEach-Object { $exceptionTelemetry.Metrics[$_] = $Metrics[$_] }

        $exceptionTelemetry
    }
}
Export-ModuleMember -Function New-ExceptionTelemetry