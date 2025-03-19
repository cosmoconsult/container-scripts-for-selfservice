function Import-NAVModules {
    [CmdletBinding()]
    param (
        [string]$ServiceTierFolder = "",
        [string]$RoleTailoredClientFolder = "",
        [switch]$ExcludeServiceTier,
        [switch]$ExcludeRoleTailoredClient,
        [switch]$Force
    )

    begin {
        if ((! $ExcludeServiceTier) -and (! $ServiceTierFolder)) {
            $ServiceTierFolder = Get-NAVServiceTierFolder
        }

        if ((! $ExcludeRoleTailoredClient) -and (! $RoleTailoredClientFolder)) {
            $RoleTailoredClientFolder = Get-NAVRoleTailoredClientFolder
        }
    }
    
    process {
        if ((! $ExcludeServiceTier) -and $ServiceTierFolder) {
            if (Test-Path "$ServiceTierFolder") {
                if (Test-Path "$ServiceTierFolder\Microsoft.Dynamics.Nav.Management.psm1") {
                    Write-Host "Import Management Utils from $ServiceTierFolder\Microsoft.Dynamics.Nav.Management.psm1"
                    Import-Module "$ServiceTierFolder\Microsoft.Dynamics.Nav.Management.psm1" -Global -Force:$Force -ErrorAction SilentlyContinue -DisableNameChecking
                }
                else {
                    Write-Host "Import Management Utils from $ServiceTierFolder\Microsoft.Dynamics.Nav.Management.dll"
                    Import-Module "$ServiceTierFolder\Microsoft.Dynamics.Nav.Management.dll" -Global -Force:$Force -ErrorAction SilentlyContinue -DisableNameChecking
                }
                if (Test-Path "$ServiceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1") {
                    Write-Host "Import App Management Utils from $ServiceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1"
                    Import-Module "$ServiceTierFolder\Microsoft.Dynamics.Nav.Apps.Management.psd1" -Global -Force:$Force -DisableNameChecking
                }
                elseif (Test-Path "SserviceTierFolder\Management\Microsoft.Dynamics.Nav.Apps.Management.psd1") {
                    Write-Host "Import App Management Utils from $ServiceTierFolder\Management\Microsoft.Dynamics.Nav.Apps.Management.psd1"
                    Import-Module "$ServiceTierFolder\Management\Microsoft.Dynamics.Nav.Apps.Management.psd1" -Global -Force:$Force -DisableNameChecking
                }
            }
        }

        if ((! $ExcludeRoleTailoredClient) -and $RoleTailoredClientFolder) {
            if (Test-Path "$RoleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1") {
                Write-Host "Import Nav IDE from $RoleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1"
                Import-Module "$RoleTailoredClientFolder\Microsoft.Dynamics.Nav.Ide.psm1" -Global -Force:$Force -ErrorAction SilentlyContinue -DisableNameChecking
            }
        }
    }
}
Export-ModuleMember -Function Import-NAVModules