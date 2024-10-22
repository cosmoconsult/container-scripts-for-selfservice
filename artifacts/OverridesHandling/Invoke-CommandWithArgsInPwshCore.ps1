function Invoke-CommandWithArgsInPwshCore() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$ArgumentList
    )

    begin {
        $pwshCoreSessionConfigurationName = "PowerShell.7"
        $pwshCoreSessionName = "PwshCoreSession"
    }

    process {
        if ($PSVersionTable.PSEdition -eq 'Core') {
            return Invoke-CommandWithArgs -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
        }

        if (! $global:pwshCoreSession) {
            # Find existing session (open or disconnected)
            $global:pwshCoreSession = Get-PSSession -Name $pwshCoreSessionName -ea silentlycontinue | Where-Object { $_.State -in @("Opened","Disconnected") } | Select-Object -Last 1
        }

        if (! $global:pwshCoreSession) {
            # Check powershell core exists
            if (! (Get-Command pwsh -ea SilentlyContinue)) {
                Write-Warning "Powershell core not found... using current powershell session"
                return Invoke-CommandWithArgs -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
            }

            # Find or setup session configuration
            $pwshCoreSessionConfiguration = Get-PSSessionConfiguration -Name $pwshCoreSessionConfigurationName -ea silentlycontinue
            if (! $pwshCoreSessionConfiguration) {
                Write-Warning "Remoting for powershell core not enabled... enabling"
                pwsh -Command 'Enable-PSRemoting -wa SilentlyContinue'
                $pwshCoreSessionConfiguration = Get-PSSessionConfiguration -Name $pwshCoreSessionConfigurationName
            }
            if (! $pwshCoreSessionConfiguration) { return }

            # Create session
            Write-Host ("Creating powershell core session ({0})" -f $pwshCoreSessionConfiguration)
            $global:pwshCoreSession = New-PSSession -Name $pwshCoreSessionName -ConfigurationName $pwshCoreSessionConfiguration.Name -EnableNetworkAccess

            # Install modules in session
            Invoke-Command -Session $global:pwshCoreSession -ScriptBlock {
                Param(
                    [string[]]$Modules
                )
                foreach ($Module in $Modules) {
                    Import-Module $Module -DisableNameChecking -Force
                }
            } -ArgumentList @($MyInvocation.MyCommand.Module.Path)
        }
        if (! $global:pwshCoreSession) { return }

        # Reconnect disconnected session
        if ($global:pwshCoreSession.State -eq 'Disconnected') {
            Connect-PSSession -Session $global:pwshCoreSession
        }

        # Invoke in session
        Write-Host "Forwarding to powershell core session"
        Invoke-Command -Session $global:pwshCoreSession -ScriptBlock {
            Param(
                [Parameter(Mandatory = $true)]
                [string]$ScriptBlockString,
                [object[]]$ArgumentList
            )
            $scriptBlock = [scriptBlock]::create($ScriptBlockString)
            Invoke-CommandWithArgs -ScriptBlock $scriptBlock -ArgumentList $ArgumentList
        } -ArgumentList @($ScriptBlock.ToString(), $ArgumentList)
    }
}
Export-ModuleMember -Function Invoke-CommandWithArgsInPwshCore