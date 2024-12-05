# Overrides only needed if not powershell core
if ($PSVersionTable.PSEdition -eq 'Core') { return }
# Overrides only needed if BC24 or higher
if (! (Test-Path "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\Microsoft.BusinessCentral.Apps.Management.dll")) { return }

# Import PPI Powershell Core Utils
if (! (Get-Module 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -DisableNameChecking -Global -Force
}

# Create powershell core remote session (may enable remoting for powershell core)
Request-PwshCoreSession | Out-Null

function Publish-NAVApp() {
    [CmdletBinding()]
    Param()

    DynamicParam {
        $overwrittenParameters = Invoke-CommandInPwshCore -ScriptBlock {
            if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                c:\run\prompt.ps1 -silent
            }
            (Get-Command Publish-NAVApp).Parameters
        }
        ConvertTo-DynamicParameters -CommandName 'Microsoft.BusinessCentral.Apps.Management\Publish-NAVApp' -Parameters $overwrittenParameters
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

function Sync-NAVApp() {
    [CmdletBinding()]
    Param()

    DynamicParam {
        $overwrittenParameters = Invoke-CommandInPwshCore -ScriptBlock {
            if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                c:\run\prompt.ps1 -silent
            }
            (Get-Command Sync-NAVApp).Parameters
        }
        ConvertTo-DynamicParameters -CommandName 'Microsoft.BusinessCentral.Apps.Management\Sync-NAVApp' -Parameters $overwrittenParameters
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
            Sync-NAVApp @using:PSBoundParameters
        }
    }
}
Export-ModuleMember -Function Sync-NAVApp

function Install-NAVApp() {
    [CmdletBinding()]
    Param()

    DynamicParam {
        $overwrittenParameters = Invoke-CommandInPwshCore -ScriptBlock {
            if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                c:\run\prompt.ps1 -silent
            }
            (Get-Command Install-NAVApp).Parameters
        }
        ConvertTo-DynamicParameters -CommandName 'Microsoft.BusinessCentral.Apps.Management\Install-NAVApp' -Parameters $overwrittenParameters
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
            Install-NAVApp @using:PSBoundParameters
        }
    }
}
Export-ModuleMember -Function Install-NAVApp

function Start-NAVAppDataUpgrade() {
    [CmdletBinding()]
    Param()

    DynamicParam {
        $overwrittenParameters = Invoke-CommandInPwshCore -ScriptBlock {
            if (! (Get-Module 'Microsoft.BusinessCentral.Apps.Management')) {
                c:\run\prompt.ps1 -silent
            }
            (Get-Command Start-NAVAppDataUpgrade).Parameters
        }
        ConvertTo-DynamicParameters -CommandName 'Microsoft.BusinessCentral.Apps.Management\Start-NAVAppDataUpgrade' -Parameters $overwrittenParameters
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
            Start-NAVAppDataUpgrade @using:PSBoundParameters
        }
    }
}
Export-ModuleMember -Function Start-NAVAppDataUpgrade