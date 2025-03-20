function Install-NuGetTools {
    [cmdletbinding()]
    Param(
        [switch]$Force
    )

    begin {
        $nugetMinimumVersion = [version]"2.8.5.201"
    }

    process {
        if ($Force -or (! (Get-PackageProvider -Name "NuGet" -ea Ignore | Where-Object { $_.Version -ge $nugetMinimumVersion }))) {
            Write-Host "Install Nuget Provider"
            Install-PackageProvider -Name "NuGet" -MinimumVersion $nugetMinimumVersion -Force
        }

        if ($Force -or (! (Get-InstalledModule "bccontainerhelper" -ea Ignore))) {
            Write-Host "Install BCContainerHelper"
            Install-Module -Name "bccontainerhelper" -Scope CurrentUser -Force
        }
    }
}
Export-ModuleMember -Function Install-NuGetTools