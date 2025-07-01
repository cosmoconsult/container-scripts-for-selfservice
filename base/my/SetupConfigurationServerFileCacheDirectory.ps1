$CustomConfigFile =  Join-Path $ServiceTierFolder "CustomSettings.config"
$CustomConfig = [xml](Get-Content $CustomConfigFile)

$serverFileCacheDirectory = $customConfig.SelectSingleNode("//appSettings/add[@key='ServerFileCacheDirectory']").Value

if (! $serverFileCacheDirectory) {
    return;
}

if (Test-Path -Path $serverFileCacheDirectory) {
    Write-Host "ServerFileCacheDirectory already exists: $serverFileCacheDirectory"
    return;
}
 
$originalServerFileCacheDirectory = (Get-Item "C:\ProgramData\Microsoft\Microsoft Dynamics NAV\*\Server\${NavServiceName}" -ea SilentlyContinue).FullName
if (! $originalServerFileCacheDirectory) {
    return;
}

Write-Host "Copy Server File Cache from ${originalServerFileCacheDirectory} to ${serverFileCacheDirectory}"
$duration = Measure-Command { 
    Copy-Item -Path $originalServerFileCacheDirectory -Destination $serverFileCacheDirectory -Recurse 
}
Write-Host "Copy Server File Cache done. (Duration: ${duration})"
