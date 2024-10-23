function Move-Database {
    param (
        $databaseToMove
    )

    Write-Host " - Moving SaaS database to volume"
    if (($env:volPath -ne "") -and (Test-Path $env:volPath)) {
        $volPath = $env:volPath
        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Common") | Out-Null
        $dummy = new-object Microsoft.SqlServer.Management.SMO.Server
        $sqlConn = new-object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList "$DatabaseServer\$DatabaseInstance"
        $smo = new-object Microsoft.SqlServer.Management.SMO.Server($sqlConn)
        $smo.Databases | Where-Object { $_.Name -eq $databaseToMove } | ForEach-Object {
            # set recovery mode and shrink log
            $sqlcmd = "ALTER DATABASE [$($_.Name)] SET RECOVERY SIMPLE WITH NO_WAIT"
            & sqlcmd -S 'localhost\SQLEXPRESS' -Q $sqlcmd
            $shrinkCmd = "USE [$($_.Name)]; "
            $_.LogFiles | ForEach-Object {
                $shrinkCmd += "DBCC SHRINKFILE (N'$($_.Name)' , 10) WITH NO_INFOMSGS"
                & sqlcmd -S 'localhost\SQLEXPRESS' -Q $shrinkCmd
            }

            Write-Host " - - Moving $($_.Name)"
            $toCopy = @()
            $dbPath = Join-Path -Path $volPath -ChildPath $_.Name
            New-Item $dbPath -Type Directory -Force | Out-Null
            $_.FileGroups | ForEach-Object {
                $_.Files | ForEach-Object {
                    $destination = (Join-Path -Path $dbPath -ChildPath ($_.Name + '.' + $_.FileName.SubString($_.FileName.LastIndexOf('.') + 1)))
                    $toCopy += , @($_.FileName, $destination)
                    $_.FileName = $destination
                } 
            }
            $_.LogFiles | ForEach-Object {
                $destination = (Join-Path -Path $dbPath -ChildPath ($_.Name + '.' + $_.FileName.SubString($_.FileName.LastIndexOf('.') + 1)))
                $toCopy += , @($_.FileName, $destination)
                $_.FileName = $destination
            }

            $_.Alter()
            try {
                $db = $_
                $_.SetOffline()
            }
            catch {
                $db.Refresh()
                if ($db.Status -ne "Offline") {
                    Write-Warning "Database $($db.Name) is not offline!"
                }
            }

            $toCopy | ForEach-Object {
                Move-Item -Path $_[0] -Destination $_[1]
            }
            
            $_.SetOnline()
        }
        $smo.ConnectionContext.Disconnect()
    }

}

