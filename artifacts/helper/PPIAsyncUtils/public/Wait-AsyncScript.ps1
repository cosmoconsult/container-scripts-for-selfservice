function Wait-AsyncScript {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [powershell]$Runspace,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.IAsyncResult]$Result,
        
        [scriptblock]$ErrorScriptBlock = { if ($_.Exception.WasThrownFromThrowStatement) { throw $_ } else { Write-Error $_ } },
        [scriptblock]$WarningScriptBlock = { Write-Warning $_ },
        [scriptblock]$VerboseScriptBlock = { Write-Verbose $_ },
        [scriptblock]$DebugScriptBlock = { Write-Debug $_ },
        [scriptblock]$InformationScriptBlock = { Write-Host $_ },
        [scriptblock]$DefaultScriptBlock = { $_ }
    )

    process {
        $outputs = $Runspace.EndInvoke($Result);
        $Runspace.Dispose();

        $scriptBlock = $null;
        foreach ($output in $outputs) {
            switch($output.GetType()) {
                ( [System.Management.Automation.ErrorRecord] )       { $scriptBlock = $ErrorScriptBlock }
                ( [System.Management.Automation.WarningRecord] )     { $scriptBlock = $WarningScriptBlock }
                ( [System.Management.Automation.VerboseRecord] )     { $scriptBlock = $VerboseScriptBlock }
                ( [System.Management.Automation.DebugRecord] )       { $scriptBlock = $DebugScriptBlock }
                ( [System.Management.Automation.InformationRecord] ) { $scriptBlock = $InformationScriptBlock }
                default                                              { $scriptBlock = $DefaultScriptBlock }
            }
            $output | ForEach-Object ( [scriptblock]::create($scriptBlock) )
        }
    }
}
Export-ModuleMember -Function Wait-AsyncScript