# this is from custom-scripts package
$downloadCustomScriptsScript = "C:\run\my\CC-DownloadCustomScripts.ps1"

$volPath = "$env:volPath"

if ($volPath -ne "" -and (Get-Item -path $volPath).GetFileSystemInfos().Count -ne 0) {
  # database volume path is provided and the database files are there, so this seems to be a restart
  $cosmoServiceRestart = $true
}
else {
  $cosmoServiceRestart = $false
}

if (Test-Path $downloadCustomScriptsScript) {
  . $downloadCustomScriptsScript
}

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)