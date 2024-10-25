Import-Module Microsoft.PowerShell.Utility -DisableNameChecking -Global

function Invoke-WebRequest() {
    [CmdletBinding()]
    Param()

    DynamicParam {
        Get-DynamicParameters -TargetCommand $MyInvocation.MyCommand -SourceCommandName 'Microsoft.PowerShell.Utility\Invoke-WebRequest'
    }
    
    begin {
        $MyInvocation.MyCommand.Parameters.Values | Where-Object { ! $_.IsDynamic } | Foreach-Object {
            $PSBoundParameters.Remove($_.Name) | Out-Null
        }
    }
    
    process {
        try {
            $previousProgressPreference = $global:ProgressPreference
            $global:ProgressPreference = 'SilentlyContinue'
            
            Microsoft.PowerShell.Utility\Invoke-WebRequest @PSBoundParameters
        }
        finally {
            $global:ProgressPreference = $previousProgressPreference
        }
    }
}
Export-ModuleMember -Function Invoke-WebRequest