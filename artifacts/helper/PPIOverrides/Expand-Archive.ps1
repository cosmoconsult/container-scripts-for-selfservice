function Expand-Archive() {
    # Must be a simple function for correct splatting
    try {
        $previousProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'

        Import-Module Microsoft.PowerShell.Archive -DisableNameChecking
        Microsoft.PowerShell.Archive\Expand-Archive @args
    }
    finally {
        $global:ProgressPreference = $previousProgressPreference
    }
}
Export-ModuleMember -Function Expand-Archive