Import-Module Microsoft.PowerShell.Archive -DisableNameChecking

function Expand-Archive() {
    [CmdletBinding(DefaultParameterSetName = "PPIOverrides")]
    Param()

    DynamicParam {
        Get-DynamicParameters -TargetCommand $MyInvocation.MyCommand -SourceCommandName 'Microsoft.PowerShell.Archive\Expand-Archive'
    }

    begin {
        $dynamicParameters = $PSBoundParameters
        $MyInvocation.MyCommand.Parameters.Values | Where-Object { ! $_.IsDynamic } | Foreach-Object {
            $dynamicParameters.Remove($_.Name) | Out-Null
        }
    }

    process {
        try {
            $previousProgressPreference = $global:ProgressPreference
            $global:ProgressPreference = 'SilentlyContinue'
            
            Microsoft.PowerShell.Archive\Expand-Archive @dynamicParameters
        }
        finally {
            $global:ProgressPreference = $previousProgressPreference
        }
    }
}
Export-ModuleMember -Function Expand-Archive