function Install-NuGetTools {
    [cmdletbinding()]
    Param(
        [switch]$Force
    )

    process {
        Write-Host "Install Nuget Provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force:$Force

        Write-Host "Import BCContainerHelper"
        Install-Module -Name "bccontainerhelper" -Scope CurrentUser -Force:$Force
    }
}
Export-ModuleMember -Function Install-NuGetTools