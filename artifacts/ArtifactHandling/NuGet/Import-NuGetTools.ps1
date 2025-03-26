function Import-NuGetTools {
    [cmdletbinding()]
    Param(
        [switch]$Force,
        [switch]$Install
    )
    
    if ($Install) {
        Install-NuGetTools
    }
    
    if ($Force -or (! (Get-Module -Name "bccontainerhelper"))) {
        Write-Host "Import BCContainerHelper"
        Import-Module -Name "bccontainerhelper" -DisableNameChecking -Scope Global -Force:$Force
    }
}

Export-ModuleMember -Function Import-NuGetTools