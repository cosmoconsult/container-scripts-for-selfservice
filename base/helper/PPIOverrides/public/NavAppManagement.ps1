# Overrides only needed if not powershell core
if ($PSVersionTable.PSEdition -eq 'Core') { return }
# Overrides only needed if BC24 or higher
$bcVersion = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
if ($bcVersion -and $bcVersion.Major -lt 24) { return }

# Import PPI Powershell Core Utils
if (! (Get-Module 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -Global -Force
}

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

if ($bcVersion.Major -ge 28) {
    # Validate that PowerShell Core (pwsh) is available up front for the BC28+ path
    try {
        Get-Command pwsh -ErrorAction Stop | Out-Null
    }
    catch {
        throw "PowerShell Core ('pwsh') is required but was not found. Ensure that PowerShell Core is installed and 'pwsh' is available on PATH."
    }
    Invoke-PwshOverwriting -commandNames $commandNames
    
    Get-PwshCoreSessionConfiguration | Out-Null
}
else {
    # Create powershell core remote session (may enable remoting for powershell core)
    Get-PwshCoreSessionConfiguration | Out-Null

    $moduleName = 'Microsoft.BusinessCentral.Apps.Management'
    $moduleImportScriptBlock = { c:\run\prompt.ps1 -silent }
   
    $commandNames | ForEach-Object {
        Export-PwshCoreOverride -CommandName $_ -ModuleName $moduleName -ModuleImportScriptBlock $moduleImportScriptBlock
    }

    Export-PwshCoreOverride -CommandName 'Mount-NAVTenant' -ModuleName 'Microsoft.BusinessCentral.Management' -ModuleImportScriptBlock $moduleImportScriptBlock
}