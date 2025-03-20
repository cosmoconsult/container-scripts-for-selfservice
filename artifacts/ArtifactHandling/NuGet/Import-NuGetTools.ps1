function Import-NuGetTools {
    [cmdletbinding()]
    Param(
        [object[]]$Feeds = @(),
        [switch]$Force
    )

    begin {
        if (! $PSBoundParameters.ContainsKey("Feeds")) {
            $Feeds = Get-NuGetFeeds
        }
    }

    process {
        Install-NuGetTools
        
        if ($Force -or (! (Get-Module "bccontainerhelper"))) {
            Write-Host "Import BCContainerHelper"
            Import-Module -Name "bccontainerhelper" -DisableNameChecking -Scope Global -Force:$Force

            Write-Host "Add trusted NuGet feeds to BCContainerHelperConfig"
            $bcContainerHelperConfig.TrustedNuGetFeeds += $Feeds
        }
    }
}

Export-ModuleMember -Function Import-NuGetTools