# Smbolic link needed to prevent endless recursion
if (! (Test-Path 'c:\run\my\prompt.link.ps1')) {
    New-Item -ItemType SymbolicLink -Path 'c:\run\my\prompt.link.ps1' -Target 'c:\run\prompt.ps1' | Out-Null
}

$scripts = @(
    (Join-Path $PSScriptRoot "PPIOverrides.ps1"),
    (Join-Path $PSScriptRoot "prompt.link.ps1")
)

try {
    $ServerExe = Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe"
    if ($ServerExe.VersionInfo.FileMajorPart -ge 28 -and $PSSenderInfo) {
        Write-Host "Import Types"
        Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\" | Get-ChildItem -Filter '*.dll' | ForEach-Object { try { Add-Type -Path $_.FullName } catch {} }
    }
}
catch {
    Write-Host "Unable to import types from NAV installation folder, some functionality may not work"
}

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        . ($script) -Silent:$silent
    }
}
