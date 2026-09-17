[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet('nuget', 'app', 'zip')]
    [string]$Type,
    [string]$Name = "",
    [string]$Version = "",
    [long]$InputLength = 0,
    [ValidateSet('Global', 'Tenant')]
    [string]$DeployScope = "Tenant"
)

c:\run\prompt.ps1
$targetDir = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())

function Save-StandardInputToFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [long]$Length
    )

    if ($Length -le 0) {
        throw "Input length must be greater than zero"
    }

    $inputStream = [Console]::OpenStandardInput()
    $outputStream = $null
    try {
        $outputStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $buffer = [byte[]]::new(81920)
        [long]$remaining = $Length
        while ($remaining -gt 0) {
            $bytesToRead = [int][Math]::Min($buffer.Length, $remaining)
            $bytesRead = $inputStream.Read($buffer, 0, $bytesToRead)
            if ($bytesRead -le 0) {
                throw "Stream ended with $remaining bytes remaining"
            }

            $outputStream.Write($buffer, 0, $bytesRead)
            $remaining -= $bytesRead
        }
    }
    finally {
        if ($outputStream) {
            $outputStream.Dispose()
        }
    }
}

try {
    $artifactDir = $targetDir
    New-Item -Path $targetDir -ItemType Directory -Force | Out-Null

    switch ($Type) {
        'app' {
            Save-StandardInputToFile -Path (Join-Path $targetDir 'artifact.app') -Length $InputLength
            break
        }
        'zip' {
            $archivePath = Join-Path $targetDir 'artifact.zip'
            Save-StandardInputToFile -Path $archivePath -Length $InputLength

            $artifactDir = Join-Path $targetDir 'extracted'
            Expand-Archive -Path $archivePath -DestinationPath $artifactDir -Force
            break
        }
        'nuget' {
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

    if ($appFiles.Count -eq 0) {
        $artifactName = if ($Name) { "'$Name'" } else { $Type }
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
