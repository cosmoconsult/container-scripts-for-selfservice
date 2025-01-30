Write-Host "Start Setup Configuration"

$scripts = @(
                        (Join-Path $runPath "EnablePerformanceCounter.ps1")
)
Push-Location
# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)

# Workaround for BC26 (NextMajor)
$version = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
if ($version -and $version.Major -eq 26) {
    if (Get-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName 'ServerFileCacheDirectory') { 
        Write-Host "Resetting ServerFileCacheDirectory"
        Set-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName 'ServerFileCacheDirectory' -KeyValue '' -WA SilentlyContinue
    }
}

Pop-Location


foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}