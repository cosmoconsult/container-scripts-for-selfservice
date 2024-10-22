function Invoke-WebRequest() { 
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