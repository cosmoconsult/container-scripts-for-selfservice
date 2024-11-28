function New-RequestTelemetry {
    [CmdletBinding()]
    param (
        [string]$name,
        [string]$started = $null,
        [string]$ended = $null,
        [hashtable]$properties = @{},
        [hashtable]$metrics = @{},
        [bool]$success = $true
    )
    
    process {
        try {
            $data = [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry]::new()
        } catch {
            return
        }
        
        $started = Get-DateOrNow -date $started -format "o"
        $ended = Get-DateOrNow -date $ended -format "o"
        $duration = (Get-Date -Date $ended) - (Get-Date -Date $started)

        $data.Name = $name
        $data.StartTime = $started            
        $data.Duration = $duration
        $data.Success = $success
        $properties.Keys | 
            ForEach-Object { $data.Properties[$_] = $properties[$_] }
        $metrics.Keys    | 
            ForEach-Object { $data.Metrics[$_] = $metrics[$_] }

        return $data
    }
}
Export-ModuleMember -Function New-RequestTelemetry

function Get-DateOrNow {
    [CmdletBinding()]
    param (
        [string]$date,
        [string]$format = "o"
    )
    
    try {
        $date = Get-Date -Date "$date" -Format $format
    }
    catch {
        $date = Get-Date -Format $format
    }
    
    return $date
}