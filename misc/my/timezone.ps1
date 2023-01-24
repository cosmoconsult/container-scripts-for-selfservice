if ($env:mode -eq "4ps") {
    Write-Host "4PS mode, set time zone"
    tzutil /s "W. Europe Standard Time"
}