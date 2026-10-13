$scripts = @(
    (Join-Path $PSScriptRoot "PPIOverrides.ps1"),
    (Join-Path $PSScriptRoot "PPIAsyncUtils.ps1"),
    (Join-Path $PSScriptRoot "PPIArtifactUtils.ps1")
)

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}