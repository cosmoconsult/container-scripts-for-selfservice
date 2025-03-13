function Wait-Async {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [powershell]$Runspace,
        
        [scriptblock]$ErrorScriptBlock       = { if ($_.Exception.WasThrownFromThrowStatement) { throw $_ } else { Write-Error $_ } },
        [scriptblock]$WarningScriptBlock     = { Write-Warning $_ },
        [scriptblock]$VerboseScriptBlock     = { Write-Verbose $_ },
        [scriptblock]$DebugScriptBlock       = { Write-Debug $_ },
        [scriptblock]$InformationScriptBlock = { Write-Host $_ },
        [scriptblock]$OutputScriptBlock      = { $_ }
    )

    process {
        $script:runspaces | 
            Where-Object { $_.Runspace -eq $Runspace } | 
            ForEach-Object {
                $outputs = $_.Runspace.EndInvoke($_.Result);
                $_.Runspace.Dispose();

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

        $script:runspaces = @( $script:runspaces | Where-Object { $_.Runspace -ne $Runspace } )
    }
}
Export-ModuleMember -Function Wait-Async