[CmdletBinding()]
param (
    [string]$url, 
    [string]$pat = "",
    [string]$exclude = "*Tests_*.app",
    [string]$ppiArtifactUtils = "c:\run\PPIArtifactUtils.psd1",
    [string]$ppiArtifactSettings = "c:\run\ArtifactSettings.ps1"
)

try {
    if (Test-Path $ppiArtifactUtils) { Import-Module $ppiArtifactUtils -DisableNameChecking -Force -ErrorAction SilentlyContinue }
    . "c:\run\ArtifactSettings.ps1"

    $started = Get-Date -Format "o"

    $targetDir = "$($env:TEMP)/$([System.IO.Path]::GetRandomFileName())"
    if (! $Tenantid) { $Tenantid = "default" }
    
    Write-Host "$([System.Environment]::NewLine)Download Artifact ..."
    Invoke-DownloadArtifact -url $url -destination $targetDir -accessToken $pat -telemetryClient $telemetryClient
    Write-Host "$([System.Environment]::NewLine)Import Artifact(s) ..."
    Import-Artifacts -Path $targetDir -NavServiceName $NavServiceName -ServerInstance $ServerInstance -Tenant $Tenantid -OperationScope "Download and Import Artifact - " -telemetryClient $telemetryClient
    Write-Host "Done"
    
    $properties = @{"organization" = $organization; "project" = $project; "feed" = $feed; "name" = $name; "scope" = $scope; "view" = $view; "protocolType" = $type; "url" = $url_output }
    Invoke-LogOperation -name "Download and Import Artifact" -success $success -started $started -properties $properties -telemetryClient $telemetryClient
    
    return $result
}
catch {
    Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -operation "Download and Import Artifact"
}