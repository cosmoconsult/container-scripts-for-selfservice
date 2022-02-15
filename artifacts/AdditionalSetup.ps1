# Check, if -includeCSide exists, because --volume ""$($programFilesFolder):C:\navpfiles"" is mounted
if ("$($env:includeCSide)" -eq "y" -or (Test-Path "c:\navpfiles\")) {
    Write-Host ""
    Write-Host "=== Additional Setup Freddy ==="
    
    if ($restartingInstance -eq $false -and $databaseServer -eq "localhost" -and $databaseInstance -eq "SQLEXPRESS") {
        sqlcmd -S 'localhost\SQLEXPRESS' -d $DatabaseName -Q "update [dbo].[Object] SET [Modified] = 0" | Out-Null
    }

    if (!(Test-Path "c:\navpfiles\*")) {
        Copy-Item -Path "C:\Program Files (x86)\Microsoft Dynamics NAV\*" -Destination "c:\navpfiles" -Recurse -Force -ErrorAction Ignore
        $destFolder = (Get-Item "c:\navpfiles\*\RoleTailored Client").FullName
        $ClientUserSettingsFileName = "$runPath\ClientUserSettings.config"
        [xml]$ClientUserSettings = Get-Content $clientUserSettingsFileName
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""Server""]").value = "$PublicDnsName"
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ServerInstance""]").value = $ServerInstance
        if ($multitenant) {
            $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""TenantId""]").value = "$TenantId"
        }
        if ($null -ne $clientUserSettings.SelectSingleNode("//appSettings/add[@key=""ServicesCertificateValidationEnabled""]")) {
            $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ServicesCertificateValidationEnabled""]").value = "false"
        }
        if ($null -ne $clientUserSettings.SelectSingleNode("//appSettings/add[@key=""ClientServicesCertificateValidationEnabled""]")) {
            $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ClientServicesCertificateValidationEnabled""]").value = "false"
        }
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ClientServicesPort""]").value = "$publicWinClientPort"
        $acsUri = "$federationLoginEndpoint"
        if ($acsUri -ne "") {
            if (!($acsUri.ToLowerInvariant().Contains("%26wreply="))) {
                $acsUri += "%26wreply=$publicWebBaseUrl"
            }
        }
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ACSUri""]").value = "$acsUri"
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""DnsIdentity""]").value = "$dnsIdentity"
        $clientUserSettings.SelectSingleNode("//configuration/appSettings/add[@key=""ClientServicesCredentialType""]").value = "$Auth"
        $clientUserSettings.Save("$destFolder\ClientUserSettings.config")
    }
    Write-Host "=== Additional Setup Freddy Done ==="
    Write-Host ""    
}

Write-Host ""
Write-Host "=== Additional Setup ==="

if (Test-Path "c:\run\PPIArtifactUtils.psd1") {
    Write-Host "Import PPI Setup Utils from c:\run\PPIArtifactUtils.psd1"
    Import-Module "c:\run\PPIArtifactUtils.psd1" -DisableNameChecking -Force
}

if (Test-Path "$serviceTierFolder") {
    Write-Host "Import Management Utils from $serviceTierFolder\Microsoft.Dynamics.Nav.Management.psd1"
    Import-Module "$serviceTierFolder\Microsoft.Dynamics.Nav.Management.psd1" -Force -ErrorAction SilentlyContinue -DisableNameChecking
    Write-Host "Import App Management Utils from $serviceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1"
    Import-Module "$serviceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1" -Force -ErrorAction SilentlyContinue -DisableNameChecking
}
if (Test-Path "$roleTailoredClientFolder") {
    Write-Host "Import Nav IDE from $roleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1"
    Import-Module "$roleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1" -Force -ErrorAction SilentlyContinue -DisableNameChecking
}

if (Test-Path 'c:\run\cosmo.compiler.helper.psm1')
{
    Write-Host "Import compiler helper c:\run\cosmo.compiler.helper.psm1"
    Import-Module 'c:\run\cosmo.compiler.helper.psm1' -DisableNameChecking -Force
}


