function Publish-NAVApp() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )
    
    Invoke-CommandWithArgsInPwshCore -ScriptBlock {
        if (! (Get-Module -Name Microsoft.BusinessCentral.Apps.Management)) {
            Push-Location
            c:\run\prompt.ps1 -silent
            Pop-Location
        }
        Microsoft.BusinessCentral.Apps.Management\Publish-NAVApp @namedArgs @positionalArgs 
    } -ArgumentList $RemainingArgs
}
Export-ModuleMember -Function Publish-NAVApp