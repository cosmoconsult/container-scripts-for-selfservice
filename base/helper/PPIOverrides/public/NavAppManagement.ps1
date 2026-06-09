# Overrides only needed if not powershell core
if ($PSVersionTable.PSEdition -eq 'Core') { return }
# Overrides only needed if BC24 or higher
$bcVersion = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
if ($bcVersion -and $bcVersion.Major -lt 24) { return }

# Import PPI Powershell Core Utils
if (! (Get-Module 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -Global -Force
}

$commandNamesForAppManagement = @(
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

$commandNamesForManagement = @(
    'Mount-NAVTenant'
)

# Create powershell core remote session (may enable remoting for powershell core)
Get-PwshCoreSessionConfiguration | Out-Null

$useRemoteSession = $bcVersion.Major -lt 28 # For BC28 and higher the import of the BC modules fails in WinRM-Sessions, so we will use direct execution for the overrides instead of remote sessions.

$moduleImportScriptBlock = { c:\run\prompt.ps1 -silent }

$commandNamesForAppManagement | ForEach-Object {
    Export-PwshCoreOverride -CommandName $_ -ModuleName 'Microsoft.BusinessCentral.Apps.Management' -ModuleImportScriptBlock $moduleImportScriptBlock -UseRemoteSession $useRemoteSession
}

$commandNamesForManagement | ForEach-Object {
    Export-PwshCoreOverride -CommandName $_ -ModuleName 'Microsoft.BusinessCentral.Management' -ModuleImportScriptBlock $moduleImportScriptBlock -UseRemoteSession $useRemoteSession
}