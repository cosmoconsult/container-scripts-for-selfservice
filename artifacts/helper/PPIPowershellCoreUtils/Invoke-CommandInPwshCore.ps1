
$script:PwshCoreSession = $null

function Invoke-CommandInPwshCore() {
    # Must be a simple function for correct splatting
    Param(
        [scriptblock]$ScriptBlock,
        [PSModuleInfo[]]$Modules,
    
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
    $commonCmdLetParams.Remove('Modules');

    if ($PSVersionTable.PSEdition -eq 'Core') {
        & $ScriptBlock @args @commonCmdLetParams
        return
    }

    $pwshCoreSessionConfigurationName = "PowerShell.7"
    $pwshCoreSessionName = "PwshCoreSession"

    if ($script:PwshCoreSession) {
        # Check known session
        if ($script:PwshCoreSession.State -notin @("Opened","Disconnected")) {
            $script:PwshCoreSession = $null
        }
    }
    if (! $script:PwshCoreSession) {
        # Find existing session (open or disconnected)
        $script:PwshCoreSession = Get-PSSession -Name $pwshCoreSessionName -ea silentlycontinue | Where-Object { $_.State -in @("Opened","Disconnected") } | Select-Object -Last 1
    }

    if (! $script:PwshCoreSession) {
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
        Write-Host ("Creating powershell core session (Version: {0})" -f $pwshCoreSessionConfiguration.PSVersion)
        $script:PwshCoreSession = New-PSSession -Name $pwshCoreSessionName -ConfigurationName $pwshCoreSessionConfiguration.Name -EnableNetworkAccess
    }
    if (! $script:PwshCoreSession) { return }

    # Reconnect disconnected session
    if ($script:PwshCoreSession.State -eq 'Disconnected') {
        Connect-PSSession -Session $script:PwshCoreSession
    }

    # Invoke scriptblock in session
    Invoke-Command -Session $script:PwshCoreSession -ScriptBlock {
        foreach ($module in $using:Modules) {
            Import-Module $module.Path -DisableNameChecking -Force
        }
        $scriptBlock = [scriptBlock]::create($using:ScriptBlock)
        & $scriptBlock @using:args
    } @commonCmdLetParams
}
Export-ModuleMember -Function Invoke-CommandInPwshCore