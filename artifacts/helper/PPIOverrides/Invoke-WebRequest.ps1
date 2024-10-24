function Invoke-WebRequest() { 
    # Must be a simple function for correct splatting
    try {
        $previousProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'
        
        Import-Module Microsoft.PowerShell.Utility -DisableNameChecking
        Microsoft.PowerShell.Utility\Invoke-WebRequest @args
    }
    finally {
        $global:ProgressPreference = $previousProgressPreference
    }
}
Export-ModuleMember -Function Invoke-WebRequest