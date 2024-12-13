# Overrides only needed if not powershell core
if ($PSVersionTable.PSEdition -eq 'Core') { return }
# Overrides only needed if BC24 or higher
if (! (Test-Path "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\Microsoft.BusinessCentral.Apps.Management.dll")) { return }

$commands = Invoke-CommandInPwshCore -ScriptBlock {
    $moduleName = 'Microsoft.BusinessCentral.Apps.Management'
    if (! (Get-Module $moduleName)) {
        c:\run\prompt.ps1 -silent
    }
    Get-Command -Module $moduleName | Select-Object -Property *
}
if (! $commands) { return }

$commands | Export-PwshCoreOverride