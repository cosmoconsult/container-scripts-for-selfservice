# Smbolic link needed to prevent endless recursion
if (! (Test-Path 'c:\run\my\prompt.link.ps1')) {
    New-Item -ItemType SymbolicLink -Path 'c:\run\my\prompt.link.ps1' -Target 'c:\run\prompt.ps1' | Out-Null
}

# Import NAV/BC modules
. 'c:\run\my\prompt.link.ps1' -silent:$silent

# Import PPIOverrides module
if (! (Get-Module PPIOverrides)) {
    if (Test-Path 'c:\run\helper\PPIOverrides\PPIOverrides.psm1') {
        Import-Module "c:\run\helper\PPIOverrides\PPIOverrides.psm1" -DisableNameChecking -Force
    }
}