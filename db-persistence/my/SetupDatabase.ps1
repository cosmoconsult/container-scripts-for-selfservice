$volPath = "$env:volPath"

if (Test-Path "c:\run\PPIArtifactUtils.psd1") {
    Write-Host "Import PPI Setup Utils from c:\run\PPIArtifactUtils.psd1"
    Import-Module "c:\run\PPIArtifactUtils.psd1" -Force
}

if ($restartingInstance) {

    # Nothing to do

}
elseif (($volPath -ne "") -and (Test-Path $volPath)) {
    # database volume path is provided, check if the database is already there or not

    if ((Get-ChildItem $volPath -Directory -Exclude ALAssemblies).Count -eq 0) {
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
        }
        
        $smo.ConnectionContext.Disconnect()
    }
    else {
        $databases = (Get-ChildItem $volPath -Directory -Exclude ALAssemblies).BaseName
        $appDatabaseName = Get-AppDatabaseName

        # In multitenant mode the app database is expected to be 'default'.
        # Some historical setups persist only CRONUS in volPath on first boot,
        # so we reconstruct the missing default folder before attaching.
        if (($appDatabaseName -eq 'default') -and ($databases -notcontains 'default')) {
            $rebuildSource = $null
            if ($databases -contains 'tenant') {
                $rebuildSource = 'tenant'
            }
            elseif ($databases -contains 'CRONUS') {
                $rebuildSource = 'CRONUS'
            }

            if (! $rebuildSource) {
                throw "Expected app database folder 'default' is missing in '$volPath' and no source (tenant/CRONUS) is available to rebuild it."
            }

            $sourcePath = Join-Path $volPath $rebuildSource
            $defaultPath = Join-Path $volPath 'default'
            Write-Warning "App database folder 'default' is missing in '$volPath'. Rebuilding from '$rebuildSource'."
            New-Item -Path $defaultPath -ItemType Directory -Force | Out-Null
            Copy-Item -Path (Join-Path $sourcePath '*') -Destination $defaultPath -Recurse -Force

            # Avoid attaching CRONUS when default was reconstructed from CRONUS,
            # because both copies may contain identical metadata/logical file names.
            if ($rebuildSource -eq 'CRONUS') {
                $databases = @($databases | Where-Object { $_ -ne 'CRONUS' })
            }

            $databases = (Get-ChildItem $volPath -Directory -Exclude ALAssemblies).BaseName
        }

        Write-Host ("Databases discovered in volume: {0}" -f ($databases -join ', '))

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

        Write-Host "Expected app database from configuration: $appDatabaseName"

        if ($databases -notcontains $appDatabaseName) {
            throw "Expected app database '$appDatabaseName' is not attached. Attached databases: $($databases -join ', ')."
        }

        Write-Host "Check database $appDatabaseName and container version to identify need for upgrade"
        $sysAppPath = 'C:\Applications\system application\source\Microsoft_System Application.app'
        if (Test-Path $sysAppPath) {
            c:\run\prompt.ps1
            $sysAppInfoFS = Get-NAVAppInfo -Path $sysAppPath
            $sysAppInfoDB = (Invoke-Sqlcmd -database $appDatabaseName -Query "select * FROM [dbo].[NAV App Installed App] WHERE Publisher='Microsoft' and Name='System Application'" -ServerInstance "$DatabaseServer\$DatabaseInstance")

            $sysAppVersionFS = $sysAppInfoFS.Version
            Write-Host "Trying to parse $($sysAppInfoDB.'Version Major').$($sysAppInfoDB.'Version Minor').$($sysAppInfoDB.'Version Build').$($sysAppInfoDB.'Version Revision') for the database version"
            $sysAppVersionDB = [Version]::new()
            $canParseVersionDB = [Version]::TryParse("$($sysAppInfoDB.'Version Major').$($sysAppInfoDB.'Version Minor').$($sysAppInfoDB.'Version Build').$($sysAppInfoDB.'Version Revision')", [ref]$sysAppVersionDB)
            if (-not $canParseVersionDB) {
                Write-Host "  Unable to parse the version in the database, trying to convert and hoping for the best..."
                Write-Host "  Found in FS:"
                $sysAppInfoFS
                Write-Host "  Found in DB:"
                $sysAppInfoDB
                Invoke-NAVApplicationDatabaseConversion -databaseServer "$DatabaseServer\$DatabaseInstance" -DatabaseName "$appDatabaseName" -Force
                $env:cosmoUpgradeSysApp = $true
            }
            else {
                Write-Host "  Found version $sysAppVersionFS for the container and $sysAppVersionDB for the database"
                Write-Host "  As we see issues with revision changes on BC 26.2, we ignore the revision for now"
                $sysAppVersionFS_NoRev = [Version]::new($sysAppVersionFS.Major, $sysAppVersionFS.Minor, $sysAppVersionFS.Build)
                $sysAppVersionDB_NoRev = [Version]::new($sysAppVersionDB.Major, $sysAppVersionDB.Minor, $sysAppVersionDB.Build)
                Write-Host "  We now compare $sysAppVersionFS_NoRev for the container and $sysAppVersionDB_NoRev for the database"
                if ($sysAppVersionDB_NoRev -gt $sysAppVersionFS_NoRev) {
                    Write-Error "  Database version is newer than container version, this probably won't work"
                }
                elseif ($sysAppVersionFS_NoRev -gt $sysAppVersionDB_NoRev) {
                    Write-Host "  Container version is newer than database version, trying to convert"
                    Invoke-NAVApplicationDatabaseConversion -databaseServer "$DatabaseServer\$DatabaseInstance" -DatabaseName "$appDatabaseName" -Force
                    $env:cosmoUpgradeSysApp = $true
                }
                else {
                    Write-Host "  Versions are identical, this should work"
                }
            }
        }
        else {
            Write-Host "Can't upgrade database because System App not available (likely old BC version)"
        }
    }
}
else {
    # invoke default
    . (Join-Path $runPath $MyInvocation.MyCommand.Name)
}
