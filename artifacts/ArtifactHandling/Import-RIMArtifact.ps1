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
        if ($env:cosmoServiceRestart -eq $true) {
            Add-ArtifactsLog -message "Skipping RIM artifact import because this seems to be a service restart"
            return
        }

        # Initialize, if files are present
        if (! $importFiles -and (Get-Item -Path $Path -Filter $Filter -ErrorAction SilentlyContinue)) {
            $importFiles = $true
            Add-ArtifactsLog -message "Prepare RIM Artifact Import"
            New-NAVServerUser -WindowsAccount (whoami) $ServerInstance -Tenant $Tenant -ErrorAction SilentlyContinue
            New-NAVServerUserPermissionSet -WindowsAccount (whoami) -PermissionSetId SUPER $ServerInstance  -Tenant $Tenant -ErrorAction SilentlyContinue
        }
        #Manage path as a filter
        if ($Path -like '*'){
            $Path = (Get-Item -Path $Path -Filter $Filter)[0]
        }
        
        if ($importFiles) {
            $properties = @{"path" = $Path; "ServerInstance" = $ServerInstance}

            Add-ArtifactsLog -kind RIM -message "Import RIM ... Get Companies ..."
            $companies  = (Get-NAVCompany $ServerInstance -Tenant $Tenant -ErrorAction SilentlyContinue)
        
            if ($companies.count -eq 0){
                Add-ArtifactsLog -kind RIM -message "Import RIM FAILED:$([System.Environment]::NewLine)  No company found" -data $properties -severity Error -success fail
                return
            } else {
                Add-ArtifactsLog -kind RIM -message "Import RIM ... found $($companies.count) companies" -data $properties
            }
            
            Add-ArtifactsLog -kind RIM -message "Import RapidStart files from $Path ..." -data $properties
            
            foreach ($company in $companies) {
                $properties = @{"path" = $Path; "Company" = $company.CompanyName; "ServerInstance" = $ServerInstance}
            
                try {
                    Add-ArtifactsLog -kind RIM -message "$([System.Environment]::NewLine)Import RIM $path" -data $properties

                    $started = Get-Date -Format "o"
                    Invoke-NAVCodeunit `
                        -CodeunitId         8620 `
                        -ServerInstance     $ServerInstance `
                        -Tenant             $Tenant `
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
    }
    
    end {
        if ($importFiles) {
            Add-ArtifactsLog -message "Import RapidStart files done. (Duration: $(New-TimeSpan -start $started -end (Get-Date)))"
        }
    }
}
Export-ModuleMember -Function Import-RIMArtifact