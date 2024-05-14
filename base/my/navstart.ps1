$version = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion

if ($version -ge [Version]"24.0.0.0") {
    pwsh.exe (Join-Path $myPath "navstartCustom.ps1")
} else {
    . (Join-Path $myPath "navstartCustom.ps1")
}

