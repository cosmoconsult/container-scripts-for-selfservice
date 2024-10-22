function Publish-NAVApp() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$RemainingArgs
    )
    
    Invoke-CommandWithArgsInPwshCore -ScriptBlock {
        $moduleNames = @('Microsoft.BusinessCentral.Apps.Management', 'Microsoft.Dynamics.Nav.Apps.Management', 'Microsoft.Dynamics.Nav.Management')
        $module = Get-Module -Name $moduleNames | Sort-Object { $moduleNames.IndexOf($_.Name) } | Select-Object -First 1
        if (! $module) {
            Push-Location
            c:\run\prompt.ps1 -silent
            Pop-Location
            $module = Get-Module -Name $moduleNames | Sort-Object { $moduleNames.IndexOf($_.Name) } | Select-Object -First 1
        }
        if (! $module) {
            throw ("Powershell modules not found: {0}" -f ($moduleNames -join ', '))
        }
        & "${module.Name}\Publish-NAVApp" @args
    } -ArgumentList $RemainingArgs
}
Export-ModuleMember -Function Publish-NAVApp