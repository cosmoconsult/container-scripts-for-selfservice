function Invoke-CommandInPwshCore() {
    # Must be a simple function for correct splatting
    Param(
        [scriptblock]$ScriptBlock,
    
        [Alias('db')][switch]$Debug,
        [Alias('vb')][switch]$Verbose,
        [Alias('ea')][string]$ErrorAction,
        [Alias('ev')][string]$ErrorVariable,
        [Alias('infa')][string]$InformationAction,
        [Alias('iv')][string]$InformationVariable,
        [Alias('ob')][int]$OutBuffer,
        [Alias('ov')][string]$OutVariable,
        [Alias('pv')][string]$PipelineVariable,
        [Alias('pa')][string]$ProgressAction,
        [Alias('wa')][string]$WarningAction,
        [Alias('wv')][string]$WarningVariable
    )
    $commonCmdLetParams = [hashtable]$PSBoundParameters
    $commonCmdLetParams.Remove('ScriptBlock');

    if ($PSVersionTable.PSEdition -eq 'Core') {
        & $ScriptBlock @args @commonCmdLetParams
        return
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
            throw "Powershell core not found"
            return
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
    } -ArgumentList $ScriptBlock.ToString() @commonCmdLetParams
}
Export-ModuleMember -Function Invoke-CommandInPwshCore