if ($env:cosmoUpgradeSysApp) {
    Write-Host "System application upgrade requested"
    if (!$TenantId) { $TenantId = "default" }
    $sysAppInstallInfo = Get-NAVAppInfo -ServerInstance BC -Name "System Application" -Publisher "Microsoft"
    if ($sysAppInstallInfo) {
        Write-Host "  Uninstall the previous system application with dependencies"
        Uninstall-NAVApp -ServerInstance BC -Name "System Application" -Publisher "Microsoft" -Force -Tenant $TenantId
    }
    else {
        Write-Host "  No previous system application found"
    }
    $sysAppInfoFS = Get-NAVAppInfo -Path 'C:\Applications\system application\source\Microsoft_System Application.app'
    Write-Host "  Publish the new system application $($sysAppInfoFS.Version)"
    Publish-NAVApp -ServerInstance BC -Path 'C:\Applications\system application\source\Microsoft_System Application.app'
    Write-Host "  Sync the new system application"
    Sync-NAVApp -ServerInstance BC -Name "System Application" -Publisher "Microsoft" -Version $sysAppInfoFS.Version -Tenant $TenantId
    Write-Host "  Start data upgrade for the system application"
    Start-NAVAppDataUpgrade -ServerInstance BC -Name "System Application" -Publisher "Microsoft" -Version $sysAppInfoFS.Version -Tenant $TenantId
    Write-Host "  Install the new system application"
    Install-NAVApp -ServerInstance BC -Name "System Application" -Publisher "Microsoft" -Version $sysAppInfoFS.Version -Tenant $TenantId

    Write-Host    "Set NAVApplication version '$($sysAppInfoFS.Version)' in Serverinstance 'BC'."
    Set-NAVApplication -ApplicationVersion "$($sysAppInfoFS.Version)" -ServerInstance BC -Force -ErrorAction Stop
    Sync-NAVTenant -ServerInstance BC -Mode Sync -Force -ErrorAction Stop -Tenant $TenantId
    Start-NAVDataUpgrade -SkipUserSessionCheck -FunctionExecutionMode Serial -ServerInstance BC -SkipAppVersionCheck -Force -ErrorAction Stop -Tenant $TenantId
    Wait-DataUpgradeToFinish -ServerInstance BC -ErrorAction Stop -Tenant $TenantId

    Write-Host    "Check data upgrade is executed"
    Set-NavServerInstance -ServerInstance BC -Restart
    Check-DataUpgradeExecuted -ServerInstance BC -RequiredTenantDataVersion "$($sysAppInfoFS.Version)"

    if ($env:mode -ne "4ps") {
        Write-Host " - Syncing all apps"
        do {
            $unsyncedApps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $tenantId -TenantSpecificProperties | Where-Object { $_.SyncState -ne "Synced" }
            $unsyncedApps | Sync-NAVApp -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        } while ($unsyncedApps.Count -gt 0)

        Write-Host " - Upgrading all apps"
        do {
            $upgradeableApps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $tenantId -TenantSpecificProperties | Where-Object { $_.NeedsUpgrade -eq $true }
            $upgradeableApps | Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction SilentlyContinue
        } while ($upgradeableApps.Count -gt 0)

        Write-Host " - Installing all apps"
        do {
            $uninstalledApps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $tenantId -TenantSpecificProperties | Where-Object { $_.IsInstalled -eq $false }
            $uninstalledApps | Install-NAVApp -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction SilentlyContinue
        } while ($uninstalledApps.Count -gt 0)
    }
}


Write-Host ""
Write-Host "=== Additional Setup ==="

$ppiau = Get-Module -Name PPIArtifactUtils
if (-not $ppiau) {
    if (Test-Path "c:\run\PPIArtifactUtils.psd1") {
        Write-Host "Import PPI Setup Utils from c:\run\PPIArtifactUtils.psd1"
        Import-Module "c:\run\PPIArtifactUtils.psd1" -DisableNameChecking -Force
    }
}

if (Test-Path "$serviceTierFolder") {
    Write-Host "Import Management Utils from $serviceTierFolder\Microsoft.Dynamics.Nav.Management.psd1"
    Import-Module "$serviceTierFolder\Microsoft.Dynamics.Nav.Management.psd1" -Force -ErrorAction SilentlyContinue -DisableNameChecking
    if (Test-Path "$serviceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1") {
        Write-Host "Import App Management Utils from $serviceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1"
        Import-Module "$serviceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1" -Force -DisableNameChecking
    }
    elseif (Test-Path "$serviceTierFolder\Management\Microsoft.Dynamics.Nav.Apps.Management.psd1") {
        Write-Host "Import App Management Utils from $serviceTierFolder\Management\Microsoft.Dynamics.Nav.Apps.Management.psd1"
        Import-Module "$serviceTierFolder\Management\Microsoft.Dynamics.Nav.Apps.Management.psd1" -Force -DisableNameChecking
    }
}
if (Test-Path "$roleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1") {
    Write-Host "Import Nav IDE from $roleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1"
    Import-Module "$roleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1" -Force -ErrorAction SilentlyContinue -DisableNameChecking
}

if ((Test-Path 'c:\run\cosmo.compiler.helper.psm1') -and ($env:IsBuildContainer)) {
    Write-Host "Import compiler helper c:\run\cosmo.compiler.helper.psm1"
    Import-Module 'c:\run\cosmo.compiler.helper.psm1' -DisableNameChecking -Force
}

$env:nugetImported = $false

$targetDir = "C:\run\my\apps"
$targetDirManuallySorted = "C:\run\my\manuallysorted-apps"
$telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
$properties = @{}

Invoke-LogEvent -name "AdditionalSetup - Started" -telemetryClient $telemetryClient

# Show installed apps
Write-Host "##[group]Initially installed apps"
Get-NAVAppInfo -Tenant default -TenantSpecificProperties -ServerInstance BC
Write-Host "##[endgroup]"

