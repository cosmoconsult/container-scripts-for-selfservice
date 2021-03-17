function Import-RIMArtifact {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias("FullName")]    
        [string]$Path,
        [Parameter(Mandatory=$false)]
        [string]$ServerInstance = "NAV",
        [Parameter(Mandatory=$false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory=$false)]
        [string]$Filter = "*.rapidstart",
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
            Add-ArtifactsLog -message "Skipping RIM artifact import because this seems to be a service restart"
        }

        # Initialize, if files are present
        if (! $importFiles -and (Get-Item -Path $Path -Filter $Filter -ErrorAction SilentlyContinue)) {
            $importFiles = $true
            Add-ArtifactsLog -message "Prepare RIM Artifact Import"
            New-NAVServerUser -WindowsAccount (whoami) $ServerInstance -ErrorAction SilentlyContinue
            New-NAVServerUserPermissionSet -WindowsAccount (whoami) -PermissionSetId SUPER $ServerInstance -ErrorAction SilentlyContinue
            
            Add-ArtifactsLog -message "Import RapidStart files..."
            $companies = (Get-NAVCompany $ServerInstance -ErrorAction SilentlyContinue)
        }

        foreach ($company in $companies) {
            $properties = @{"path" = $Path; "Company" = $company.CompanyName; "ServerInstance" = $ServerInstance}
        
            try {
                Add-ArtifactsLog -kind RIM -message "$([System.Environment]::NewLine)Import RIM $path" -data $properties

                $started = Get-Date -Format "o"
                Invoke-NAVCodeunit `
                    -CodeunitId         8620 `
                    -ServerInstance     $ServerInstance `
                    -MethodName         'ImportAndApplyRapidStartPackage' `
                    -Argument           "$Path" `
                    -CompanyName        "$($company.CompanyName)" `
                    -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info

                $info | foreach { Add-ArtifactsLog -kind RIM -message "$_" -severity Info  -data $properties }
                $warn | foreach { Add-ArtifactsLog -kind RIM -message "$_" -severity Warn  -data $properties }
                $err  | foreach { Add-ArtifactsLog -kind RIM -message "$_" -severity Error -data $properties }
                $success = ! $err
                if ($success) { Add-ArtifactsLog -kind RIM "Import RIM ... successful" -data $properties -success success }
                Invoke-LogOperation -name "Import RIM Artifact" -started $started -properties $properties -telemetryClient $telemetryClient -success $success
            }
            catch {
                Add-ArtifactsLog -kind RIM -message "Import RIM $path FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $properties -severity Error -success fail
                Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Import RIM Artifact"
            }            
            Add-ArtifactsLog -message " "
        }
    }
    
    end {
        if ($importFiles) {
            Add-ArtifactsLog -message "Import RapidStart files done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
        }
    }
}
Export-ModuleMember -Function Import-RIMArtifact