function Install-NuGetTools {
    [cmdletbinding()]
    Param(
        [switch]$Force
    )
    
    $nugetMinimumVersion = [version]"2.8.5.201"

    if ($Force -or (! (Get-PackageProvider -Name "NuGet" -ea SilentlyContinue | Where-Object { $_.Version -ge $nugetMinimumVersion }))) {
        Write-Host "Install NuGet Provider"
        Install-PackageProvider -Name "NuGet" -MinimumVersion $nugetMinimumVersion -Scope CurrentUser -Force | Out-Null
    }

    if ($Force -or (! (Get-InstalledModule -Name "bccontainerhelper" -ea SilentlyContinue))) {
        Write-Host "Install BCContainerHelper"
        Install-Module -Name "bccontainerhelper" -Scope CurrentUser -Force | Out-Null
    }
}
Export-ModuleMember -Function Install-NuGetTools