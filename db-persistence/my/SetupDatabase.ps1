$volPath = "$env:volPath"

if ($restartingInstance) {

    # Nothing to do

} elseif ($volPath -ne "") {
    # database volume path is provided, check if the database is already there or not

    if ((Get-Item -path $volPath).GetFileSystemInfos().Count -eq 0) {
        # folder is empty, try to move the existing database to the db volume path

        Write-Host "Setting up database with default script"
        . (Join-Path $runPath $MyInvocation.MyCommand.Name)

        Write-Host "Move databases to volume"

        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Smo") | Out-Null

        [reflection.assembly]::LoadWithPartialName("Microsoft.SqlServer.Common") | Out-Null

        $dummy = new-object Microsoft.SqlServer.Management.SMO.Server

        $sqlConn = new-object Microsoft.SqlServer.Management.Common.ServerConnection

        $smo = new-object Microsoft.SqlServer.Management.SMO.Server($sqlConn)
        $dbs = New-Object Collections.Generic.List[object]
        
        foreach ($db in $smo.Databases) {
            $dbs.Add($db)
        }
        
        $tenantDb = $dbs | where Name -eq "tenant"
        
        if ($tenantDb) {
            # on multitenant we need to move tenant db first and keep it offline until all databases are moved
            $dbs.Remove($tenantDb)
            $dbs.Insert(0, $tenantDb)
        }
        
        $dbs | ForEach-Object {
            if ($_.Name -ne 'master' -and $_.Name -ne 'model' -and $_.Name -ne 'msdb' -and $_.Name -ne 'tempdb') {
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
                $_.SetOffline()

                $toCopy | ForEach-Object {
                    Move-Item -Path $_[0] -Destination $_[1]
                }
                
                if ($_.Name -ne 'tenant') {
                    $_.SetOnline()
                }
            }
        }
        
        if ($tenantDb) {
            $tenantDb.SetOnline();
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
    . (Join-Path $runPath $MyInvocation.MyCommand.Name)
}
