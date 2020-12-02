
function Get-TelemetryClient {
    [CmdletBinding()]
    param (
        [bool]$SessionStarted       = $true,
        [string]$InstrumentationKey = "$($env:AZURE_DEVOPS_INSTRUMENTATION_KEY)"
    )
    
    process {
        try {
            $TelemetryClient  = New-Object -TypeName Microsoft.ApplicationInsights.TelemetryClient -ErrorAction SilentlyContinue
        } catch {}
        if ($TelemetryClient) {
            return $TelemetryClient
        } else {
            try {
                @(
                    Get-ChildItem 'C:\Program Files\Microsoft Dynamics NAV\*\Service\*ApplicationInsights.dll' -Recurse -ErrorAction SilentlyContinue
                    Get-ChildItem 'c:\run\my\' -Filter '*ApplicationInsights.dll' -Recurse -ErrorAction SilentlyContinue
                    Get-ChildItem 'c:\PPI\' -Filter '*ApplicationInsights.dll' -Recurse -ErrorAction SilentlyContinue
                    Get-ChildItem "$PSScriptRoot" -Filter *'ApplicationInsights.dll' -Recurse -ErrorAction SilentlyContinue
                ) | ForEach-Object { Add-Type -Path $_.FullName -ErrorAction SilentlyContinue }
                $TelemetryClient = New-Object -TypeName Microsoft.ApplicationInsights.TelemetryClient -ErrorAction SilentlyContinue
            }
            catch {
                Write-Warning "Init Telemetry Client failed: $($_.Exception.Message)"
            }
            if (! $TelemetryClient) { Write-Warning "Init Telemetry Client failed" }
            return $TelemetryClient
        }
    }
    end {
        if ($TelemetryClient) {
            try {
                if ("$InstrumentationKey" -ne "") {
                    $TelemetryClient.InstrumentationKey = $InstrumentationKey
                } else {
                    $TelemetryClient.InstrumentationKey = "f0f88cc5-794d-4c24-a828-b3b4cab5917e"  # ppi-container-self-service AppInsights
                }
                $TelemetryClient.Context.Session.IsFirst = $SessionStarted
                $TelemetryClient.Context.Session.Id = "$($env:COMPUTERNAME)|$($env:USERNAME)"
                $TelemetryClient.Context.User.Id    = "$($env:USERNAME)"
            }
            catch {
                Write-Warning "Init Telemetry Client failed: $($_.Exception.Message)"
            }
        }
    }
}
Export-ModuleMember -Function Get-TelemetryClient