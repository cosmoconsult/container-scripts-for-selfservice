$NAVModuleNames = @('Microsoft.BusinessCentral.Apps.Management', 'Microsoft.Dynamics.Nav.Apps.Management', 'Microsoft.Dynamics.Nav.Management')
if (! (Get-Module -Name $NAVModuleNames)) {
    Push-Location
    c:\run\prompt.ps1 -silent
    Pop-Location
}

function Publish-NAVApp() {
    # Must be a simple function for correct splatting
    if ($PSVersionTable.PSEdition -ne 'Core') {
        if (Test-Path "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\Microsoft.BusinessCentral.Apps.Management.dll") {
            Import-Module "c:\run\helper\PPIPowershellCoreUtils" -DisableNameChecking
            return Invoke-CommandInPwshCore `
                -ScriptBlock { Publish-NAVApp @args } `
                -Modules $MyInvocation.MyCommand.Module `
                @args
        }
    }

    $module = Get-Module -Name $NAVModuleNames | Sort-Object { $NAVModuleNames.IndexOf($_.Name) } | Select-Object -First 1
    if (! $module) {
        throw ("NAV/BC powershell modules not found: {0}" -f ($NAVModuleNames -join ', '))
    }
    & "$($module.Name)\Publish-NAVApp" @args
}
Export-ModuleMember -Function Publish-NAVApp