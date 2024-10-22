function Invoke-CommandInPwshCore() {
    Param(
        [scriptblock]$ScriptBlock
    )

    if ($PSVersionTable.PSEdition -eq 'Core') {
        return & $ScriptBlock @args
    }

    $pwshCoreSessionConfigurationName = "PowerShell.7"
    $pwshCoreSessionName = "PwshCoreSession"

    if (! $pwshCoreSession) {
        # Find existing session (open or disconnected)
        $pwshCoreSession = Get-PSSession -Name $pwshCoreSessionName -ea silentlycontinue | Where-Object { $_.State -in @("Opened","Disconnected") } | Select-Object -Last 1
    }

    if (! $pwshCoreSession) {
        # Check powershell core exists
        if (! (Get-Command pwsh -ea SilentlyContinue)) {
            Write-Warning "Powershell core not found... using current powershell session"
            return & $ScriptBlock @args
        }

        # Find or setup session configuration
        $pwshCoreSessionConfiguration = Get-PSSessionConfiguration -Force | Where-Object { $_.Name -eq $pwshCoreSessionConfigurationName } | Select-Object -First 1
        if (! $pwshCoreSessionConfiguration) {
            Write-Warning "Remoting for powershell core not enabled... enabling"
            pwsh -Command 'Enable-PSRemoting -wa SilentlyContinue'
            $pwshCoreSessionConfiguration = Get-PSSessionConfiguration -Name $pwshCoreSessionConfigurationName
        }
        if (! $pwshCoreSessionConfiguration) { return }

        # Create session
        Write-Host ("Creating powershell core session ({0})" -f $pwshCoreSessionConfiguration.Name)
        $pwshCoreSession = New-PSSession -Name $pwshCoreSessionName -ConfigurationName $pwshCoreSessionConfiguration.Name -EnableNetworkAccess

        # Install modules in session
        Invoke-Command -Session $pwshCoreSession -ScriptBlock {
            Param(
                [string[]]$Modules
            )
            foreach ($Module in $Modules) {
                Import-Module $Module -DisableNameChecking -Force
            }
        } -ArgumentList @($MyInvocation.MyCommand.Module.Path)
    }
    if (! $pwshCoreSession) { return }

    # Reconnect disconnected session
    if ($pwshCoreSession.State -eq 'Disconnected') {
        Connect-PSSession -Session $pwshCoreSession
    }

    # Invoke scriptblock in session
    Invoke-Command -Session $pwshCoreSession -ScriptBlock {
        Param(
            [string]$ScriptBlockString
        )
        $scriptBlock = [scriptBlock]::create($ScriptBlockString)
        & $scriptBlock @using:args
    } -ArgumentList $ScriptBlock.ToString()
}
Export-ModuleMember -Function Invoke-CommandInPwshCore