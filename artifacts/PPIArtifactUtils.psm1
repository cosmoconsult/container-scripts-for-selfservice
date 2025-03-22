# Telemetry functions
. (Join-Path $PSScriptRoot "Telemetry/Invoke-LogEvent.ps1")
. (Join-Path $PSScriptRoot "Telemetry/Invoke-LogOperation.ps1")
. (Join-Path $PSScriptRoot "Telemetry/Invoke-LogError.ps1")
. (Join-Path $PSScriptRoot "Telemetry/New-EventTelemetry.ps1")
. (Join-Path $PSScriptRoot "Telemetry/New-ExceptionTelemetry.ps1")
. (Join-Path $PSScriptRoot "Telemetry/New-RequestTelemetry.ps1")
. (Join-Path $PSScriptRoot "Telemetry/Push-Telemetry.ps1")
. (Join-Path $PSScriptRoot "Telemetry/Get-TelemetryClient.ps1")

# Artifact Handling functions
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-AppFilesSortedByDependencies.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-PackageVersion.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Invoke-DownloadArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Invoke-DownloadArtifactInternal.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Resolve-DownloadArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Invoke-DownloadArtifactAsync.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Wait-DownloadArtifactAsync.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-ArtifactsFromEnvironment.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-FOBArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-AppArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-RIMArtifact.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-Artifacts.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Import-Fonts.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Get-ArtifactJson.ps1")

# Artifact Azure DevOps functions
. (Join-Path $PSScriptRoot "ArtifactHandling/AzureDevOps/Get-AzureDevOpsAccessToken.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/AzureDevOps/Get-AzureDevOpsApiFeatures.ps1")

# Artifact NAV functions
. (Join-Path $PSScriptRoot "ArtifactHandling/NAV/Get-NAVServiceTierFolder.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/NAV/Get-NAVRoleTailoredClientFolder.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/NAV/Import-NAVModules.ps1")

# Artifact BCContainerHelper functions
. (Join-Path $PSScriptRoot "ArtifactHandling/BcContainerHelper/Set-BCContainerHelperConfig.ps1")

# Artifact Nuget functions
. (Join-Path $PSScriptRoot "ArtifactHandling/NuGet/Set-NuGetFeeds.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/NuGet/Install-NuGetTools.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/NuGet/Import-NuGetTools.ps1")

# Artifact Log Handling functions
. (Join-Path $PSScriptRoot "ArtifactHandling/Log/Get-ArtifactsLog.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Log/Set-ArtifactsLog.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Log/Add-ArtifactsLog.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Log/ArtifactsLogEntry.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Log/New-ArtifactsLogEntry.ps1")
. (Join-Path $PSScriptRoot "ArtifactHandling/Log/Push-ArtifactsLogEntry.ps1")

# 4PS
. (Join-Path $PSScriptRoot "4PS/Wait-DataUpgradeToFinish.ps1")
. (Join-Path $PSScriptRoot "4PS/Test-DataUpgradeExecuted.ps1")
. (Join-Path $PSScriptRoot "4PS/Invoke-4PSArtifactHandling.ps1")
. (Join-Path $PSScriptRoot "4PS/Get-AppDatabaseName.ps1")
. (Join-Path $PSScriptRoot "4PS/Unpublish-AllNavAppsInServerInstance.ps1")
. (Join-Path $PSScriptRoot "4PS/Get-DemoDataFiles.ps1")