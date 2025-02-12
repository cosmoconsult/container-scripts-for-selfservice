# Output version of the business central server executable
$bcVersion = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
Write-Host "Dev. Server Version : $bcVersion"