# Download Artifacts
try {
    Write-Host "##[group]Download Artifacts"
    $started = Get-Date -Format "o"
    $artifacts = Get-ArtifactsFromEnvironment -path $targetDir -telemetryClient $telemetryClient -ErrorAction SilentlyContinue
    $artifacts | Where-Object { "$($_.target)".ToLower() -ne "bak" -and "$($_.target)".ToLower() -ne "saasbak" -and ($_.name -eq $null -or ($_.name -ne $null -and !($_.name.StartsWith("sortorder")))) } | Invoke-DownloadArtifact -destination $targetDir -telemetryClient $telemetryClient -ErrorAction SilentlyContinue
    $artifacts | Where-Object { $_.name -ne $null -and $_.name.StartsWith("sortorder") } | Invoke-DownloadArtifact -destination $targetDirManuallySorted -telemetryClient $telemetryClient -ErrorAction SilentlyContinue
 
    $properties["artifacts"] = ($artifacts | ConvertTo-Json -Depth 50 -ErrorAction SilentlyContinue)
    Invoke-LogOperation -name "AdditionalSetup - Get Artifacts" -started $started -telemetryClient $telemetryClient -properties $properties
    $installModifiedBaseAppManually = $null -ne ($artifacts | Where-Object { $null -ne $_.name -and $_.name -like "*_4PS Construct DE_*" })
}
catch {
    Add-ArtifactsLog -message "Download Artifacts Error: $($_.Exception.Message)" -severity Error
}
finally {
    Add-ArtifactsLog -message "Download Artifacts done."
    Write-Host "##[endgroup]"
}

# Initialize company
if ($env:mode -eq "4ps") {
    $files = Get-DemoDataFiles
    foreach ($demoDataFile in $files) {
        $demoDataFileName = $demoDataFile | ForEach-Object { $_.Name }
        "  Using XML file {0}" -f $demoDataFile.FullName | Write-Host 
        if ($demoDataFileName -match 'DemoData_(.*)_.xml') {
            $companyName = $Matches[1]
            Write-Host "  Create company $companyName"
            New-NAVCompany -CompanyName $companyName -ServerInstance BC
        }
    }
}

# If SaaS backup for 4PS (modified base app), we need to remove all apps and reinstall the System App first
if ((![string]::IsNullOrEmpty($env:saasbakfile) -or $installModifiedBaseAppManually) -and $env:mode -eq "4ps" -and $env:cosmoServiceRestart -eq $false) {
    Write-Host "Identified SaaS Backup and 4PS mode, removing all apps to cleanly rebuild later"
    Unpublish-AllNavAppsInServerInstance
    $sysAppInfoFS = Get-NAVAppInfo -Path 'C:\Applications\system application\source\Microsoft_System Application.app'
    Write-Host "  Publish the system application $($sysAppInfoFS.Version)"
    Publish-NAVApp -ServerInstance BC -Path 'C:\Applications\system application\source\Microsoft_System Application.app'
    Write-Host "  Sync the system application"
    Sync-NAVApp -ServerInstance BC -Name "System Application" -Publisher "Microsoft" -Version $sysAppInfoFS.Version
    Write-Host "  Install the system application"
    Install-NAVApp -ServerInstance BC -Name "System Application" -Publisher "Microsoft" -Version $sysAppInfoFS.Version
}

