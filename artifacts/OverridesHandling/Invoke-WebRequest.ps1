function Invoke-WebRequest() { 
    # Must be a simple function for correct splatting
    try {
        $previousProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'
        
        Microsoft.PowerShell.Utility\Invoke-WebRequest @args
    }
    finally {
        $global:ProgressPreference = $previousProgressPreference
    }
}
Export-ModuleMember -Function Invoke-WebRequest