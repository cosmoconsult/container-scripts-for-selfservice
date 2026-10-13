Get-ChildItem -LiteralPath $PSScriptRoot -Recurse | ForEach-Object { Unblock-File -Path $_.FullName }

Remove-Module PPIArtifactUtils -ErrorAction Ignore
Uninstall-module PPIArtifactUtils -ErrorAction Ignore

$modulePath = Join-Path $PSScriptRoot "PPIArtifactUtils.psd1"
Import-Module $modulePath -ErrorAction Stop