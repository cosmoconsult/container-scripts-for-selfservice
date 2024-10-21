function Publish-NAVApp() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    $scriptBlock = {
        if (! (Get-Module -Name Microsoft.BusinessCentral.Apps.Management)) {
            Push-Location
            c:\run\prompt.ps1 -silent
            Pop-Location
        }
        Microsoft.BusinessCentral.Apps.Management\Publish-NAVApp @namedArgs @positionalArgs
    }

    if ($PSVersionTable.PSEdition -eq 'Core') {
        Invoke-CommandWithArgs -ScriptBlock $scriptBlock -Arguments $RemainingArgs
    } else {
        Invoke-CommandWithArgsInPwshCore -ScriptBlock { Publish-NAVApp @namedArgs @positionalArgs } @RemainingArgs
    }
}
Export-ModuleMember -Function Publish-NAVApp