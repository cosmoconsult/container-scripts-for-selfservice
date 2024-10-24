# Overrides only needed if not powershell core
if ($PSVersionTable.PSEdition -eq 'Core') { return }
# Overrides only needed if BC24 or higher
if (! (Test-Path "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\Microsoft.BusinessCentral.Apps.Management.dll")) { return }

if (! (Get-Module -Name 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -DisableNameChecking -Force
}

function Publish-NAVApp() {
    [CmdletBinding()]
    Param()

    DynamicParam {
        Get-DynamicParameters -TargetCommand $MyInvocation.MyCommand -SourceParamsScript {
            Invoke-CommandInPwshCore -ScriptBlock {
                if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                    c:\run\prompt.ps1 -silent
                }
                (Get-Command Publish-NAVApp).Parameters
            }
        }
    }

    begin {
        $dynamicParameters = $PSBoundParameters
        $MyInvocation.MyCommand.Parameters.Values | Where-Object { ! $_.IsDynamic } | Foreach-Object {
            $dynamicParameters.Remove($_.Name) | Out-Null
        }
    }
    
    process {
        $pwshCoreSession = Request-PwshCoreSession
        if (!$pwshCoreSession) { return }
        Invoke-Command -Session $pwshCoreSession -ScriptBlock {
            if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                c:\run\prompt.ps1 -silent
            }
            Publish-NAVApp @using:dynamicParameters
        }
    }
}
Export-ModuleMember -Function Publish-NAVApp