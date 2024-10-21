function Invoke-CommandWithArgsInPwshCore() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )

    $coreScriptBlock = {
        [CmdletBinding(DefaultParameterSetName = 'Default')]
        Param(
            [Parameter(Mandatory = $true)]
            [string]$ScriptBlock,
            [string[]]$Modules,
            [Parameter(ValueFromRemainingArguments = $true)]
            [object[]]$RemainingArgs
        )
        foreach ($Module in $Modules) {
            Import-Module $Module -DisableNameChecking -Force
        }
        Invoke-CommandWithArgsAndJsonOutput -ScriptBlock ([scriptblock]::create("$ScriptBlock")) -Arguments $RemainingArgs
    }

    Write-Host "Redirecting to powershell core (pwsh)"
    $output = pwsh -Interactive -CommandWithArgs $coreScriptBlock.ToString() -ScriptBlock $ScriptBlock.ToString() -Modules $MyInvocation.MyCommand.Module.Path @RemainingArgs
    try {
        $result = $output | ConvertFrom-Json
        $result.info | ForEach-Object { Write-Host $_ }
        $result.warn | ForEach-Object { Write-Warning $_ }
        $result.err  | ForEach-Object { Write-Error $_ }
        $result.out
    }
    catch {
        Write-Error ("Powershell core (pwsh) did not return a valid JSON:`n{0}" -f ($output -join "`n"))
    }
}
Export-ModuleMember -Function Invoke-CommandWithArgsInPwshCore