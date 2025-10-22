function HandleIssue {
    $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
    if ($null -ne $env:ArtifactUrl -and $env:ArtifactUrl.EndsWith('onprem/26.2.34746.34832/w1')) {
        Invoke-LogEvent -name "SetupLicense, BC Service is not running on a OnPrem 26.2 W1 container" -telemetryClient $telemetryClient
        Write-Error "BC Service is not running on a OnPrem 26.2 W1 container. This is a known issue, typically fixed by a restart. Doing that now."
        exit 1
    }
    else {
        Invoke-LogEvent -name "SetupLicense, BC Service is not running, but this is NOT a OnPrem 26.2 W1 container" -telemetryClient $telemetryClient
        Write-Error "BC Service is not running, but this is NOT a OnPrem 26.2 W1 container. Doing nothing and hoping for the best."
    }
}

try {
    $status = Get-NAVServerInstance $ServerInstance
    if ($status.State -ne 'Running') {
        HandleIssue
    }
}
catch {
    HandleIssue
}

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)