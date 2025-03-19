function Get-NAVRoleTailoredClientFolder {
    [CmdletBinding()]
    param ()
    
    process {
        # Get the Role Tailored Client Folder
        $folder = (Get-Item "C:\Program Files (x86)\Microsoft Dynamics NAV\*\RoleTailored Client" -ErrorAction Ignore).FullName
        return $folder
    }
}
Export-ModuleMember -Function Get-NAVRoleTailoredClientFolder