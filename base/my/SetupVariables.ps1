if (($env:cosmoServiceRestart -eq $false) -and ![string]::IsNullOrWhiteSpace($env:bakfile)) {
    Write-Host "Increasing SQL timeout to 600 seconds for database backup restore"
    $env:SqlTimeout = "600"
}

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)