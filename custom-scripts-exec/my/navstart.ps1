# this is from custom-scripts package
$downloadCustomScriptsScript = "C:\run\my\CC-DownloadCustomScripts.ps1"

if (Test-Path $downloadCustomScriptsScript) {
  . $downloadCustomScriptsScript
}

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)