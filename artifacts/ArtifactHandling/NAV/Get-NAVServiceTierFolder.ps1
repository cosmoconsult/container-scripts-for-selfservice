function Get-NAVServiceTierFolder {
    [CmdletBinding()]
    param ()
    
    process {
        # Get the Service Tier Folder
        $folder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service" -ErrorAction SilentlyContinue).FullName
        if (! $folder) {
            Add-ArtifactsLog -message "Service Tier Folder not found at 'C:\Program Files\Microsoft Dynamics NAV\*\Service'" -severity Warn
        }
        return $folder
    }
}
Export-ModuleMember -Function Get-NAVServiceTierFolder