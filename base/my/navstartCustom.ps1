$isPsCore = [System.Version]$PSVersionTable.PSVersion -ge [System.Version]"7.4.1"
if ($isPsCore) {
    
    $runPath = "c:\Run"
    $myPath = Join-Path $runPath "my"
    
    . (Join-Path $myPath "pscoreoverrides.ps1")

    if (Test-Path 'c:\run\my\prompt.ps1') {
        . 'c:\run\my\prompt.ps1'
    }
    else {
        . 'c:\run\prompt.ps1'
    }
    
    Install-Module -name SqlServer -RequiredVersion 22.2.0 -Scope AllUsers -Force
    Import-Module -name SqlServer -RequiredVersion 22.2.0 -Global -Force

}

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
        . ($script)
    }
}

# invoke default
. (Join-Path $runPath "navstart.ps1")