# Import Artifacts
try {
    $SyncMode = $env:IMPORT_SYNC_MODE
    $Scope = $env:IMPORT_SCOPE
    if (! ($SyncMode -in @("Add", "ForceSync")) ) { $SyncMode = "Add" }
    if (! ($Scope -in @("Global", "Tenant")) ) { $Scope = "Global" }
    if ($env:mode -eq "4ps") {
        $env:AppExcludeExpr = "I_DONT_WANT_TO_EXCLUDE_ANYTHING"
    }

    Import-Artifacts `
        -Path            $targetDirManuallySorted `
        -NavServiceName  $NavServiceName `
        -ServerInstance  $ServerInstance `
        -Tenant          $TenantId `
        -SyncMode        $SyncMode `
        -Scope           "Global" `
        -telemetryClient $telemetryClient `
        -ErrorAction     SilentlyContinue `
        -SkipFontImport  $true

    Import-Artifacts `
        -Path            $targetDir `
        -NavServiceName  $NavServiceName `
        -ServerInstance  $ServerInstance `
        -Tenant          $TenantId `
        -SyncMode        $SyncMode `
        -Scope           $Scope `
        -telemetryClient $telemetryClient `
        -ErrorAction     SilentlyContinue
}
catch {
    Write-Host "Import Artifacts Error: $($_.Exception.Message)" -f Red
}
finally {
    Write-Host "Import Artifacts done."
}

$artifactSettings = "c:\run\ArtifactSettings.ps1"
Set-Content $artifactSettings -Value ("# Container Settings from Additional setup")
Add-Content $artifactSettings -Value ('$NavServiceName   = "' + "$NavServiceName" + '"')
Add-Content $artifactSettings -Value ('$ServerInstance   = "' + "$ServerInstance" + '"')
Add-Content $artifactSettings -Value ('$DatabaseServer   = "' + "$databaseServer" + '"')
Add-Content $artifactSettings -Value ('$DatabaseInstance = "' + "$databaseInstance" + '"')
Add-Content $artifactSettings -Value ('$DatabaseName     = "' + "$DatabaseName" + '"')
Add-Content $artifactSettings -Value ('$TenantId         = "' + "$TenantId" + '"')
Add-Content $artifactSettings -Value ('$SyncMode         = "' + "$SyncMode" + '"')
Add-Content $artifactSettings -Value ('$Scope            = "' + "$Scope" + '"')

if ($env:IsBuildContainer) {
    Setup-Compiler
}

$enablePerformanceCounter = $($env:enablePerformanceCounter)
if ([string]::IsNullOrEmpty($env:enablePerformanceCounter)) {
    $enablePerformanceCounter = "true"
} 

if ($enablePerformanceCounter.ToLower() -eq "true") {
    Write-Host "Start Performance Data Collection"
    $DCSName = "BC" 

    if ($newPublicDnsName) {
        [xml]$doc = New-Object System.Xml.XmlDocument
        $root = $doc.CreateNode("element", "PerformanceCounterDataCollector", $null)
        "\Microsoft Dynamics NAV($ServerInstance)\% Primary key cache hit rate",
        "\Microsoft Dynamics NAV($ServerInstance)\# Active sessions",
        "\Microsoft Dynamics NAV($ServerInstance)\% Command cache hit rate",
        "\process(microsoft.dynamics.nav.server)\% processor time",
        "\.NET CLR Memory(microsoft.dynamics.nav.server)\# Total committed Bytes" | % {
            $root.AppendChild($doc.CreateElement('Counter')).InnerText = $_
        }
        $doc.AppendChild($root) | Out-Null

        $server = $env:COMPUTERNAME
    
        Write-Host "Running Perfmon-Collector to create / update Perfmon Data Collector Set $DCSName on $Server" -ForegroundColor Green
        $SubDir = "C:\ProgramData\BCContainerHelper\PerfmonLogs"
        If (!(Test-Path -PathType Container $SubDir)) {
            New-Item -ItemType Directory -Path $SubDir | Out-Null
        }
        $DCS = New-Object -COM Pla.DataCollectorSet

        Write-Host "Creating the $DCSName Data Collector Set"
        $DCS.DisplayName = $DCSName
        $DCS.Segment = $true
        $DCS.SegmentMaxDuration = 86400
        $DCS.SubdirectoryFormat = 1
        $DCS.RootPath = $SubDir
        $DCS.SetCredentials($null, $null)
        $DCS.Commit($DCSName, $Server, 3) | Out-Null
        $DCS.Query($DCSName, $Server)

        $DC = $DCS.DataCollectors.CreateDataCollector(0)
        $DC.Name = $DCSName
        $DC.FileName = $DCSName + "_"
        $DC.FileNameFormat = 3
        $DC.FileNameFormatPattern = "yyyyMMddHHmmss"
        $DC.SampleInterval = 5
        $DC.LogFileFormat = 3
        $DC.SetXML($doc.OuterXml)
        $DCS.DataCollectors.Add($DC)
        $DCS.SetCredentials($null, $null)
        $DCS.Commit($DCSName, $Server, 3) | Out-Null
        $DCS.Query($DCSName, $Server)

        Write-Host "Starting the $DCSName Data Collector Set"
        Start-SMPerformanceCollector -CollectorName $DCSName
    }
    elseif ($restartingInstance) {
        Write-Host "Starting the $DCSName Data Collector Set"
        Start-SMPerformanceCollector -CollectorName $DCSName
    }
}

$excludeAppsFromSaaSBak = @(
    [pscustomobject]@{
        Name   = "CKL Monetization";
        Id     = '2d648cd3-1779-449a-b0eb-23a98267d85e';
        Reason = "works only on SaaS"
    },
    [pscustomobject]@{
        Name   = "_Exclude_AnonymizedDataSharing_";
        Id     = '063b3ac9-c464-4899-96e0-70d5425854e4';
        Reason = "works only on SaaS"
    },
    [pscustomobject]@{
        Name   = "4PS Document API (DEPRECATED) W1";
        Id     = '40409ec8-f051-4b5b-bcb9-8ef51e1cd1ff';
        Reason = "deprecated"
    },
    [pscustomobject]@{
        Name   = "4PS App API (DEPRECATED) W1";
        Id     = 'dd2d0593-ba8d-4f73-bab1-f51f2daa658d';
        Reason = "deprecated"
    },
    [pscustomobject]@{
        Name   = "4PS Job API (DEPRECATED) W1";
        Id     = 'f8e2d23f-5500-4b0a-b139-8a7b9725334e';
        Reason = "deprecated"
    },
    [pscustomobject]@{
        Name   = "Intelligent Cloud Base";
        Id     = '58623bfa-0559-4bc2-ae1c-0979c29fd9e0';
        Reason = "works only on SaaS"
    },
    [pscustomobject]@{
        Name   = "Business Central Intelligent Cloud";
        Id     = '334ef79e-547e-4631-8ba1-7a7f18e14de6';
        Reason = "works only on SaaS"
    }
)
if ($global:excludeAppsFromSaaSBak -is [array] -and $global:excludeAppsFromSaaSBak.Length -gt 0) {
    $excludeAppsFromSaaSBak += $global:excludeAppsFromSaaSBak
}

if (($env:cosmoServiceRestart -eq $false) -and ![string]::IsNullOrEmpty($env:saasbakfile)) {
    Write-Host "HANDLING SaaS BAKFILE"

    $bak = $env:saasbakfile
    $tenantId = "saas"
    
    if (!$databaseFolder) {
        $databaseFolder = "c:\databases\my"
    }
    
    if (!(Test-Path -Path $databaseFolder -PathType Container)) {
        New-Item -Path $databaseFolder -itemtype Directory | Out-Null
    }
    
    Write-Host " - Restoring SaaS DB to $databaseFolder"
    New-NAVDatabase -DatabaseServer $DatabaseServer `
        -DatabaseInstance $DatabaseInstance `
        -DatabaseName "$tenantId" `
        -FilePath "$bak" `
        -DestinationPath "$databaseFolder" `
        -Timeout $SqlTimeout -Force | out-null
    
    Write-Host " - Adapting package IDs"
    $diffPackageIds = Invoke-Sqlcmd -Query "select da.[App ID], da.[Package ID] FROM [default].[dbo].[NAV App Installed App] da JOIN [$tenantId].[dbo].[NAV App Installed App] ta ON da.[App ID] = ta.[App ID] AND da.[Version Major] = ta.[Version Major] AND da.[Version Minor] = ta.[Version Minor] AND da.[Version Build] = ta.[Version Build] AND da.[Version Revision] = ta.[Version Revision] AND da.[Package ID] != ta.[Package ID]" -ServerInstance "$DatabaseServer\$DatabaseInstance"
    foreach ($app in $diffPackageIds) {
        Invoke-Sqlcmd -Database $tenantId -Query "UPDATE [dbo].[NAV App Installed App] SET [Package ID] = '$($app.'Package ID')' WHERE [App ID] = '$($app.'App ID')'" -ServerInstance "$DatabaseServer\$DatabaseInstance"
    }

    foreach ($excludeApp in $excludeAppsFromSaaSBak) {
        Write-Host "   - Removing app '$($excludeApp.Name)' if installed, reason '$($excludeApp.Reason)', id '$($excludeApp.Id)'"
        Invoke-Sqlcmd -Database $tenantId -Query "DELETE FROM [dbo].[NAV App Published App] WHERE [App ID] = '$($excludeApp.Id)'" -ServerInstance "$DatabaseServer\$DatabaseInstance"
        Invoke-Sqlcmd -Database $tenantId -Query "DELETE FROM [dbo].[NAV App Installed App] WHERE [App ID] = '$($excludeApp.Id)'" -ServerInstance "$DatabaseServer\$DatabaseInstance"
    }

    Write-Host " - Replacing default tenant database with new SaaS database"
    Dismount-NAVTenant -ServerInstance $ServerInstance -Tenant "default" -Force
    Invoke-SqlCmd -Query "alter database [default] set single_user with rollback immediate; DROP DATABASE [default]" -ServerInstance "$DatabaseServer\$DatabaseInstance"
    Invoke-SqlCmd -Query "ALTER DATABASE $tenantId SET SINGLE_USER WITH ROLLBACK IMMEDIATE; ALTER DATABASE $tenantId MODIFY NAME = [default]; ALTER DATABASE [default] SET MULTI_USER" -ServerInstance "$DatabaseServer\$DatabaseInstance"
    $tenantId = "default"

    # move database to volume
    Move-Database -databaseToMove $tenantId

    # special handling for modified base app
    if (![string]::IsNullOrEmpty($env:cosmoBaseAppVersion)) {
        Write-Host "Set application version to $($env:cosmoBaseAppVersion) as this is a modified base app"
        Set-NAVApplication -ApplicationVersion "$($env:cosmoBaseAppVersion)" -ServerInstance BC -Force -ErrorAction Stop

        $collation = "Latin1_General_100_CI_AS"
        Write-Host "Change collation to $collation"
        $navDataFilePath = (Join-Path $volPath "export.navdata")
        Write-Host "Export NAVData"
        Export-NAVData -ApplicationDatabaseServer "$DatabaseServer\$DatabaseInstance" -DatabaseServer "$DatabaseServer\$DatabaseInstance" -ApplicationDatabaseName "CRONUS" -IncludeApplication -IncludeApplicationData -FilePath $navDataFilePath
        Write-Host "Create new database with collation $collation"
        Invoke-SqlCmd -Query "CREATE DATABASE [CronusNew] COLLATE $collation" -ServerInstance "$DatabaseServer\$DatabaseInstance"
        Write-Host "Import NAVData"
        Import-NAVData -ApplicationDatabaseServer "$DatabaseServer\$DatabaseInstance" -DatabaseServer "$DatabaseServer\$DatabaseInstance" -ApplicationDatabaseName "CronusNew" -IncludeApplication -IncludeApplicationData -FilePath $navDataFilePath -Force
        Write-Host "Stop server instance"
        Stop-NAVServerInstance BC
        Write-Host "Replace CRONUS database"
        Invoke-SqlCmd -Query "alter database [CRONUS] set single_user with rollback immediate; DROP DATABASE [CRONUS]" -ServerInstance "$DatabaseServer\$DatabaseInstance"
        Invoke-SqlCmd -Query "ALTER DATABASE CronusNew SET SINGLE_USER WITH ROLLBACK IMMEDIATE; ALTER DATABASE CronusNew MODIFY NAME = [CRONUS]; ALTER DATABASE [CRONUS] SET MULTI_USER" -ServerInstance "$DatabaseServer\$DatabaseInstance"
        Remove-Item (Join-Path $volPath "CRONUS") -recurse -force
        Move-Database -databaseToMove "CRONUS"
        Write-Host "Start server instance"
        Start-NAVServerInstance BC
    }

    Write-Host " - Mounting SaaS tenant"
    Mount-NavTenant `
        -ServerInstance $ServerInstance `
        -id $tenantId `
        -databasename $tenantId `
        -databaseserver $DatabaseServer `
        -databaseinstance $DatabaseInstance `
        -EnvironmentType Sandbox `
        -OverwriteTenantIdInDatabase `
        -Force
        
    Write-Host " - Syncing new tenant"
    Sync-NavTenant `
        -ServerInstance $ServerInstance `
        -Tenant $tenantId `
        -Force

    Write-Host " - Syncing all apps"
    do {
        $unsyncedApps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $tenantId -TenantSpecificProperties | Where-Object { $_.SyncState -ne "Synced" }
        $unsyncedApps | Sync-NAVApp -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    } while ($unsyncedApps.Count -gt 0)

    Write-Host " - Upgrading all apps"
    do {
        $upgradeableApps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $tenantId -TenantSpecificProperties | Where-Object { $_.NeedsUpgrade -eq $true }
        $upgradeableApps | Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction SilentlyContinue
    } while ($upgradeableApps.Count -gt 0)

    Write-Host " - Syncing new tenant"
    Sync-NavTenant `
        -ServerInstance $ServerInstance `
        -Tenant $tenantId `
        -Force

    Write-Host " - Upgrading tenant"
    Start-NAVDataUpgrade -SkipUserSessionCheck -FunctionExecutionMode Serial -ServerInstance BC -SkipAppVersionCheck -Force -ErrorAction Stop -Tenant $TenantId
    Wait-DataUpgradeToFinish -ServerInstance BC -ErrorAction Stop -Tenant $TenantId

    Write-Host " - Check data upgrade is executed"
    Set-NavServerInstance -ServerInstance BC -Restart
    
    for ($i = 0; $i -lt 10; $i++) {
        $TenantState = (Get-NavTenant -ServerInstance BC -Tenant $TenantId).State
        if (($TenantState -eq "Mounted") -or ($TenantState -eq "Operational")) {
            break;
        }

        Write-Host " - - Tenant not operational yet (try $i), sleeping 10s"
        Start-Sleep -Seconds 10
    }

    if (![string]::IsNullOrEmpty($env:cosmoBaseAppVersion)) {
        Check-DataUpgradeExecuted -ServerInstance BC -RequiredTenantDataVersion "$($env:cosmoBaseAppVersion)"
    }

    Write-Host " - Deactivate all users to ensure license compliance"
    Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object { $_.UserName.ToLower() -ne $env:username.ToLower() } | % {
        Write-Host " - Disable $($_.UserName)"
        Set-NAVServerUser -UserName $_.UserName -State Disabled -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction Continue
    }

    Write-Host " - Create user in new tenant (if not exists)"
    if (!(Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object { $_.UserName.ToLower() -eq $env:username.ToLower() })) {
        if ($($env:username).indexOf("@") -gt 0) {
            New-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -UserName $env:username -Password $securePassword -AuthenticationEMail $env:username -ErrorAction Continue
        }
        else {
            New-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -UserName $env:username -Password $securePassword -ErrorAction Continue
        }
        New-NAVServerUserPermissionSet -ServerInstance $ServerInstance -Tenant $tenantId -UserName $env:username -PermissionSetId SUPER -ErrorAction Continue
    }
}

