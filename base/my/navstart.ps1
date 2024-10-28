$scripts = @(
    (Join-Path $PSScriptRoot "PPIOverrides.ps1"),
    (Join-Path $PSScriptRoot "ExtendedEnvironment.ps1"),
    (Join-Path $PSScriptRoot "navstartCustomScripts.ps1"),
    (Join-Path $PSScriptRoot "winrm.ps1"),
    (Join-Path $PSScriptRoot "timezone.ps1"),
    (Join-Path $runPath $MyInvocation.MyCommand.Name) # default
)

Write-Host "Start"
Write-Host "Running on Powershell Version:" $PSVersionTable.PSVersion

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}