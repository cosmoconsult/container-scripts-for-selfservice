function Import-NuGetTools {
    [cmdletbinding()]
    Param(
        [object[]]$Feeds = @(),
        [switch]$Force,
        [switch]$Install
    )
    
    if ($Install) {
        Install-NuGetTools
    }

    if (! $PSBoundParameters.ContainsKey("Feeds")) {
        $Feeds = Get-NuGetFeeds
    }
    
    if ($Force -or (! (Get-Module -Name "bccontainerhelper"))) {
        Write-Host "Import BCContainerHelper"
        Import-Module -Name "bccontainerhelper" -DisableNameChecking -Scope Global -Force:$Force
    }

    Write-Host "Set trusted NuGet feeds of BCContainerHelperConfig"
    $bcContainerHelperConfig.TrustedNuGetFeeds = @(
        Compare-Object -ReferenceObject $TrustedFeeds -DifferenceObject $bcContainerHelperConfig.TrustedNuGetFeeds -IncludeEqual | 
            Select-Object -ExpandProperty InputObject
    )
}

Export-ModuleMember -Function Import-NuGetTools