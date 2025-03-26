function Install-NuGetTools {
    [cmdletbinding()]
    Param(
        [switch]$Force
    )
    
    $nugetMinimumVersion = [version]"2.8.5.201"

    if ($Force -or (! (Get-PackageProvider -Name "NuGet" -ea SilentlyContinue | Where-Object { $_.Version -ge $nugetMinimumVersion }))) {
        Write-Host "Install Nuget Provider"
        Install-PackageProvider -Name "NuGet" -MinimumVersion $nugetMinimumVersion -Scope CurrentUser -Force | Out-Null
    }

    # $nugetVersioningMinimumVersion = [version]"6.13.2"

    # if ($Force -or (! (Get-Package -Name "NuGet.Versioning" -ea SilentlyContinue | Where-object { $_.Version -ge $nugetVersioningMinimumVersion }))) {
    #     Write-Host "Install Nuget.Versioning"
    #     Install-Package -Name "NuGet.Versioning" -MinimumVersion $nugetVersioningMinimumVersion -Scope CurrentUser -Force | Out-Null
    # }

    if ($Force -or (! (Get-InstalledModule -Name "bccontainerhelper" -ea SilentlyContinue))) {
        Write-Host "Install BCContainerHelper"
        Install-Module -Name "bccontainerhelper" -Scope CurrentUser -Force | Out-Null
    }
}
Export-ModuleMember -Function Install-NuGetTools