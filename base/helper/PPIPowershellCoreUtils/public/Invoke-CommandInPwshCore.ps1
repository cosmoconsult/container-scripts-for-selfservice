
function Invoke-CommandInPwshCore() {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),

        [bool]$UseRemoteSession = $true
    )

    # Propagate caller's preferences across module boundary
    # (only when not explicitly bound via -ErrorAction etc.)
    @(
        @{ Variable = 'ErrorActionPreference'; Parameter = 'ErrorAction' },
        @{ Variable = 'WarningPreference'; Parameter = 'WarningAction' },
        @{ Variable = 'InformationPreference'; Parameter = 'InformationAction' },
        @{ Variable = 'VerbosePreference'; Parameter = 'Verbose' },
        @{ Variable = 'DebugPreference'; Parameter = 'Debug' }
    ) | Where-Object { -not $PSBoundParameters.ContainsKey($_.Parameter) } |
        ForEach-Object {
            Set-Variable -Name $_.Variable -Value $PSCmdlet.GetVariableValue($_.Variable)
        }

    if ($PSVersionTable.PSEdition -eq 'Core') {
        & $ScriptBlock @ArgumentList
        return
    }

    $invokeScriptBlock = {
        param(
            $ScriptBlock,
            $ArgumentList,
            $InformationPreference,
            $WarningPreference,
            $ErrorActionPreference,
            $VerbosePreference,
            $DebugPreference
        )

        try {
            & ( [ScriptBlock]::create($ScriptBlock) ) @ArgumentList *>&1
        } catch {
            Write-Error $_ *>&1
        }
    }

    $invokeArgs = @(
        $ScriptBlock,
        $ArgumentList,
        $(if ($InformationPreference -eq 'SilentlyContinue') { 'Continue' } else { $InformationPreference }),
        $(if ($WarningPreference -eq 'SilentlyContinue') { 'Continue' } else { $WarningPreference }),
        $(if ($ErrorActionPreference -eq 'SilentlyContinue') { 'Continue' } else { $ErrorActionPreference }),
        $VerbosePreference,
        $DebugPreference
    )

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
        Invoke-Command -Session $pwshCoreSession -ScriptBlock $invokeScriptBlock -ArgumentList $invokeArgs |
            ForEach-Object $processScriptBlock
    }
    else {
        # Invoke scriptblock in local pwsh process
        pwsh -NoProfile -c $invokeScriptBlock -Args $invokeArgs |
            ForEach-Object $processScriptBlock
    }
}
Export-ModuleMember -Function Invoke-CommandInPwshCore