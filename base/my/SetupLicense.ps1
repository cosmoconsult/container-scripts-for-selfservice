function HandleIssue {
    $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
    if ($null -ne $env:ArtifactUrl -and $env:ArtifactUrl.EndsWith('onprem/26.2.34746.34832/w1')) {
        Invoke-LogEvent -name "SetupLicense, BC Service is not running on a OnPrem 26.2 W1 container" -telemetryClient $telemetryClient
        Write-Error "BC Service is not running on a OnPrem 26.2 W1 container. This is a known issue, typically fixed by a restart. Doing that now."
        Stop-Computer -Force
    }
    else {
        Invoke-LogEvent -name "SetupLicense, BC Service is not running, but this is NOT a OnPrem 26.2 W1 container" -telemetryClient $telemetryClient
        Write-Error "BC Service is not running, but this is NOT a OnPrem 26.2 W1 container. Proceeding with default license setup and hoping for the best."
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
$defaultScript = Join-Path $runPath $MyInvocation.MyCommand.Name
if ([string]::IsNullOrWhiteSpace($env:licensefile)) {
    Write-Host "No license file configured. Skipping license import in SetupLicense."
}
elseif ((Test-Path -LiteralPath $env:licensefile -PathType Leaf) -or $env:licensefile -match '^https?://') {
    . $defaultScript
}
else {
    Write-Host "Configured license file is neither a local file nor an URL. Skipping license import in SetupLicense."
}