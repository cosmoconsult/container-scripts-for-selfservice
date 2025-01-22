if ($env:mode -eq "4ps") {
    Write-Host "4PS mode, skip setting time zone to W. Europe Standard Time"
    # Write-Host "4PS mode, set time zone"
    # tzutil /s "W. Europe Standard Time"
}