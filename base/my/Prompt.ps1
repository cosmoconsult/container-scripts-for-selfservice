# Smbolic link needed to prevent endless recursion
if (! (Test-Path 'c:\run\my\prompt.link.ps1')) {
    New-Item -ItemType SymbolicLink -Path 'c:\run\my\prompt.link.ps1' -Target 'c:\run\prompt.ps1' | Out-Null
}

$scripts = @(
    (Join-Path $PSScriptRoot "PPIOverrides.ps1"),
    (Join-Path $PSScriptRoot "prompt.link.ps1")
)

foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        . ($script) -Silent:$silent
    }
}