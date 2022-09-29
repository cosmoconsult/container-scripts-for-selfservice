$scripts = @(
                        (Join-Path $PSScriptRoot "AdditionalSetupArtifacts.ps1"),
                        (Join-Path $PSScriptRoot "AdditionalSetupSSH.ps1")
                   )


foreach ($script in $scripts){
    if (Test-Path -Path $script) {
        . ($script)
    }
}