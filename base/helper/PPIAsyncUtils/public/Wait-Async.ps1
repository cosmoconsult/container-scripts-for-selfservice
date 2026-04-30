function Wait-Async {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [RunspaceInfo]$RunspaceInfo,

        [int]$TimeoutSeconds = 0,

        [scriptblock]$ErrorScriptBlock       = { throw $args[0] },
        [scriptblock]$WarningScriptBlock     = { Write-Warning $args[0] },
        [scriptblock]$VerboseScriptBlock     = { Write-Verbose $args[0] },
        [scriptblock]$DebugScriptBlock       = { Write-Debug $args[0] },
        [scriptblock]$InformationScriptBlock = { Write-Host $args[0] },
        [scriptblock]$OutputScriptBlock      = { $args[0] }
    )

    begin {
        $exceptions = @()
    }

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

        $startTime = Get-Date

        Write-Host "Waiting for Runspace"

        while (! $RunspaceInfo.Handled) {
            while ($RunspaceInfo.Output.Count -gt 0) {
                $outputs = $RunspaceInfo.Output.ReadAll()
                foreach($output in $outputs) {
                    try {
                        $scriptBlock = $null
                        # switch($output.GetType()) {
                        #     ( [System.Management.Automation.ErrorRecord] )       { $scriptBlock = $ErrorScriptBlock }
                        #     ( [System.Management.Automation.WarningRecord] )     { $scriptBlock = $WarningScriptBlock }
                        #     ( [System.Management.Automation.VerboseRecord] )     { $scriptBlock = $VerboseScriptBlock }
                        #     ( [System.Management.Automation.DebugRecord] )       { $scriptBlock = $DebugScriptBlock }
                        #     ( [System.Management.Automation.InformationRecord] ) { $scriptBlock = $InformationScriptBlock }
                        #     default                                              { $scriptBlock = $OutputScriptBlock }
                        # }
                        # $scriptBlock.Invoke($output)
                        switch($output.GetType()) {
                            ( [System.Management.Automation.ErrorRecord] )       { throw $output }
                            ( [System.Management.Automation.WarningRecord] )     { Write-Warning $output }
                            ( [System.Management.Automation.VerboseRecord] )     { Write-Verbose $output }
                            ( [System.Management.Automation.DebugRecord] )       { Write-Debug $output }
                            ( [System.Management.Automation.InformationRecord] ) { Write-Host $output }
                            default                                              { $output }
                        }
                    } catch {
                        # Catch thrown errors to prevent the function from stopping
                        $message = Out-String -InputObject $_
                        Write-Host $message -ForegroundColor Red
                        $exceptions += $_
                    }
                }
            }

            if ($RunspaceInfo.Handle.IsCompleted) {
                Write-Host "Runspace is completed with status: $($RunspaceInfo.Runspace.InvocationStateInfo.State)"
                $RunspaceInfo.Handled = $true
                $RunspaceInfo.Runspace.EndInvoke($RunspaceInfo.Handle) | Out-Null
            } else {
                if ($TimeoutSeconds -gt 0 -and $TimeoutSeconds -lt (New-TimeSpan -Start $startTime).TotalSeconds) {
                    Write-Warning "Stopping Runspace - Timeout of ${TimeoutSeconds} seconds reached"
                    $RunspaceInfo.Runspace.Stop()
                } else {
                    Write-Host "Waiting for new output from Runspace..."
                    Start-Sleep -Milliseconds 250
                }
            }
        }

        $RunspaceInfo.Runspace.Dispose();
        $RunspaceInfo.Output.Complete();
        $RunspaceInfo.Output.Dispose();
    }

    end {
        if ($exceptions) {
            Write-Warning "Runspaces completed with $($exceptions.Count) exceptions"
            $message = $exceptions |
                ForEach-Object -Begin { $index = 0 } -Process { $index ++; "Exception #${index}:"; $_ } |
                Out-String
            $errorRecord = New-Object System.Management.Automation.ErrorRecord( $message, "Wait-Async Exceptions", "InvalidResult", $null )
            throw $errorRecord
        }
    }
}
Export-ModuleMember -Function Wait-Async