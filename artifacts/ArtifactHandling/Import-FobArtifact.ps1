function Import-FobArtifact {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias("FullName")]
        [string]$Path,
        [Parameter(Mandatory=$true)]
        [string]$NavServiceName,
        [Parameter(Mandatory=$false)]
        [string]$ServerInstance = "NAV",
        [Parameter(Mandatory=$false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory=$false)]
        [string]$DatabaseServer = "localhost\sqlexpress",
        [Parameter(Mandatory=$false)]
        [string]$Filter = "*.fob",
        [Parameter(Mandatory=$false)]
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }

        $importFiles = $false
        $started     = Get-Date -Format "o"
    }
    
    process {
        # check restart
        if ($cosmoServiceRestart -eq $true) {
            Add-ArtifactsLog -message "Skipping FOB artifact import because this seems to be a service restart"
            return
        }

        # Initialize, if files are present
        if (! $importFiles -and (Get-Item -Path $Path -Filter $Filter -ErrorAction SilentlyContinue)) {
            $importFiles = $true
            Add-ArtifactsLog -message "Import Object Files"
            Stop-Service -Name $NavServiceName -WarningAction Ignore
            $databaseName = ((Get-NAVServerConfiguration -ServerInstance $ServerInstance -ErrorAction SilentlyContinue) | Where-Object { $_.key -eq "DatabaseName" }).value
        }
        
        $properties = @{"path" = $Path; "DatabaseName" = $DatabaseName; "NavServiceName" = $NavServiceName; "ServerInstance" = $ServerInstance}
        try {
            $started = Get-Date -Format "o"
            
            $fob     = Get-Item -Path $Path -Filter $Filter -ErrorAction SilentlyContinue
            if ($fob -and ("$($fob.Length)" -ne "0")) {
                Add-ArtifactsLog -kind FOB -message "$([System.Environment]::NewLine)Import Objects from $($fob.FullName) ... into $DatabaseName" -data $properties
                Import-NAVApplicationObject `
                    -Path                     $($fob.FullName) `
                    -ImportAction             Overwrite `
                    -SynchronizeSchemaChanges No `
                    -DatabaseName             $DatabaseName `
                    -DatabaseServer           $DatabaseServer `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info

                $info | foreach { Add-ArtifactsLog -kind FOB -message "$_" -severity Info  -data $properties }
                $warn | foreach { Add-ArtifactsLog -kind FOB -message "$_" -severity Warn  -data $properties }
                $err  | foreach { Add-ArtifactsLog -kind FOB -message "$_" -severity Error -data $properties }
                $success = ! $err
                if ($success) { Add-ArtifactsLog -kind FOB -message "Import Objects ... successful" -data $properties -success success }                
            } else {
                Add-ArtifactsLog -kind FOB -message "Import Objects from $Path ... SKIPPED" -success "skip" -data $properties
            }
            
            Invoke-LogOperation -name "Import FOB Artifact" -started $started -properties $properties -telemetryClient $telemetryClient -success $success
            Add-ArtifactsLog -message " "
        }
        catch {
            Add-ArtifactsLog -kind FOB -message "Import FOB FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $properties -severity Error -success fail
            Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Import FOB Artifact"
        }        
        return $artifacts        
    }
    
    end {
        if ($importFiles) {
            try {
                $started2 = Get-Date -Format "o"

                Start-Service -Name $NavServiceName -WarningAction Ignore
                Add-ArtifactsLog -kind FOB -message "Sync-NAVTenant $ServerInstance with FORCE"
                Sync-NAVTenant -ServerInstance $ServerInstance -Mode ForceSync -Tenant $Tenant -Force
                Add-ArtifactsLog -kind FOB -message "Sync NAV Tenant successful" -success success
                Write-Host "Restart NAV service"
                Restart-Service -Name $NavServiceName
                Invoke-LogOperation -name "Sync NAV Tenant" -started $started2 -telemetryClient $telemetryClient
            }
            catch {
                Add-ArtifactsLog -kind FOB -message "Sync NAV Tenant failed" -success fail -severity Error
                Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -operation "Import FOB Artifact"
            }
            finally {
                Add-ArtifactsLog "Import Object Files done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
            }
        }
    }
}
Export-ModuleMember -Function Import-FobArtifact