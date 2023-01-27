$volPath = "$env:volPath"

if (Test-Path "c:\run\PPIArtifactUtils.psd1") {
    Write-Host "Import PPI Setup Utils from c:\run\PPIArtifactUtils.psd1"
    Import-Module "c:\run\PPIArtifactUtils.psd1" -DisableNameChecking -Force
}

if ($restartingInstance) {

    # Nothing to do

} elseif ($volPath -ne "") {
    # database volume path is provided, check if the database is already there or not

    if ((Get-ChildItem $volPath).Count -eq 0) {
        # folder is empty, try to move the existing database to the db volume path

        Write-Host "Setting up database with default script"
        . (Join-Path $runPath $MyInvocation.MyCommand.Name)

        Write-Host "Move databases to volume"

        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null

        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Common") | Out-Null

        $dummy = new-object Microsoft.SqlServer.Management.SMO.Server

        $sqlConn = new-object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList "$DatabaseServer\$DatabaseInstance"

        $smo = new-object Microsoft.SqlServer.Management.SMO.Server($sqlConn)
        
        $smo.Databases | ForEach-Object {
            if ($_.Name -ne 'master' -and $_.Name -ne 'model' -and $_.Name -ne 'msdb' -and $_.Name -ne 'tempdb' -and $_.Name -ne 'tenant') {
                if (($bakfile -ne "") -and $_.Name -eq 'CRONUS') {
                    return; # don't restore CRONUS if we have provided our own bak
                }

                # set recovery mode and shrink log
                $sqlcmd = "ALTER DATABASE [$($_.Name)] SET RECOVERY SIMPLE WITH NO_WAIT"
                & sqlcmd -Q $sqlcmd -S "$DatabaseServer\$DatabaseInstance"
                $shrinkCmd = "USE [$($_.Name)]; "
                $_.LogFiles | ForEach-Object {
                    $shrinkCmd += "DBCC SHRINKFILE (N'$($_.Name)' , 10) WITH NO_INFOMSGS"
                    & sqlcmd -Q $shrinkCmd -S "$DatabaseServer\$DatabaseInstance"
                }
            
                Write-Host "- Moving $($_.Name)"
                $toCopy = @()
                $dbPath = Join-Path -Path $volPath -ChildPath $_.Name
                mkdir $dbPath | Out-Null
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
        }
        
        $smo.ConnectionContext.Disconnect()
    } else {
        $databases = (Get-ChildItem $volPath -Directory).BaseName

        foreach ($database in $databases) {
            # folder is not empty, attach the database
            Write-Host "Attach database $database"

            $sqlcmd = "DROP DATABASE IF EXISTS [$database]"
            & sqlcmd -Q $sqlcmd -S "$DatabaseServer\$DatabaseInstance"

            $dbPath = (Join-Path $volPath $database)
            $files = Get-ChildItem $dbPath -File
            $joinedFiles = $files.Name -join "'), (FILENAME = '$dbPath\"
            $sqlcmd = "CREATE DATABASE [$database] ON (FILENAME = '$dbPath\$joinedFiles') FOR ATTACH;"
            & sqlcmd -Q $sqlcmd -S "$DatabaseServer\$DatabaseInstance"
        }

        $appDatabaseName = Get-AppDatabaseName

        Write-Host "Check database $appDatabaseName and container version to identify need for upgrade"
        c:\run\prompt.ps1
        $sysAppInfoFS = Get-NAVAppInfo -Path 'C:\Applications\system application\source\Microsoft_System Application.app'
        $sysAppInfoDB = (Invoke-Sqlcmd -database $appDatabaseName -Query "select * FROM [dbo].[NAV App Installed App] WHERE Publisher='Microsoft' and Name='System Application'" -ServerInstance "$DatabaseServer\$DatabaseInstance")

        $sysAppVersionFS = $sysAppInfoFS.Version
        Write-Host "Trying to parse $($sysAppInfoDB.'Version Major').$($sysAppInfoDB.'Version Minor').$($sysAppInfoDB.'Version Build').$($sysAppInfoDB.'Version Revision') for the database version"
        $sysAppVersionDB = [Version]::new()
        $canParseVersionDB = [Version]::TryParse("$($sysAppInfoDB.'Version Major').$($sysAppInfoDB.'Version Minor').$($sysAppInfoDB.'Version Build').$($sysAppInfoDB.'Version Revision')", [ref]$sysAppVersionDB)
        if (-not $canParseVersionDB) {
            Write-Host "  Unable to parse the version in the database, doing nothing and hoping for the best..."
            Write-Host "  Found in FS:"
            $sysAppInfoFS
            Write-Host "  Found in DB:"
            $sysAppInfoDB
        } else {
            Write-Host "  Found version $sysAppVersionFS for the container and $sysAppVersionDB for the database"
            if ($sysAppVersionDB -gt $sysAppVersionFS) {
                Write-Error "  Database version is newer than container version, this probably won't work"
            } elseif ($sysAppVersionFS -gt $sysAppVersionDB) {
                Write-Host "  Container version is newer than database version, trying to convert"
                Invoke-NAVApplicationDatabaseConversion -databaseServer "localhost" -DatabaseName "$databaseName" -Force
                $env:cosmoUpgradeSysApp = $true
            } else {
                Write-Host "  Versions are identical, this should work"
            }
        }
    }
} else {
    # invoke default
    . (Join-Path $runPath $MyInvocation.MyCommand.Name)
}
