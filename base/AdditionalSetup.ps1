$scripts = @(
                        (Join-Path $PSScriptRoot "AdditionalSetupArtifacts.ps1"),
                        (Join-Path $PSScriptRoot "AdditionalSetupSSH.ps1")
)

Write-Host "Start AdditionalSetup"

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}