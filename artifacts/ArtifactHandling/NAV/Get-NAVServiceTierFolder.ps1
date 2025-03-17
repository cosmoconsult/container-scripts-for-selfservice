function Get-NAVServiceTierFolder {
    [CmdletBinding()]
    param ()
    
    process {
        # Get the Service Tier Folder
        $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service" -ErrorAction SilentlyContinue).FullName
        if (! $serviceTierFolder) {
            Add-ArtifactsLog -message "Service Tier Folder not found at 'C:\Program Files\Microsoft Dynamics NAV\*\Service'" -severity Warn
        }
        return $serviceTierFolder
    }
}
Export-ModuleMember -Function Get-NAVServiceTierFolder