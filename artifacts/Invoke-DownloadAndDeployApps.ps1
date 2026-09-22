[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('nuget', 'app', 'zip')]
    [string]$Type,
    [string]$Name = "",
    [string]$Version = "",
    [string]$ArtifactPath = "",
    [ValidateSet('Global', 'Tenant', 'Dev')]
    [string]$DeployScope = "Tenant",
    [ValidateSet('Add', 'ForceSync')]
    [string]$SyncMode = "Add",
    [string]$PublicDnsName = ""
)

c:\run\prompt.ps1
Write-Host "[Deploy] Start Type=$Type Name='$Name' Version='$Version' ArtifactPath='$ArtifactPath' Scope=$DeployScope SyncMode=$SyncMode"
$targetDir = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())
$maxExtractedSize = 1GB
$maxArchiveEntries = 1000

try {
    $artifactDir = $targetDir
    Write-Host "[Deploy] Preparing artifact directory '$targetDir'"
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

    switch ($Type) {
        'app' {
            Write-Host "[Deploy] Staging APP artifact from '$ArtifactPath'"
            if (-not $ArtifactPath) {
                throw "ArtifactPath is required for app deployments"
            }
            $artifactFolder = Split-Path -Parent $ArtifactPath
            New-Item -ItemType Directory -Force -Path $artifactFolder | Out-Null
            Write-Host "[Deploy] Ensured artifact directory '$artifactFolder'"
            for ($attempt = 1; $attempt -le 10 -and -not (Test-Path -LiteralPath $ArtifactPath); $attempt++) {
                Write-Host "[Deploy] Waiting for staged artifact (attempt $attempt/10)"
                Start-Sleep -Milliseconds 500
            }
            $targetPath = Join-Path $targetDir 'artifact.app'
            Copy-Item -LiteralPath $ArtifactPath -Destination $targetPath -ErrorAction Stop
            break
        }
        'zip' {
            Write-Host "[Deploy] Staging and extracting ZIP artifact from '$ArtifactPath'"
            if (-not $ArtifactPath) {
                throw "ArtifactPath is required for ZIP deployments"
            }
            $archivePath = Join-Path $targetDir 'artifact.zip'
            Copy-Item -LiteralPath $ArtifactPath -Destination $archivePath -ErrorAction Stop
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $archive = [System.IO.Compression.ZipFile]::OpenRead($archivePath)
            try {
                if ($archive.Entries.Count -gt $maxArchiveEntries) {
                    throw "ZIP contains more than $maxArchiveEntries entries"
                }
                [long]$expandedSize = 0
                foreach ($entry in $archive.Entries) {
                    $expandedSize += $entry.Length
                    if ($expandedSize -gt $maxExtractedSize) {
                        throw "ZIP expands beyond the $maxExtractedSize byte limit"
                    }
                }
            }
            finally {
                $archive.Dispose()
            }
            $artifactDir = Join-Path $targetDir 'extracted'
            Expand-Archive -Path $archivePath -DestinationPath $artifactDir -Force
            break
        }
        'nuget' {
            Write-Host "[Deploy] Downloading NuGet artifact Name='$Name' Version='$Version'"
            Import-Module "c:\run\PPIArtifactUtils.psd1" -Force
            . "c:\run\my\ExtendedEnvironment.ps1"
            try {
                Install-NuGetTools
                Initialize-NuGetFeeds
            }
            catch {
                Write-Host "NuGet feed initialization warning: $($_.Exception.Message)"
            }

            Invoke-DownloadArtifact -Name $Name -Version $Version -Type nuget -Destination $targetDir
            break
        }
    }

    $appFiles = @(Get-ChildItem -Path $artifactDir -Filter *.app -Recurse)
    Write-Host "[Deploy] Found $($appFiles.Count) app file(s)"

    if ($appFiles.Count -eq 0) {
        $artifactName = if ($Name) { "'$Name'" } else { $Type }
        throw "No .app file found in downloaded artifact $artifactName"
    }

    $appPaths = ($appFiles | ForEach-Object { $_.FullName }) -join ','
    Write-Host "[Deploy] Starting ordered deployment Scope=$DeployScope SyncMode=$SyncMode"
    & c:\run\Invoke-AppListDeployment.ps1 -AppsToDeploy $appPaths -Scope $DeployScope -SyncMode $SyncMode -PublicDnsName $PublicDnsName

    $allInstalled = $true
    foreach ($appFile in $appFiles) {
        $info = Get-NAVAppInfo -Path $appFile.FullName
        $deployed = Get-NAVAppInfo -ServerInstance BC -Name $info.Name -Publisher $info.Publisher -Version $info.Version -Tenant default -TenantSpecificProperties -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not ($deployed -and $deployed.IsInstalled)) { $allInstalled = $false }
    }
    if ($allInstalled) { Write-Host "[Deploy] App deployment verified successfully" }
    else { Write-Host "[Deploy] App deployment verification failed" }
}
catch {
    Write-Host "App deployment failed: $($_.Exception.Message)"
    throw
}
finally {
    Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
    if ($ArtifactPath) {
        Remove-Item -LiteralPath $ArtifactPath -Force -ErrorAction SilentlyContinue
    }
}
