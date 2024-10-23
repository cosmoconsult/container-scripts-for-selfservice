function Import-Module() {
    # Must be a simple function for correct splatting
    Microsoft.PowerShell.Core\Import-Module @args -Global
}

. (Join-Path $PSScriptRoot "Overrides/Invoke-WebRequest.ps1")
. (Join-Path $PSScriptRoot "Overrides/Expand-Archive.ps1")
. (Join-Path $PSScriptRoot "Overrides/Publish-NAVApp.ps1")