$targetDir = "C:\run\my\apps"
$telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
$properties = @{}

Invoke-LogEvent -name "AdditionalSetup - Started" -telemetryClient $telemetryClient
# Download Artifacts
try {
    $started = Get-Date -Format "o"
    $artifacts = Get-ArtifactsFromEnvironment -path $targetDir -telemetryClient $telemetryClient -ErrorAction SilentlyContinue
    $artifacts | Invoke-DownloadArtifact -destination $targetDir -telemetryClient $telemetryClient -ErrorAction SilentlyContinue

    $properties["artifats"] = ($artifacts | ConvertTo-Json -Depth 50 -ErrorAction SilentlyContinue)
    Invoke-LogOperation -name "AdditionalSetup - Get Artifacts" -started $started -telemetryClient $telemetryClient -properties $properties
}
catch {
    Add-ArtifactsLog -message "Donwload Artifacts Error: $($_.Exception.Message)" -severity Error
}
finally {
    Add-ArtifactsLog -message "Donwload Artifacts done."
}

# Import Artifacts
try {
    $SyncMode = $env:IMPORT_SYNC_MODE
    $Scope = $env:IMPORT_SCOPE
    if (! ($SyncMode -in @("Add", "ForceSync")) ) { $SyncMode = "Add" }
    if (! ($Scope -in @("Global", "Tenant")) ) { $Scope = "Global" }

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

$enablePerformanceCounter = $($env:enablePerformanceCounter)
if ([string]::IsNullOrEmpty($env:enablePerformanceCounter)) {
    $enablePerformanceCounter = "true"
} 

if ($enablePerformanceCounter.ToLower() -eq "true") {
    Write-Host "Start Performance Data Collection"
    $DCSName = "BC" 

    if ($newPublicDnsName) {
        [xml]$doc = New-Object System.Xml.XmlDocument
        $root = $doc.CreateNode("element","PerformanceCounterDataCollector",$null)
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
        $DCS.SetCredentials($null,$null)
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
        $DCS.SetCredentials($null,$null)
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

if (($env:cosmoServiceRestart -eq $false) -and ![string]::IsNullOrEmpty($env:saasbakfile))
{
    Write-Host "HANDLING SaaS BAKFILE"

    $bak = $env:saasbakfile
    $tenantId = "saas"
    
    Write-Host " - Restoring SaaS db"
    New-NAVDatabase -DatabaseServer $DatabaseServer `
                        -DatabaseInstance $DatabaseInstance `
                        -DatabaseName "$tenantId" `
                        -FilePath "$bak" `
                        -DestinationPath "$databaseFolder" `
                        -Timeout $SqlTimeout -Force | Out-Null
    
    Write-Host " - Adapting package IDs"
    $diffPackageIds = Invoke-Sqlcmd -Query "select da.[App ID], da.[Package ID] FROM [default].[dbo].[NAV App Installed App] da JOIN [$tenantId].[dbo].[NAV App Installed App] ta ON da.[App ID] = ta.[App ID] AND da.[Version Major] = ta.[Version Major] AND da.[Version Minor] = ta.[Version Minor] AND da.[Version Build] = ta.[Version Build] AND da.[Version Revision] = ta.[Version Revision] AND da.[Package ID] != ta.[Package ID]"
    foreach ($app in $diffPackageIds) {
        Invoke-Sqlcmd -Database $tenantId -Query "UPDATE [dbo].[NAV App Installed App] SET [Package ID] = '$($app.'Package ID')' WHERE [App ID] = '$($app.'App ID')'"
    }

    Write-Host " - Replacing default tenant database with new SaaS database"
    Dismount-NAVTenant -ServerInstance $ServerInstance -Tenant "default" -Force
    Invoke-SqlCmd -Query "alter database [default] set single_user with rollback immediate; DROP DATABASE [default]"
    Invoke-SqlCmd -Query "ALTER DATABASE $tenantId SET SINGLE_USER WITH ROLLBACK IMMEDIATE; ALTER DATABASE $tenantId MODIFY NAME = [default]; ALTER DATABASE [default] SET MULTI_USER"
    $tenantId = "default"

    # move database to volume
    Write-Host " - Moving SaaS database to volume"
    if ($env:volPath -ne "") {
        $volPath = $env:volPath
        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null
        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Common") | Out-Null
        $dummy = new-object Microsoft.SqlServer.Management.SMO.Server
        $sqlConn = new-object Microsoft.SqlServer.Management.Common.ServerConnection
        $smo = new-object Microsoft.SqlServer.Management.SMO.Server($sqlConn)
        $smo.Databases | Where-Object { $_.Name -eq $tenantId } | ForEach-Object {
            # set recovery mode and shrink log
            $sqlcmd = "ALTER DATABASE [$($_.Name)] SET RECOVERY SIMPLE WITH NO_WAIT"
            & sqlcmd -Q $sqlcmd
            $shrinkCmd = "USE [$($_.Name)]; "
            $_.LogFiles | ForEach-Object {
                $shrinkCmd += "DBCC SHRINKFILE (N'$($_.Name)' , 10) WITH NO_INFOMSGS"
                & sqlcmd -Q $shrinkCmd
            }

            Write-Host " - - Moving $($_.Name)"
            $toCopy = @()
            $dbPath = Join-Path -Path $volPath -ChildPath $_.Name
            New-Item $dbPath -Type Directory -Force | Out-Null
            $_.FileGroups | ForEach-Object {
                $_.Files | ForEach-Object {
                    $destination = (Join-Path -Path $dbPath -ChildPath ($_.Name + '.' +  $_.FileName.SubString($_.FileName.LastIndexOf('.') + 1)))
                    $toCopy += ,@($_.FileName, $destination)
                    $_.FileName = $destination
                } 
            }
            $_.LogFiles | ForEach-Object {
                $destination = (Join-Path -Path $dbPath -ChildPath ($_.Name + '.' +  $_.FileName.SubString($_.FileName.LastIndexOf('.') + 1)))
                $toCopy += ,@($_.FileName, $destination)
                $_.FileName = $destination
            }

            $_.Alter()
            try {
                $db = $_
                $_.SetOffline()
            } catch {
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
    for ($i = 0; $i -lt 10; $i++) {
        Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $tenantId | Sync-NAVApp -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction silentlycontinue -WarningAction silentlycontinue
    }

    Write-Host " - Upgrading all apps"
    Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $tenantId | Start-NAVAppDataUpgrade -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction silentlycontinue

    Write-Host " - Upgrading tenant"
    Start-NAVDataUpgrade `
            -ServerInstance $ServerInstance `
            -Tenant $tenantId `
            -Force `
            -FunctionExecutionMode Serial `
            -SkipIfAlreadyUpgraded
    Get-NAVDataUpgrade `
        -ServerInstance $ServerInstance `
        -Tenant $tenantId `
        -Progress

    Write-Host " - Create user in new tenant"
    New-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -UserName $env:username -Password $securePassword
    New-NAVServerUserPermissionSet -ServerInstance $ServerInstance -Tenant $tenantId -UserName $env:username -PermissionSetId SUPER

    Write-Host " - Importing License to new tenant"
    Invoke-Sqlcmd -Database $tenantId -Query "truncate table [dbo].[Tenant License State]"
    Import-NAVServerLicense -ServerInstance $ServerInstance -Tenant $tenantId -LicenseFile "$runPath\license.flf" -Database Tenant
    Set-NAVServerInstance -ServerInstance $ServerInstance -Restart
}

Invoke-LogEvent -name "AdditionalSetup - Done" -telemetryClient $telemetryClient
Write-Host "=== Additional Setup Done ==="
Write-Host ""