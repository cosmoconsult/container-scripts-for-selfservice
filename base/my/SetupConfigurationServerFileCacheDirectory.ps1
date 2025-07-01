$CustomConfigFile =  Join-Path $ServiceTierFolder "CustomSettings.config"
$CustomConfig = [xml](Get-Content $CustomConfigFile)

$serverFileCacheDirectory = $customConfig.SelectSingleNode("//appSettings/add[@key='ServerFileCacheDirectory']").Value

if (! $serverFileCacheDirectory) {
    Write-Host "ServerFileCacheDirectory not defined in Service Tier Config"
    return;
}

if (Test-Path -Path $serverFileCacheDirectory) {
    Write-Host "ServerFileCacheDirectory already exists: '$serverFileCacheDirectory'"
    return;
}

$defaultServerFileCacheDirectoryPattern = "C:\ProgramData\Microsoft\Microsoft Dynamics NAV\*\Server\${NavServiceName}"
$defaultServerFileCacheDirectory = (Get-Item $defaultServerFileCacheDirectoryPattern -ea SilentlyContinue).FullName
if (! $defaultServerFileCacheDirectory) {
    Write-Host "Default Server File Cache directory not found. Expected: '${defaultServerFileCacheDirectoryPattern}'"
    return;
}

Write-Host "Copy default Server File Cache from '${defaultServerFileCacheDirectory}' to '${serverFileCacheDirectory}'"
$duration = Measure-Command { 
    Copy-Item -Path $defaultServerFileCacheDirectory -Destination $serverFileCacheDirectory -Recurse 
}
Write-Host "Copy default Server File Cache done. (Duration: ${duration})"
