$Script:PwshCoreSessionConfigurations = @{}

function Get-PwshCoreSessionConfiguration() {
    Param(
        [string]$SessionConfigurationName = "PowerShell.7"
    )

    if ($Script:PwshCoreSessionConfigurations.ContainsKey($SessionConfigurationName)) {
        return $Script:PwshCoreSessionConfigurations[$SessionConfigurationName]
    }

    $sessionConfiguration = Get-PSSessionConfiguration -Name $SessionConfigurationName -ea SilentlyContinue

    if (! $sessionConfiguration) {
        Write-Warning "Remoting for powershell core not enabled... enabling"
        pwsh -Command 'Enable-PSRemoting -wa SilentlyContinue'
        $sessionConfiguration = Get-PSSessionConfiguration -Name $SessionConfigurationName
    }
    
    if (! $sessionConfiguration) { return }

    $Script:PwshCoreSessionConfigurations[$SessionConfigurationName] = $sessionConfiguration
    return $sessionConfiguration
}
Export-ModuleMember -Function Get-PwshCoreSessionConfiguration