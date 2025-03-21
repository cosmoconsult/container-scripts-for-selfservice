function Wait-Async {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [RunspaceInfo]$RunspaceInfo,
        
        [scriptblock]$ErrorScriptBlock       = { if ($_.Exception.WasThrownFromThrowStatement) { throw $_ } else { Write-Error $_ } },
        [scriptblock]$WarningScriptBlock     = { Write-Warning $_ },
        [scriptblock]$VerboseScriptBlock     = { Write-Verbose $_ },
        [scriptblock]$DebugScriptBlock       = { Write-Debug $_ },
        [scriptblock]$InformationScriptBlock = { Write-Host $_ },
        [scriptblock]$OutputScriptBlock      = { $_ }
    )

    process {
        if ($RunspaceInfo.Handled) {
            return
        }

        if (! $RunspaceInfo.Runspace) {
            return
        }

        if (! $RunspaceInfo.Handle) {
            return
        }

        $outputs = $RunspaceInfo.Runspace.EndInvoke($RunspaceInfo.Handle) | Where-Object { $_ -ne $null };
        $RunspaceInfo.Runspace.Dispose();
        $RunspaceInfo.Handled = $true;

        $scriptBlock = $null;
        foreach ($output in $outputs) {
            switch($output.GetType()) {
                ( [System.Management.Automation.ErrorRecord] )       { $scriptBlock = $ErrorScriptBlock }
                ( [System.Management.Automation.WarningRecord] )     { $scriptBlock = $WarningScriptBlock }
                ( [System.Management.Automation.VerboseRecord] )     { $scriptBlock = $VerboseScriptBlock }
                ( [System.Management.Automation.DebugRecord] )       { $scriptBlock = $DebugScriptBlock }
                ( [System.Management.Automation.InformationRecord] ) { $scriptBlock = $InformationScriptBlock }
                default                                              { $scriptBlock = $OutputScriptBlock }
            }
            $output | ForEach-Object $scriptBlock
        }
    }
}
Export-ModuleMember -Function Wait-Async