# this is from custom-scripts package
$downloadCustomScriptsScript = "C:\run\my\CC-DownloadCustomScripts.ps1"

$volPath = "$env:volPath"

if ($volPath -ne "" -and (Get-ChildItem $volPath).Count -ne 0) {
  # database volume path is provided and the database files are there, so this seems to be a restart
  $env:cosmoServiceRestart = $true
  Write-Host "This seems to be a service restart"
}
else {
  $env:cosmoServiceRestart = $false
  Write-Host "This seems to be a regular service start"
}

if (Test-Path $downloadCustomScriptsScript) {
  . $downloadCustomScriptsScript
}

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)