if (![string]::IsNullOrEmpty($env:saasbakfile)) {
    # license import also needs to happen on restart in case we got a new license
    Write-Host " - Importing License to tenant"
    Invoke-Sqlcmd -Database $tenantId -Query "truncate table [dbo].[Tenant License State]" -ServerInstance "$DatabaseServer\$DatabaseInstance"
    if ([string]::IsNullOrWhiteSpace($licensefile)) {
        $licenseToImport = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Cronus.*").FullName
    }
    else {
        $licenseToImport = $licensefile
    }
    
    if (Test-Path $licenseToImport) {
        Import-NAVServerLicense -ServerInstance $ServerInstance -Tenant $tenantId -LicenseFile $licenseToImport -Database Tenant
        Set-NAVServerInstance -ServerInstance $ServerInstance -Restart
    }
    else {
        Write-Host "   Couldn't find license file"
    }
}

Invoke-4PSArtifactHandling -username $username -securepassword $securepassword -tenantParam $tenantParam

Invoke-LogEvent -name "AdditionalSetup - Done" -telemetryClient $telemetryClient
Write-Host "=== Additional Setup Done ==="
if (!(Test-Path "C:\CosmoSetupCompleted.txt")) {
    New-Item "C:\CosmoSetupCompleted.txt" -type "file" | Out-Null
    Write-Host "Set marker for health check"
}
Write-Host ""
