
function Test() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    $scriptBlock = {
        Write-Host @namedArgs @positionalArgs
    }

    if ($PSVersionTable.PSEdition -eq 'Core') {
        Invoke-CommandWithArgs -ScriptBlock $scriptBlock -Arguments $RemainingArgs
    } else {
        Invoke-CommandWithArgsInPwshCore -ScriptBlock { Test @namedArgs @positionalArgs } @RemainingArgs
    }
}
Export-ModuleMember -Function Test