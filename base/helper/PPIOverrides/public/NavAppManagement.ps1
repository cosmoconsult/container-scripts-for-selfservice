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

$forEachOutputScriptBlock = { $_ }

if ($bcVersion.Major -ge 29) {
    # For BC29 and higher, we will also override Get-NAVAppInfo to handle issues with the returned AppId
    # The returned deserialized object for the AppId can not be passed directly to other NAV App cmdlets because they expect a Guid
    # For this we also add a ForEach-Object scriptblock to convert the deserialized AppId object to a Guid by returning the Value property of the deserialized AppId object instead of the deserialized object itself
    $commandNamesForAppManagement += 'Get-NAVAppInfo'

    $forEachOutputScriptBlock = {
        $object = $_

        # Return the object if it is not a PS Object
        if ($null -eq $object) { return $object }
        if ($object -isnot [PSObject]) { return $object }

        # Resolve properties of deserialized NavAppInfoDetail
        if ($object.PSObject.TypeNames -contains 'Deserialized.Microsoft.Dynamics.Nav.Apps.Management.Cmdlets.NavAppInfoDetail') {
            $object.PSObject.Properties |
                Where-Object { $_.Name -in 'AppId', 'PackageId' } |
                ForEach-Object {
                    $_.Value = $_.Value.Value
                }
        }

        return $object
    }
}

$commandNamesForAppManagement | ForEach-Object {
    Export-PwshCoreOverride `
        -CommandName $_ `
        -ModuleName 'Microsoft.BusinessCentral.Apps.Management' `
        -ModuleImportScriptBlock $moduleImportScriptBlock `
        -ForEachOutputScriptBlock $forEachOutputScriptBlock `
        -UseRemoteSession $useRemoteSession
}

$commandNamesForManagement | ForEach-Object {
    Export-PwshCoreOverride `
        -CommandName $_ `
        -ModuleName 'Microsoft.BusinessCentral.Management' `
        -ModuleImportScriptBlock $moduleImportScriptBlock `
        -ForEachOutputScriptBlock $forEachOutputScriptBlock `
        -UseRemoteSession $useRemoteSession
}