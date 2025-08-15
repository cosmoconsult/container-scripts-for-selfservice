$customConfigFile =  Join-Path $ServiceTierFolder "CustomSettings.config"
$customConfig = [xml](Get-Content $customConfigFile)

$serverFileCacheDirectory = $customConfig.SelectSingleNode("//appSettings/add[@key='ServerFileCacheDirectory']").Value

if (! $serverFileCacheDirectory) {
    Write-Host "ServerFileCacheDirectory not defined in Service Tier Config"
    return;
}

Write-Host "Server File Cache Directory: '$serverFileCacheDirectory'"

if (Test-Path -Path $serverFileCacheDirectory) {
    Write-Host "Server File Cache Directory already exists"
    return;
}

$defaultServerFileCacheDirectoryPattern = "C:\ProgramData\Microsoft\Microsoft Dynamics NAV\*\Server\${NavServiceName}"
$defaultServerFileCacheDirectory = (Get-Item $defaultServerFileCacheDirectoryPattern -ea SilentlyContinue).FullName
if (! $defaultServerFileCacheDirectory) {
    Write-Host "Default Server File Cache Directory not found. Expected: '${defaultServerFileCacheDirectoryPattern}'"
    return;
}

Write-Host "Default Server File Cache Directory: '${defaultServerFileCacheDirectory}'"

Write-Host "Copy default Server File Cache to Server File Cache"
$duration = Measure-Command { 
    Copy-Item -Path $defaultServerFileCacheDirectory -Destination $serverFileCacheDirectory -Recurse 
}
Write-Host "Copy default Server File Cache to Server File Cache done. (Duration: ${duration})"