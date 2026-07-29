if (!(Test-Path "C:\CosmoSetupCompleted.txt")) {
    New-Item "C:\CosmoSetupCompleted.txt" -type "file" | Out-Null
    Write-Host "Set marker for health check"
}