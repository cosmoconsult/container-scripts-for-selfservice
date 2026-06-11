
function Invoke-CommandInPwshCore() {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),

        [bool]$UseRemoteSession = $true
    )

    if ($PSVersionTable.PSEdition -eq 'Core') {
        & $ScriptBlock @ArgumentList
        return
    }

    $invokeScriptBlock = {
        param($ScriptBlock, $ArgumentList)
        $InformationPreference = "Continue"
        $WarningPreference = "Continue"
        $VerbosePreference = "Continue"
        $ErrorActionPreference = "Continue"

        try {
            & ( [ScriptBlock]::create($ScriptBlock) ) @ArgumentList *>&1
        } catch {
            Write-Error $_ *>&1
        }
    }

    $processScriptBlock = {
        if ($_ -isnot [PSObject]) { $_ }
        elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.ErrorRecord')       { Write-Error $_ }
        elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.WarningRecord')     { Write-Warning $_ }
        elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.VerboseRecord')     { Write-Verbose $_ }
        elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.InformationRecord') {
            if ($_.Source -eq 'Write-Information') { Write-Information $_ }
            else                                   { Write-Host $_ }
        }
        else { $_ }
    }

    if ($UseRemoteSession) {
        $pwshCoreSession = Request-PwshCoreSession
        if (!$pwshCoreSession) { return }

        # Invoke scriptblock in session
        Invoke-Command -Session $pwshCoreSession -ScriptBlock $invokeScriptBlock -ArgumentList $ScriptBlock, $ArgumentList |
            ForEach-Object $processScriptBlock
    }
    else {
        # Invoke scriptblock in local pwsh process
        pwsh -NoProfile -c $invokeScriptBlock -Args $ScriptBlock, $ArgumentList |
            ForEach-Object $processScriptBlock
    }
}
Export-ModuleMember -Function Invoke-CommandInPwshCore