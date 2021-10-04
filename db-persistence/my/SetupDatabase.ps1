$volPath = "$env:volPath"

function RunDefaultSetupDbScript {
    if ($restartingInstance) {

        # Nothing to do

    } elseif ($bakfile -ne "") {

        # .bak file specified - restore and use
        # if bakfile specified, download, restore and use

        if ($bakfile.StartsWith("https://") -or $bakfile.StartsWith("http://"))
        {
            $bakfileurl = $bakfile
            $databaseFile = (Join-Path $runPath "mydatabase.bak")
            Write-Host "Downloading database backup file '$bakfileurl'"
            (New-Object System.Net.WebClient).DownloadFile($bakfileurl, $databaseFile)

        } else {

            Write-Host "Using Database .bak file '$bakfile'"
            if (!(Test-Path -Path $bakfile -PathType Leaf)) {
                Write-Error "ERROR: Database Backup File not found."
                Write-Error "The file must be uploaded to the container or available on a share."
                exit 1
            }
            $databaseFile = $bakFile
        }

        # Restore database
        $databaseFolder = "c:\databases\my"

        if (!(Test-Path -Path $databaseFolder -PathType Container)) {
            New-Item -Path $databaseFolder -itemtype Directory | Out-Null
        }

        $databaseServerInstance = $databaseServer
        if ("$databaseInstance" -ne "") {
            $databaseServerInstance += "\$databaseInstance"
        }
        Write-Host "Using database server $databaseServerInstance"

        if (!$multitenant) {
            New-NAVDatabase -DatabaseServer $databaseServer `
                            -DatabaseInstance $databaseInstance `
                            -DatabaseName "$databaseName" `
                            -FilePath "$databaseFile" `
                            -DestinationPath "$databaseFolder" `
                            -Timeout $SqlTimeout | Out-Null

            Set-DatabaseCompatibilityLevel -DatabaseServer $databaseServer -DatabaseInstance $databaseInstance -DatabaseName $databaseName

            if ($roleTailoredClientFolder -and (Test-Path "$roleTailoredClientFolder\finsql.exe")) {
                Start-Process -FilePath "$roleTailoredClientFolder\finsql.exe" -ArgumentList "Command=upgradedatabase, Database=$databaseName, ServerName=$databaseServerInstance, ntauthentication=1, logFile=c:\run\errorlog.txt" -Wait
            }
            else {
                Invoke-NAVApplicationDatabaseConversion -databaseServer $databaseServerInstance -databaseName $databaseName -Force | Out-Null
            }
        } else {
            New-NAVDatabase -DatabaseServer $databaseServer `
                            -DatabaseInstance $databaseInstance `
                            -DatabaseName "tenant" `
                            -FilePath "$databaseFile" `
                            -DestinationPath "$databaseFolder" `
                            -Timeout $SqlTimeout -Force | Out-Null

            Set-DatabaseCompatibilityLevel -DatabaseServer $databaseServer -DatabaseInstance $databaseInstance -DatabaseName "tenant"

            if ($roleTailoredClientFolder -and (Test-Path "$roleTailoredClientFolder\finsql.exe")) {
                Start-Process -FilePath "$roleTailoredClientFolder\finsql.exe" -ArgumentList "Command=upgradedatabase, Database=$databaseName, ServerName=$databaseServerInstance, ntauthentication=1, logFile=c:\run\errorlog.txt" -Wait
            }
            else {
                Invoke-NAVApplicationDatabaseConversion -databaseServer $databaseServerInstance -databaseName "tenant" -force | Out-Null
            }

            Write-Host "Exporting Application to $DatabaseName"
            Invoke-sqlcmd -serverinstance $databaseServerInstance -Database "tenant" -query 'CREATE USER "NT AUTHORITY\SYSTEM" FOR LOGIN "NT AUTHORITY\SYSTEM";'
            Export-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -DestinationDatabaseName $databaseName -Force -ServiceAccount 'NT AUTHORITY\SYSTEM' | Out-Null
            Write-Host "Removing Application from tenant"
            Remove-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -Force | Out-Null
        }

    } elseif ("$appBacpac" -ne "") {

        # appBacpac and tenantBacpac specified - restore and use

        if (Test-NavDatabase -DatabaseName "tenant") {
            Remove-NavDatabase -DatabaseName "tenant"
        }
        if (Test-NavDatabase -DatabaseName "default") {
            Remove-NavDatabase -DatabaseName "default"
        }

        $dbName = "app"
        $appBacpac, $tenantBacpac | % {
            if ($_) {
                if ($_.StartsWith("https://") -or $_.StartsWith("http://"))
                {
                    $databaseFile = (Join-Path $runPath "${dbName}.bacpac")
                    Write-Host "Downloading ${dbName}.bacpac"
                    (New-Object System.Net.WebClient).DownloadFile($_, $databaseFile)
                } else {
                    if (!(Test-Path -Path $_ -PathType Leaf)) {
                        Write-Error "ERROR: Database Backup File not found."
                        Write-Error "The file must be uploaded to the container or available on a share."
                        exit 1
                    }
                    $databaseFile = $_
                }
                Restore-BacpacWithRetry -Bacpac $databaseFile -DatabaseName $dbName
            }
            $dbName = "tenant"
        }

        $databaseServer = "localhost"
        $databaseInstance = "SQLEXPRESS"
        $databaseName = "app"

        if ("$licenseFile" -eq "") {
            $licenseFile = Join-Path $serviceTierFolder "Cronus.flf"
        }

    } elseif ($databaseCredentials) {

        if (Test-Path $myPath -PathType Container) {
            $EncryptionKeyFile = Join-Path $myPath 'DynamicsNAV.key'
        } else {
            $EncryptionKeyFile = Join-Path $runPath 'DynamicsNAV.key'
        }
        if (!(Test-Path $EncryptionKeyFile -PathType Leaf)) {
            New-NAVEncryptionKey -KeyPath $EncryptionKeyFile -Password $EncryptionSecurePassword -Force | Out-Null
        }

        Set-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName "EnableSqlConnectionEncryption" -KeyValue "true" -WarningAction SilentlyContinue
        Set-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName "TrustSQLServerCertificate" -KeyValue "true" -WarningAction SilentlyContinue

        $databaseServerInstance = $databaseServer
        if ("$databaseInstance" -ne "") {
            $databaseServerInstance += "\$databaseInstance"
        }
        Write-Host "Import Encryption Key"
        Import-NAVEncryptionKey -ServerInstance $ServerInstance `
                                -ApplicationDatabaseServer $databaseServerInstance `
                                -ApplicationDatabaseCredentials $DatabaseCredentials `
                                -ApplicationDatabaseName $DatabaseName `
                                -KeyPath $EncryptionKeyFile `
                                -Password $EncryptionSecurePassword `
                                -WarningAction SilentlyContinue `
                                -Force

        Set-NavServerConfiguration -serverinstance $ServerInstance -databaseCredentials $DatabaseCredentials -WarningAction SilentlyContinue

    } elseif ($databaseServer -eq "localhost" -and $databaseInstance -eq "SQLEXPRESS" -and $multitenant) {

        if (!(Test-NavDatabase -DatabaseName "tenant")) {
            Copy-NavDatabase -SourceDatabaseName $databaseName -DestinationDatabaseName "tenant"
            Remove-NavDatabase -DatabaseName $databaseName
            Write-Host "Exporting Application to $DatabaseName"
            Invoke-sqlcmd -serverinstance "$DatabaseServer\$DatabaseInstance" -Database tenant -query 'CREATE USER "NT AUTHORITY\SYSTEM" FOR LOGIN "NT AUTHORITY\SYSTEM";'
            Export-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -DestinationDatabaseName $databaseName -Force -ServiceAccount 'NT AUTHORITY\SYSTEM' | Out-Null
            Write-Host "Removing Application from tenant"
            Remove-NAVApplication -DatabaseServer $DatabaseServer -DatabaseInstance $DatabaseInstance -DatabaseName "tenant" -Force | Out-Null
        }
    }
}


if ($restartingInstance) {

    # Nothing to do

} elseif ($volPath -ne "") {
    # database volume path is provided, check if the database is already there or not

    if ((Get-Item -path $volPath).GetFileSystemInfos().Count -eq 0) {
        # folder is empty, try to move the existing database to the db volume path

        Write-Host "Setting up database with default script"
        RunDefaultSetupDbScript

        Write-Host "Move databases to volume"

        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null

        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Common") | Out-Null

        $dummy = new-object Microsoft.SqlServer.Management.SMO.Server

        $sqlConn = new-object Microsoft.SqlServer.Management.Common.ServerConnection

        $smo = new-object Microsoft.SqlServer.Management.SMO.Server($sqlConn)
        
        $smo.Databases | ForEach-Object {
            if ($_.Name -ne 'master' -and $_.Name -ne 'model' -and $_.Name -ne 'msdb' -and $_.Name -ne 'tempdb' -and $_.Name -ne 'tenant') {
                if (($bakfile -ne "") -and $_.Name -eq 'CRONUS') {
                    return; # don't restore CRONUS if we have provided our own bak
                }

                # set recovery mode and shrink log
                $sqlcmd = "ALTER DATABASE [$($_.Name)] SET RECOVERY SIMPLE WITH NO_WAIT"
                & sqlcmd -Q $sqlcmd
                $shrinkCmd = "USE [$($_.Name)]; "
                $_.LogFiles | ForEach-Object {
                    $shrinkCmd += "DBCC SHRINKFILE (N'$($_.Name)' , 10) WITH NO_INFOMSGS"
                    & sqlcmd -Q $shrinkCmd
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
            & sqlcmd -Q $sqlcmd

            $dbPath = (Join-Path $volPath $database)
            $files = Get-ChildItem $dbPath -File
            $joinedFiles = $files.Name -join "'), (FILENAME = '$dbPath\"
            $sqlcmd = "CREATE DATABASE [$database] ON (FILENAME = '$dbPath\$joinedFiles') FOR ATTACH;"
            & sqlcmd -Q $sqlcmd
        }
    }
} else {
    # invoke default
    RunDefaultSetupDbScript
}
