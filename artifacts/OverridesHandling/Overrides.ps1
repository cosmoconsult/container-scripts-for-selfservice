
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
        Invoke-CommandWithArgsInPwshCore -ScriptBlock {
            Import-Module $env:PSModulePath
            Publish-NAVApp @namedArgs @positionalArgs
        } -Arguments $RemainingArgs
    }
}
Export-ModuleMember -Function Publish-NAVApp

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
        Invoke-CommandWithArgsAndJsonResult -ScriptBlock ([scriptblock]::create("$ScriptBlock")) -Arguments $RemainingArgs
        # Invoke-CommandWithArgs -ScriptBlock ([scriptblock]::create("$ScriptBlock")) -Arguments $RemainingArgs
    }

    $results = pwsh -Interactive -CommandWithArgs $coreScriptBlock.ToString() -ScriptBlock $ScriptBlock.ToString() -Modules $MyInvocation.MyCommand.Module.Path @RemainingArgs `
        | ConvertFrom-Json -ErrorAction SilentlyContinue
    $results.info | ForEach-Object { Write-Information $_ }
    $results.warn | ForEach-Object { Write-Warning $_ }
    $results.err  | ForEach-Object { Write-Error $_ }
    $results.out  | ForEach-Object { $_ }
    #pwsh -Interactive -CommandWithArgs $coreScriptBlock.ToString() -ScriptBlock $ScriptBlock.ToString() -Modules $MyInvocation.MyCommand.Module.Path @RemainingArgs
}
Export-ModuleMember -Function Invoke-CommandWithArgsInPwshCore

function Invoke-CommandWithArgsAndJsonResult{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [object[]]$Arguments
    )
    Invoke-CommandWithArgs -ScriptBlock $ScriptBlock -Arguments $Arguments `
        -ErrorAction Continue -InformationVariable info -WarningVariable warn -ErrorVariable err -OutVariable out `
            *>$null
    @{
        info = @($info | ForEach-Object { $_.MessageData.Message })
        warn = @($warn | ForEach-Object { $_.Message })
        err  = @($err | ForEach-Object { $_.Exception.Message })
        out = @($out | ForEach-Object { $_.MessageData.Message })
    } | ConvertTo-Json -ErrorAction SilentlyContinue
}
Export-ModuleMember -Function Invoke-CommandWithArgsAndJsonResult

function Invoke-CommandWithArgs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [object[]]$Arguments
    )
    $namedArgs = @{}
    $positionalArgs = @()
    $name = $null
    foreach ($arg in $Arguments) {
        if ($arg -like '-*') {
            if ($name) {
                $namedArgs[$name] = $true
            }
            $name = $arg.TrimStart('-')
            $name = $arg.TrimEnd(':')
        } elseif ($name) {
            if ($namedArgs.ContainsKey($name)) {
                $namedArgs[$name] = @($namedArgs[$name], $arg)
            } else {
                $namedArgs[$name] = $arg    
            }
            $name = $null
        } else {
           $positionalArgs += $arg
        }
    }
    if ($name) {
        $namedArgs[$name] = $true
    }
    
    & $ScriptBlock
}
Export-ModuleMember -Function Invoke-CommandWithArgs