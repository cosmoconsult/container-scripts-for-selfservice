function Import-RIMArtifact {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName")]    
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [string]$ServerInstance = "NAV",
        [Parameter(Mandatory = $false)]
        [string]$Tenant = "default",
        [Parameter(Mandatory = $false)]
        [string]$Filter = "*.rapidstart",
        [Parameter(Mandatory = $false)]
        [System.Object]$telemetryClient = $null,
        [bool]$throwErrors = $false,
        [switch]$SkipServiceRestartCheck
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }

        $importFiles = $false
        $importErrorAction = if ($throwErrors) { "Stop" } else { "SilentlyContinue" }
        $started = Get-Date -Format "o"
    }
    
    process {
        # check restart
        if (-not $SkipServiceRestartCheck -and $env:cosmoServiceRestart -eq $true) {
            Add-ArtifactsLog -message "Skipping RapidStart artifact import because this seems to be a service restart"
            return
        }

        # Initialize, if files are present
        if (! $importFiles -and (Get-Item -LiteralPath $Path -ErrorAction $importErrorAction)) {
            $importFiles = $true
            Add-ArtifactsLog -message "Prepare RapidStart Artifact Import"
            New-NAVServerUser -WindowsAccount (whoami) $ServerInstance -Tenant $Tenant -ErrorAction SilentlyContinue
            New-NAVServerUserPermissionSet -WindowsAccount (whoami) -PermissionSetId SUPER $ServerInstance  -Tenant $Tenant -ErrorAction SilentlyContinue
        }
        #Manage path as a filter
        $packagePath = (Get-Item -LiteralPath $Path -ErrorAction $importErrorAction).FullName
        
        if ($importFiles) {
            $properties = @{"path" = $Path; "ServerInstance" = $ServerInstance }

            Add-ArtifactsLog -kind RIM -message "Import RapidStart ... Get Companies ..."
            $companies = [System.Collections.ArrayList]@() + ((Get-NAVCompany $ServerInstance -Tenant $Tenant -ErrorAction $importErrorAction) | Where-Object { $_.CompanyName -ne "My Company" })
        
            if ($companies.count -eq 0) {
                Add-ArtifactsLog -kind RIM -message "Import RapidStart FAILED:$([System.Environment]::NewLine)  No company found" -data $properties -severity Error -success fail
                if ($throwErrors) { throw "No company found for RapidStart import on tenant '$Tenant'" }
                return
            }
            else {
                Add-ArtifactsLog -kind RIM -message "Import RapidStart ... found $($companies.count) companies" -data $properties
            }
            
            Add-ArtifactsLog -kind RIM -message "Import and apply package from $Path ..." -data $properties
            
            foreach ($company in $companies) {
                $properties = @{"path" = $Path; "Company" = $company.CompanyName; "ServerInstance" = $ServerInstance }
            
                try {
                    Add-ArtifactsLog -kind RIM -message "$([System.Environment]::NewLine)Import and apply package $Path in company '$($company.CompanyName)'" -data $properties

                    $started = Get-Date -Format "o"
                    Invoke-NAVCodeunit `
                        -CodeunitId         8620 `
                        -ServerInstance     $ServerInstance `
                        -Tenant             $Tenant `
                        -MethodName         'ImportAndApplyRapidStartPackage' `
                        -Argument           $packagePath `
                        -CompanyName        "$($company.CompanyName)" `
                        -ErrorAction $importErrorAction -ErrorVariable err -WarningVariable warn -InformationVariable info

                    $info | foreach { Add-ArtifactsLog -kind RIM -message "$_" -severity Info  -data $properties }
                    $warn | foreach { Add-ArtifactsLog -kind RIM -message "$_" -severity Warn  -data $properties }
                    $err  | foreach { Add-ArtifactsLog -kind RIM -message "$_" -severity Error -data $properties }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind RIM "Import and apply package $Path in company '$($company.CompanyName)' ... successful" -data $properties -success success }
                    Invoke-LogOperation -name "Import and apply RapidStart Artifact" -started $started -properties $properties -telemetryClient $telemetryClient -success $success
                }
                catch {
                    Add-ArtifactsLog -kind RIM -message "Import and apply package $Path in company '$($company.CompanyName)' FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $properties -severity Error -success fail
                    Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Import RapidStart Artifact"
                    if ($throwErrors) { throw }
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