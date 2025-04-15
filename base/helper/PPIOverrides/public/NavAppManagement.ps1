# Overrides only needed if not powershell core
if ($PSVersionTable.PSEdition -eq 'Core') { return }
# Overrides only needed if BC24 or higher
$bcVersion = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
if ($bcVersion -and $bcVersion.Major -lt 24) { return }

# Create powershell core remote session (may enable remoting for powershell core)
Get-PwshCoreSessionConfiguration | Out-Null

$moduleName = 'Microsoft.BusinessCentral.Apps.Management'
$moduleImportScriptBlock = { c:\run\prompt.ps1 -silent }
$commandNames = @(
    'Get-NavAppRuntimePackage', 
    'Install-NAVApp', 
    'Invoke-InplacePublishing', 
    'Publish-NAVApp', 
    'Repair-NAVApp', 
    'Start-NAVAppDataUpgrade', 
    'Sync-NAVApp', 
    'Uninstall-NAVApp', 
    'Unpublish-NAVApp'
) 

$commandNames | ForEach-Object {
    Export-PwshCoreOverride -CommandName $_ -ModuleName $moduleName -ModuleImportScriptBlock $moduleImportScriptBlock
}
