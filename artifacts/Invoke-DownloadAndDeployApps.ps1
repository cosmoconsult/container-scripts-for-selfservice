[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('nuget', 'upack')]
    [string]$Type,

    # Common artifact identity
    [Parameter(Mandatory = $true)]
    [string]$Name,
    [string]$Version = "",

    # Azure DevOps (upack) coordinates
    [string]$Organization = "",
    [string]$Project = "",
    [string]$Feed = "",
    [string]$View = "",
    [ValidateSet('organization', 'project')]
    [string]$Scope = "project",
    [string]$Pat = "",

    # Deployment scope passed to Invoke-AppListDeployment.ps1
    [ValidateSet('Global', 'Tenant', 'Dev')]
    [string]$DeployScope = "Tenant"
)

$ErrorActionPreference = 'Stop'
c:\run\prompt.ps1

# Load the artifact-handling framework and the container's extended environment (trusted NuGet feeds, ADO settings).
# The API only sends the artifact coordinates; credentials/feeds are already provisioned in the container.
if (Test-Path "c:\run\PPIArtifactUtils.psd1") { Import-Module "c:\run\PPIArtifactUtils.psd1" -Force }
if (Test-Path "c:\run\my\ExtendedEnvironment.ps1") { . "c:\run\my\ExtendedEnvironment.ps1" }

$targetDir = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())

try {
    $downloadParameters = @{
        Name        = $Name
        Version     = $Version
        Type        = $Type
        Destination = $targetDir
        PassThru    = $true
    }

    if ($Type -eq 'upack') {
        $downloadParameters += @{
            Organization = $Organization
            Project      = $Project
            Feed         = $Feed
            View         = $View
            Scope        = $Scope
            Pat          = $Pat
        }
    } else {
        # NuGet downloads resolve dependencies (allButMicrosoft) from the container's trusted feeds
        Install-NuGetTools
        Initialize-NuGetFeeds
    }

    Invoke-DownloadArtifact @downloadParameters | Out-Null

    $appFiles = @(Get-ChildItem -Path $targetDir -Filter *.app -Recurse)
    if ($appFiles.Count -eq 0) { throw "No .app file found in downloaded artifact '$Name'" }

    # Deploy the whole set at once so it can be sorted by dependencies
    $appPaths = ($appFiles | ForEach-Object { $_.FullName }) -join ','
    & c:\run\Invoke-AppListDeployment.ps1 -AppsToDeploy $appPaths -Scope $DeployScope

    # Verify that every deployed app ended up installed before reporting success
    $allInstalled = $true
    foreach ($appFile in $appFiles) {
        $info = Get-NAVAppInfo -Path $appFile.FullName
        $deployed = Get-NAVAppInfo -ServerInstance BC -Name $info.Name -Publisher $info.Publisher -Version $info.Version -Tenant default -TenantSpecificProperties -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not ($deployed -and $deployed.IsInstalled)) { $allInstalled = $false }
    }
    if ($allInstalled) { Write-Host 'app deployment verified' }
}
finally {
    Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
}

