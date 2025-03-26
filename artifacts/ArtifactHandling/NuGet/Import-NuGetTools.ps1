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

    if ($Force -or (! ("NuGet.Versioning.NuGetVersion" -as [type]))) {
        $nuGetVersioningPackagePath = Get-Package -Name "NuGet.Versioning" | Select-Object -ExpandProperty Source
        if (Test-Path -Path $nuGetVersioningPackagePath -PathType Leaf) {
            $nuGetVersioningPackagePath = Split-Path $nuGetVersioningPackagePath
        }
        $nuGetVersioningLibPath = Join-Path $nuGetVersioningPackagePath "lib"
        $nuGetVersioningDllFile = 
            Get-ChildItem -Path $nuGetVersioningLibPath -Filter "NuGet.Versioning.dll" -Recurse | 
            Select-Object -First 1
        if (! $nuGetVersioningDllFile) {
            throw "NuGet.Versioning.dll not found in $nuGetVersioningLibPath"
        }
        Add-Type -Path $nuGetVersioningDllFile.FullName
    }
}

Export-ModuleMember -Function Import-NuGetTools