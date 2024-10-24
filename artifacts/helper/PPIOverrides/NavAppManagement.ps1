
if ($PSVersionTable.PSEdition -eq 'Core') { return }
if (! (Test-Path "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\Microsoft.BusinessCentral.Apps.Management.dll")) { return }

$NAVModuleNames = @('Microsoft.BusinessCentral.Apps.Management', 'Microsoft.Dynamics.Nav.Apps.Management', 'Microsoft.Dynamics.Nav.Management')
if (! (Get-Module -Name $NAVModuleNames)) {
    Push-Location
    c:\run\prompt.ps1 -silent
    Pop-Location
}

if (! (Get-Module -Name 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -DisableNameChecking -Force
}

function Publish-NAVApp() {
    # Must be a simple function for correct splatting
    Invoke-CommandInPwshCore -ScriptBlock { 
        if (! (Get-Module -Name 'Microsoft.BusinessCentral.Apps.Management')) {
            c:\run\prompt.ps1 -silent
        }
        Publish-NAVApp @args 
    } @args
}
Export-ModuleMember -Function Publish-NAVApp