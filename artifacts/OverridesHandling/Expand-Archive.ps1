
function Expand-Archive() { 
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        $RemainingArgs
    )
    try {
        $previousProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'

        Invoke-CommandWithArgs -ScriptBlock { 
            Microsoft.PowerShell.Archive\Expand-Archive @namedArgs @positionalArgs 
        } -ArgumentList $RemainingArgs
    }
    finally {
        $global:ProgressPreference = $previousProgressPreference
    }
}
Export-ModuleMember -Function Expand-Archive