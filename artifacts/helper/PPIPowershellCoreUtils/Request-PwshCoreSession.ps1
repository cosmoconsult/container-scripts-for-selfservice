$Script:PwshCoreSessions = @{}

function Request-PwshCoreSession() {
    Param(
        [string]$SessionConfigurationName = "PowerShell.7",
        [string]$SessionName = "PwshCoreSession"
    )

    if ($Script:PwshCoreSessions.ContainsKey($SessionName)) {
        $session = $Script:PwshCoreSessions[$SessionName]
        $Script:PwshCoreSessions[$SessionName] = $null
    }

    if ($session) {
        # Check known session
        if ($session.State -notin @("Opened","Disconnected")) {
            $session = $null
        }
    }
    if (! $session) {
        # Find existing session (open or disconnected)
        $session = Get-PSSession -Name $SessionName -ea silentlycontinue | Where-Object { $_.State -in @("Opened","Disconnected") } | Select-Object -Last 1
    }

    if (! $session) {
        # Check powershell core exists
        if (! (Get-Command pwsh -ea SilentlyContinue)) {
            throw "Powershell core not found"
            return
        }

        # Find or setup session configuration
        $sessionConfiguration = Get-PSSessionConfiguration -Force | Where-Object { $_.Name -eq $SessionConfigurationName } | Select-Object -First 1
        if (! $sessionConfiguration) {
            Write-Warning "Remoting for powershell core not enabled... enabling"
            pwsh -Command 'Enable-PSRemoting -wa SilentlyContinue'
            $sessionConfiguration = Get-PSSessionConfiguration -Name $SessionConfigurationName
        }
        if (! $sessionConfiguration) { return }

        # Create session
        Write-Host ("Creating powershell core session (Version: {0})" -f $sessionConfiguration.PSVersion)
        $session = New-PSSession -Name $SessionName -ConfigurationName $sessionConfiguration.Name -EnableNetworkAccess
    }
    if (! $session) { return }

    # Reconnect disconnected session
    if ($session.State -eq 'Disconnected') {
        Write-Host "Reopen powershell core session"
        Connect-PSSession -Session $session
    }

    if ($session.State -ne 'Opened') {
        throw "Powershell core session not open"
        return
    }

    $Script:PwshCoreSessions[$SessionName] = $session
    return $session
}
Export-ModuleMember -Function Request-PwshCoreSession