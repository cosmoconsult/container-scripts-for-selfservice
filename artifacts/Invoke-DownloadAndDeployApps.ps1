[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('nuget', 'stream')]
    [string]$Type,
    [string]$Name = "",
    [string]$Version = "",
    [long]$InputLength = 0,
    [ValidateSet('Global', 'Tenant')]
    [string]$DeployScope = "Tenant"
)

c:\run\prompt.ps1
$targetDir = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())

try {
    $artifactDir = $targetDir

    if ($Type -eq 'stream') {
        if ($InputLength -le 0) {
            throw "Streamed artifact length must be greater than zero"
        }

        New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        $archivePath = Join-Path $targetDir 'artifact.zip'
        $artifactDir = Join-Path $targetDir 'extracted'
        $inputStream = [Console]::OpenStandardInput()
        $archiveStream = $null
        try {
            $archiveStream = [System.IO.File]::Open($archivePath, [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $buffer = [byte[]]::new(81920)
            [long]$remaining = $InputLength
            while ($remaining -gt 0) {
                $bytesToRead = [int][Math]::Min($buffer.Length, $remaining)
                $bytesRead = $inputStream.Read($buffer, 0, $bytesToRead)
                if ($bytesRead -le 0) {
                    throw "Stream ended with $remaining artifact bytes remaining"
                }
                $archiveStream.Write($buffer, 0, $bytesRead)
                $remaining -= $bytesRead
            }
        }
        finally {
            if ($archiveStream) {
                $archiveStream.Dispose()
            }
        }

        Expand-Archive -Path $archivePath -DestinationPath $artifactDir -Force
    }
    else {
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
    }

    $appFiles = @(Get-ChildItem -Path $artifactDir -Filter *.app -Recurse)

    if ($appFiles.Count -eq 0) {
        $artifactName = if ($Name) { "'$Name'" } else { 'stream' }
        Write-Host "No .app file found in downloaded artifact $artifactName"
        return
    }

    $appPaths = ($appFiles | ForEach-Object { $_.FullName }) -join ','
    & c:\run\Invoke-AppListDeployment.ps1 -AppsToDeploy $appPaths -Scope $DeployScope

    $allInstalled = $true
    foreach ($appFile in $appFiles) {
        $info = Get-NAVAppInfo -Path $appFile.FullName
        $deployed = Get-NAVAppInfo -ServerInstance BC -Name $info.Name -Publisher $info.Publisher -Version $info.Version -Tenant default -TenantSpecificProperties -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not ($deployed -and $deployed.IsInstalled)) { $allInstalled = $false }
    }
    if ($allInstalled) { Write-Host 'app deployment verified' }
}
catch {
    Write-Host "App deployment failed: $($_.Exception.Message)"
    throw
}
finally {
    Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
}
