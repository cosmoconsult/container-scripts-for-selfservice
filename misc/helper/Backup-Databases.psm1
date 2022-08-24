<# 
 .Synopsis
  Backup databases in a NAV/BC Container as .bak files
 .Description
  If the Container is multi-tenant, this command will create an app.bak and a number of tenant .bak files
  If the Container is single-tenant, this command will create one .bak file called database.bak.
 .Parameter bakFolder
  The folder to which the .bak files are exported (needs to be shared with the container)
 .Parameter tenant
  The tenant database(s) to export, only applies to multi-tenant containers. Omit to export all tenants.
 .Parameter databaseCredential
  database credentials if using an external sQL Server
 .Parameter compress
  Compress the database backup. SQL Express doesn't support compression.
 .Example
  Backup-BcContainerDatabases
 .Example
  Backup-BcContainerDatabases -bakfolder "c:\programdata\bccontainerhelper\extensions\test"
 .Example
  Backup-BcContainerDatabases -tenant @("default")
#>
function Backup-BCDatabases {
    Param ( 
        [string] $bakFolder,
        [string[]] $tenant,
        [pscredential] $databasecredential,
        [switch] $compress
    )

        Write-Host $bakFolder
        $bakFolder.GetType()
        Test-Path $bakFolder

        $customConfigFile = Join-Path (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName "CustomSettings.config"
        [xml]$customConfig = [System.IO.File]::ReadAllText($customConfigFile)
        $multitenant = ($customConfig.SelectSingleNode("//appSettings/add[@key='Multitenant']").Value -eq "true")
        $databaseServer = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseServer']").Value
        $databaseInstance = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseInstance']").Value
        $databaseName = $customConfig.SelectSingleNode("//appSettings/add[@key='DatabaseName']").Value
        
        $databaseServerInstance = $databaseServer
        if ("$databaseInstance" -ne "") {
            $databaseServerInstance = "$databaseServer\$databaseInstance"
        }

        if (!(Test-Path -Path $bakFolder)) {
            New-Item $bakFolder -ItemType Directory | Out-Null
        }

        if ($multitenant) {
            if (!($tenant)) {
                $tenant = @(get-navtenant $serverInstance | % { $_.Id }) + "tenant"
            }
            Backup-BCDatabaseHelper -ServerInstance $databaseServerInstance -database $DatabaseName -bakFolder $bakFolder -bakName "app" -databasecredential $databasecredential -compress:$compress
            $tenant | ForEach-Object {
                $tenantInfo = Get-NAVTenant -ServerInstance $serverInstance $_ -ErrorAction SilentlyContinue
                if ($tenantInfo) {
                    $dbName = $tenantInfo.DatabaseName
                }
                else {
                    $tenantInfo = Get-NAVTenant -ServerInstance $serverInstance default -ErrorAction SilentlyContinue
                    if ($tenantInfo) {
                        $dbName = $tenantInfo.DatabaseName.replace('default',$_)
                    }
                    else {
                        $dbName = $_
                    }
                }
                Backup-BCDatabaseHelper -ServerInstance $databaseServerInstance -database $dbName -bakFolder $bakFolder -bakName $_ -databasecredential $databasecredential -compress:$compress
            }
        } else {
            Backup-BCDatabaseHelper -ServerInstance $databaseServerInstance -database $DatabaseName -bakFolder $bakFolder -bakName "database" -databasecredential $databasecredential -compress:$compress
        }

}


function Backup-BCDatabaseHelper {
    Param (
        $serverInstance,
        $database,
        $bakFolder,
        $bakName,
        [pscredential] $databaseCredential,
        [switch] $compress
    )
    $bakFile = Join-Path $bakFolder "$bakName.bak"
    if (Test-Path $bakFile) {
        Remove-Item -Path $bakFile -Force
    }
    Write-Host "Backing up $database to $bakFile"
    $params = @{}
    if ($compress) { $params += @{ "CompressionOption" = "On" } }
    if ($databaseCredential) { $params += @{ "credential" = $databaseCredential } }
    Backup-SqlDatabase -ServerInstance $serverInstance -database $database -BackupFile $bakFile @params
}
        

Export-ModuleMember -Function Backup-BCDatabases
Export-ModuleMember -Function Backup-BCDatabaseHelper