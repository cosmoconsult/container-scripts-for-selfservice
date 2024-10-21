function Invoke-CommandWithArgsInPwshCore() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$ArgumentList
    )

    if ($PSVersionTable.PSEdition -eq 'Core') {
        return Invoke-CommandWithArgs -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
    }

    $pwshCoreSessionName = "PwshCoreSession"
    $pwshCoreSessionConfigurationName = "PowerShell.7"
    $pwshCoreSession = Get-PSSession -Name $pwshCoreSessionName -ea silentlycontinue | Where-Object { $_.State -eq "Opened" } | Select-Object -Last 1

    if (! $pwshCoreSession) {
        Write-Host ("Creating powershell core session ({0})" -f $pwshCoreSessionConfigurationName)
        $pwshCoreSession = New-PSSession -Name $pwshCoreSessionName -ConfigurationName $pwshCoreSessionConfigurationName -EnableNetworkAccess 
        Invoke-Command -Session $pwshCoreSession -ScriptBlock {
            Param(
                [string[]]$Modules
            )
            foreach ($Module in $Modules) {
                Import-Module $Module -DisableNameChecking -Force
            }
        } -ArgumentList @($MyInvocation.MyCommand.Module.Path)
    }

    Write-Host "Redirecting to powershell core session"
    Invoke-Command -Session $pwshCoreSession -ScriptBlock {
        Param(
            [Parameter(Mandatory = $true)]
            [string]$ScriptBlockString,
            [object[]]$ArgumentList
        )
        $scriptBlock = [scriptBlock]::create($ScriptBlockString)
        Invoke-CommandWithArgs -ScriptBlock $scriptBlock -ArgumentList $ArgumentList
    } -ArgumentList @($ScriptBlock.ToString(), $ArgumentList)
}
Export-ModuleMember -Function Invoke-CommandWithArgsInPwshCore