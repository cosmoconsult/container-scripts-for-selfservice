function Install-NuGetTools {
    [cmdletbinding()]
    Param(
        [switch]$Force
    )
    
    $nugetMinimumVersion = [version]"2.8.5.201"

    if ($Force -or (! (Get-PackageProvider -Name "NuGet" -ea Ignore | Where-Object { $_.Version -ge $nugetMinimumVersion }))) {
        Write-Host "Install Nuget Provider"
        Install-PackageProvider -Name "NuGet" -MinimumVersion $nugetMinimumVersion -Force
    }

    if ($Force -or (! (Get-InstalledModule -Name "bccontainerhelper" -ea Ignore))) {
        Write-Host "Install BCContainerHelper"
        Install-Module -Name "bccontainerhelper" -Scope CurrentUser -Force
    }
}
Export-ModuleMember -Function Install-NuGetTools