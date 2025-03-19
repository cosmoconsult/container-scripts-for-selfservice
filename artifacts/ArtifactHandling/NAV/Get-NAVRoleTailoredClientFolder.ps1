function Get-NAVRoleTailoredClientFolder {
    [CmdletBinding()]
    param ()
    
    process {
        # Get the Role Tailored Client Folder
        $folder = ($roleTailoredClientItem = Get-Item "C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client" -ErrorAction Ignore).FullName
        if (! $folder) {
            Add-ArtifactsLog -message "Role Tailored Client Folder not found at 'C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client'" -severity Warn
        }
        return $folder
    }
}
Export-ModuleMember -Function Get-NAVRoleTailoredClientFolder