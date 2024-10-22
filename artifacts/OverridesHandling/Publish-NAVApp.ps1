function Publish-NAVApp() {
    [CmdletBinding(DefaultParameterSetName = 'Default')]
    Param(
        [Parameter(ValueFromRemainingArguments = $true)]
        $RemainingArgs
    )

    $scriptBlock = {
        $moduleNames = @('Microsoft.BusinessCentral.Apps.Management', 'Microsoft.Dynamics.Nav.Apps.Management', 'Microsoft.Dynamics.Nav.Management')
        $module = Get-Module -Name $moduleNames | Sort-Object { $moduleNames.IndexOf($_.Name) } | Select-Object -First 1
        if (! $module) {
            c:\run\prompt.ps1 -silent
            $module = Get-Module -Name $moduleNames | Sort-Object { $moduleNames.IndexOf($_.Name) } | Select-Object -First 1
        }
        if (! $module) {
            throw ("Powershell modules not found: {0}" -f ($moduleNames -join ', '))
        }
        & "${module.Name}\Publish-NAVApp" @namedArgs @positionalArgs
    }

    $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
    if (Test-Path "$serviceTierFolder\Admin") {
        Invoke-CommandWithArgsInPwshCore -ScriptBlock $scriptBlock -ArgumentList $RemainingArgs    
    } else {
        Invoke-CommandWithArgs -ScriptBlock $scriptBlock -ArgumentList $RemainingArgs
    }
}
Export-ModuleMember -Function Publish-NAVApp