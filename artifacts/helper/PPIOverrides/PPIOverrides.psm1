function Import-Module([string]$Name) {
    # Must be a simple function for correct splatting
    if ($Name -notin @($MyInvocation.MyCommand.Modul.Name, $MyInvocation.MyCommand.Modul.Path)) {
        Microsoft.PowerShell.Core\Import-Module -Name $Name @args -Global
    }
}

. (Join-Path $PSScriptRoot "Overrides/Invoke-WebRequest.ps1")
. (Join-Path $PSScriptRoot "Overrides/Expand-Archive.ps1")
. (Join-Path $PSScriptRoot "Overrides/Publish-NAVApp.ps1")