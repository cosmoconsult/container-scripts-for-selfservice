Import-Module Microsoft.PowerShell.Archive -DisableNameChecking -Global

function Expand-Archive() {
    [CmdletBinding(DefaultParameterSetName = "PPIOverrides")]
    Param()

    DynamicParam {
        ConvertTo-DynamicParameters -CommandName 'Microsoft.PowerShell.Archive\Expand-Archive'
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
            
            Microsoft.PowerShell.Archive\Expand-Archive @PSBoundParameters
        }
        finally {
            $global:ProgressPreference = $previousProgressPreference
        }
    }
}
Export-ModuleMember -Function Expand-Archive