# make sure BC is healthy before returning
Write-Host " - Check BC Health"
for ($i = 0; $i -lt 10; $i++) {
    . C:\run\CheckHealth.ps1
    Write-Host " - - CheckHealth returned $LASTEXITCODE, healthCheckBaseUrl is $($env:healthCheckBaseUrl)"
    if ($LASTEXITCODE -in 0, 193) {
        Write-Host " - - BC is healthy"
        break;
    }

    Write-Host " - - BC not healthy yet (try $i), outputting service tier and tenant info, sleeping 30s and trying again"
    Get-NAVServerInstance -ServerInstance $ServerInstance
    Get-NAVTenant -ServerInstance $ServerInstance
    Start-Sleep -Seconds 30
}