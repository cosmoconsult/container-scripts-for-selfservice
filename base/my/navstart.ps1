Import-Module (Join-Path $PSScriptRoot "..\helper\k8s-bc-helper.psd1") -Scope Global
Invoke-Command { & "pwsh.exe"       } -NoNewScope # PowerShell 7
$scripts = @(
                        (Join-Path $PSScriptRoot "ExtendedEnvironment.ps1"),
                        (Join-Path $PSScriptRoot "navstartCustomScripts.ps1"),
                        (Join-Path $PSScriptRoot "winrm.ps1")
                        (Join-Path $PSScriptRoot "timezone.ps1")
)

Write-Host "Start"
Write-Host "Running on Powershell Version:" $PSVersionTable.PSVersion

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        Invoke-script ($script)
    }
}

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)