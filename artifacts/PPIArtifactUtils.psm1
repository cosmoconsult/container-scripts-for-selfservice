# Telemetry functions
. (Join-Path $PSScriptRoot "Telemetry/Invoke-LogEvent.ps1")
. (Join-Path $PSScriptRoot "Telemetry/Invoke-LogOperation.ps1")
. (Join-Path $PSScriptRoot "Telemetry/Invoke-LogError.ps1")
. (Join-Path $PSScriptRoot "Telemetry/Get-TelemetryClient.ps1")

# Artifact Handling functions
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-AppFilesSortedByDependencies.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-PackageVersion.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Invoke-DownloadArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-ArtifactsFromEnvironment.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-FOBArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-AppArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-RIMArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-Artifacts.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-ArtifactsLog.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Set-ArtifactsLog.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Add-ArtifactsLog.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-Fonts.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-ArtifactJson.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-NugetTools.ps1")

# Override Handling functions
. (Join-Path $PSScriptRoot "OverrideHandling/Invoke-CommandWithArgs.ps1")
. (Join-Path $PSScriptRoot "OverrideHandling/Invoke-CommandWithArgsAndJsonOutput.ps1")
. (Join-Path $PSScriptRoot "OverrideHandling/Invoke-CommandWithArgsInPwshCore.ps1")
. (Join-Path $PSScriptRoot "OverrideHandling/Invoke-WebRequest.ps1")
. (Join-Path $PSScriptRoot "OverrideHandling/Expand-Archive.ps1")
. (Join-Path $PSScriptRoot "OverrideHandling/Publish-NAVApp.ps1")
. (Join-Path $PSScriptRoot "OverrideHandling/Overrides.ps1")

# 4PS
. (Join-Path $PSScriptRoot "4PS/Wait-DataUpgradeToFinish.ps1")
. (Join-Path $PSScriptRoot "4PS/Check-DataUpgradeExecuted.ps1")
. (Join-Path $PSScriptRoot "4PS/Invoke-4PSArtifactHandling.ps1")
. (Join-Path $PSScriptRoot "4PS/Get-AppDatabaseName.ps1")
. (Join-Path $PSScriptRoot "4PS/Unpublish-AllNavAppsInServerInstance.ps1")
. (Join-Path $PSScriptRoot "4PS/Get-DemoDataFiles.ps1")