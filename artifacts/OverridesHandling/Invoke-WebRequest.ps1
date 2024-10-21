
function Invoke-WebRequest() { 
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        $RemainingArgs
    )
    try {
        $previousProgressPreference = $global:ProgressPreference
        $global:ProgressPreference = 'SilentlyContinue'

        Invoke-CommandWithArgs -ScriptBlock { Microsoft.PowerShell.Utility\Invoke-WebRequest @namedArgs @positionalArgs } -Arguments $RemainingArgs
    }
    finally {
        $global:ProgressPreference = $previousProgressPreference
    }
}
Export-ModuleMember -Function Invoke-WebRequest