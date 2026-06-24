
function Invoke-CommandInPwshCore() {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),

        [bool]$UseRemoteSession = $true,

        [scriptblock]$ErrorScriptBlock       = { Write-Error $_ },
        [scriptblock]$WarningScriptBlock     = { Write-Warning $_ },
        [scriptblock]$VerboseScriptBlock     = { Write-Verbose $_ },
        [scriptblock]$DebugScriptBlock       = { Write-Debug $_ },
        [scriptblock]$InformationScriptBlock = { Write-Information $_ },
        [scriptblock]$HostScriptBlock        = { Write-Host $_ },
        [scriptblock]$OutputScriptBlock      = { $_ }
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
        $object = $_
        $objectScriptBlock = $OutputScriptBlock
        if ($object -is [PSObject]) {
            switch($object.PSObject.TypeNames) {
                { $_ -match '^(Deserialized\.)?System\.Management\.Automation\.VerboseRecord$' }     { $objectScriptBlock = $VerboseScriptBlock }
                { $_ -match '^(Deserialized\.)?System\.Management\.Automation\.DebugRecord$' }       { $objectScriptBlock = $DebugScriptBlock }
                { $_ -match '^(Deserialized\.)?System\.Management\.Automation\.ErrorRecord$' }       { $objectScriptBlock = $ErrorScriptBlock }
                { $_ -match '^(Deserialized\.)?System\.Management\.Automation\.WarningRecord$' }     { $objectScriptBlock = $WarningScriptBlock }
                { $_ -match '^(Deserialized\.)?System\.Management\.Automation\.InformationRecord$' } {
                    if ($object.Source -eq 'Write-Information') { $objectScriptBlock = $InformationScriptBlock }
                    else                                        { $objectScriptBlock = $HostScriptBlock }
                }
            }
        }
        $object | ForEach-Object $objectScriptBlock
    }



    if ($PSVersionTable.PSEdition -eq 'Core') {
        # Invoke scriptblock in current process
        Invoke-Command -ScriptBlock $invokeScriptBlock -ArgumentList $invokeArgs |
            ForEach-Object $processScriptBlock
    }
    elseif ($UseRemoteSession) {
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