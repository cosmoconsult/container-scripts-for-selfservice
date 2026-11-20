function Get-InstalledApps {
    [CmdletBinding()]
    param (
        [string]$ServerInstance = 'BC',
        [string]$Tenant = 'default',
        [switch]$IncludeMicrosoft,
        [switch]$AsJson
    )

    $apps = @(Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant -TenantSpecificProperties -ErrorAction Stop |
        Where-Object { $_.IsInstalled -and ($IncludeMicrosoft -or $_.Publisher -ne 'Microsoft') })
    if ($AsJson) {
        $apps = @($apps | ForEach-Object {
            [PSCustomObject]@{
                Id        = [string]$_.AppId
                Name      = [string]$_.Name
                Publisher = [string]$_.Publisher
                Version   = [string]$_.Version
            }
        })
        Write-Output ('InstalledApps:' + (ConvertTo-Json -InputObject $apps -Depth 3 -Compress))
    }
    else {
        $apps
    }
}