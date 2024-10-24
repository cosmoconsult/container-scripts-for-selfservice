$script:PwshCoreSession = $null

function Request-PwshCoreSession() {
    $sessionConfigurationName = "PowerShell.7"
    $sessionName = "PwshCoreSession"

    if ($script:PwshCoreSession) {
        # Check known session
        if ($script:PwshCoreSession.State -notin @("Opened","Disconnected")) {
            $script:PwshCoreSession = $null
        }
    }
    if (! $script:PwshCoreSession) {
        # Find existing session (open or disconnected)
        $script:PwshCoreSession = Get-PSSession -Name $sessionName -ea silentlycontinue | Where-Object { $_.State -in @("Opened","Disconnected") } | Select-Object -Last 1
    }

    if (! $script:PwshCoreSession) {
        # Check powershell core exists
        if (! (Get-Command pwsh -ea SilentlyContinue)) {
            throw "Powershell core not found"
            return
        }

        # Find or setup session configuration
        $sessionConfiguration = Get-PSSessionConfiguration -Force | Where-Object { $_.Name -eq $sessionConfigurationName } | Select-Object -First 1
        if (! $sessionConfiguration) {
            Write-Warning "Remoting for powershell core not enabled... enabling"
            pwsh -Command 'Enable-PSRemoting -wa SilentlyContinue'
            $sessionConfiguration = Get-PSSessionConfiguration -Name $sessionConfigurationName
        }
        if (! $sessionConfiguration) { return }

        # Create session
        Write-Host ("Creating powershell core session (Version: {0})" -f $sessionConfiguration.PSVersion)
        $script:PwshCoreSession = New-PSSession -Name $sessionName -ConfigurationName $sessionConfiguration.Name -EnableNetworkAccess
    }
    if (! $script:PwshCoreSession) { return }

    # Reconnect disconnected session
    if ($script:PwshCoreSession.State -eq 'Disconnected') {
        Write-Host "Reopen powershell core session"
        Connect-PSSession -Session $script:PwshCoreSession
    }

    if ($script:PwshCoreSession.State -ne 'Opened') {
        throw "Powershell core session not open"
        return
    }

    return $script:PwshCoreSession
}
Export-ModuleMember -Function Request-PwshCoreSession