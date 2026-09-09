function Install-NuGetTools {
    [cmdletbinding()]
    Param(
        [switch]$Force
    )
    
    Install-DotNet10Runtime -Force:$Force

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

function Install-DotNet10Runtime {
    [cmdletbinding()]
    Param(
        [switch]$Force
    )

    $dotnetRuntimeInstalled = $false
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $installedRuntimes = & dotnet --list-runtimes
        $dotnetRuntimeInstalled = [bool]($installedRuntimes | Where-Object { $_ -match '^Microsoft\.NETCore\.App 10\.' }) -and
        [bool]($installedRuntimes | Where-Object { $_ -match '^Microsoft\.AspNetCore\.App 10\.' })
    }

    if ($Force -or (-not $dotnetRuntimeInstalled)) {
        Write-Host "Install .NET 10 Runtime"
        $dotnetInstallScript = Join-Path $env:TEMP "dotnet-install.ps1"
        Invoke-WebRequest -UseBasicParsing -Uri "https://dot.net/v1/dotnet-install.ps1" -OutFile $dotnetInstallScript
        & $dotnetInstallScript -Channel 10.0 -Runtime aspnetcore -InstallDir "C:\Program Files\dotnet"
        Remove-Item -Path $dotnetInstallScript -Force
    }
}
Export-ModuleMember -Function Install-NuGetTools