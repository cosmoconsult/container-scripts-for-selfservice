
function Invoke-CommandInPwshCore() {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,

        [bool]$UseRemoteSession = $true
    )

    if ($PSVersionTable.PSEdition -eq 'Core') {
        & $ScriptBlock @ArgumentList
        return
    }

    if ($UseRemoteSession) {
        $pwshCoreSession = Request-PwshCoreSession
        if (!$pwshCoreSession) { return }

        # Invoke scriptblock in session
        Invoke-Command -Session $pwshCoreSession -ScriptBlock {
            $scriptBlock = [scriptblock]::create($using:ScriptBlock)
            & $scriptBlock @using:ArgumentList
        }
    }
    else {
        # Invoke scriptblock in local pwsh process
        pwsh -NoProfile -c {
            param($ScriptBlock, $ArgumentList)
            $InformationPreference = "Continue"
            $WarningPreference = "Continue"
            $VerbosePreference = "Continue"
            $ErrorActionPreference = "Continue"

            . ( [ScriptBlock]::create($ScriptBlock) ) @ArgumentList *>&1
        } -Args $ScriptBlock, $ArgumentList 2>&1 |
            ForEach-Object {
                if ($_ -isnot [PSObject]) { return $_ }
                elseif ($_ -is [System.Management.Automation.ErrorRecord])                                       { Write-Error $_ }
                elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.ErrorRecord')       { Write-Error $_ }
                elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.WarningRecord')     { Write-Warning $_ }
                elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.VerboseRecord')     { Write-Verbose $_ }
                elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.InformationRecord') { Write-Host $_ }
                else { return $_ }
            }
    }
}
Export-ModuleMember -Function Invoke-CommandInPwshCore