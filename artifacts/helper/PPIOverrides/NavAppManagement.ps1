# Overrides only needed if not powershell core
if ($PSVersionTable.PSEdition -eq 'Core') { return }
# Overrides only needed if BC24 or higher
if (! (Test-Path "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\Microsoft.BusinessCentral.Apps.Management.dll")) { return }

if (! (Get-Module -Name 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -DisableNameChecking -Global -Force
}

function Publish-NAVApp() {
    [CmdletBinding()]
    Param()

    DynamicParam {
        $sourceParameters = Invoke-CommandInPwshCore -ScriptBlock {
            if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                c:\run\prompt.ps1 -silent
            }
            (Get-Command Publish-NAVApp).Parameters
        }
        Get-DynamicParameters -TargetCommand $MyInvocation.MyCommand -SourceParameters $sourceParameters
    }

    begin {
        $MyInvocation.MyCommand.Parameters.Values | Where-Object { ! $_.IsDynamic } | Foreach-Object {
            $PSBoundParameters.Remove($_.Name) | Out-Null
        }
    }
    
    process {
        $pwshCoreSession = Request-PwshCoreSession
        if (!$pwshCoreSession) { return }
        Invoke-Command -Session $pwshCoreSession -ScriptBlock {
            if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                c:\run\prompt.ps1 -silent
            }
            Publish-NAVApp @using:PSBoundParameters
        }
    }
}
Export-ModuleMember -Function Publish-NAVApp