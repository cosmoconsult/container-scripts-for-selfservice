<#
 .Synopsis
  Get the App information as json
 .Description
  Get the App information as json file and saves it to C:\inetpub\wwwroot\http
 .Example
  Get-AppInfo
#>
function Get-AppInfo {
    [CmdletBinding()]
    Param ()

    Write-Host "Getting app info"

    $appInfoFolder = "C:\inetpub\wwwroot\http"
    if (!(Test-Path $appInfoFolder)) {
        New-Item $appInfoFolder -ItemType Directory | Out-Null
    }
    $appInfoFilename = ("appInfo" + [DateTime]::Now.ToString("yyyy-MM-ddHH.mm.ss") + ".json")
    $appInfoPath = Join-Path $appInfoFolder $appInfoFilename
  
    Get-NavAppInfo -ServerInstance BC -Tenant default -TenantSpecificProperties | Select-Object @{Name = 'Id'; Expression = { $_.AppId.ToString() } }, Name, Publisher, @{Name = 'Version'; Expression = { $_.Version.ToString() } } | ConvertTo-Json -Compress | Set-Content -Path $appInfoPath -Force
    
    Write-Host "got appinfo"
    Write-Host ("Apps:" + $appInfoFilename)
}

Export-ModuleMember -Function Get-AppInfo