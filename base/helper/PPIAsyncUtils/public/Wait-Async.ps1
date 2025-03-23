function Wait-Async {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [RunspaceInfo]$RunspaceInfo,

        [int]$TimeoutSeconds = 0,
        
        [scriptblock]$ErrorScriptBlock       = { process { throw $PSItem } },
        [scriptblock]$WarningScriptBlock     = { process { Write-Warning $PSItem } },
        [scriptblock]$VerboseScriptBlock     = { process { Write-Verbose $PSItem } },
        [scriptblock]$DebugScriptBlock       = { process { Write-Debug $PSItem } },
        [scriptblock]$InformationScriptBlock = { process { Write-Host $PSItem } },
        [scriptblock]$OutputScriptBlock      = { process { $PSItem } }
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
            Start-Sleep -Milliseconds 500
        
            while ($RunspaceInfo.Output.Count -gt 0) {
                $outputs = $RunspaceInfo.Output.ReadAll()
                foreach($output in $outputs) {
                    try {
                        switch($output.GetType()) {
                            ( [System.Management.Automation.ErrorRecord] )       { $output | . $ErrorScriptBlock }
                            ( [System.Management.Automation.WarningRecord] )     { $output | . $WarningScriptBlock }
                            ( [System.Management.Automation.VerboseRecord] )     { $output | . $VerboseScriptBlock }
                            ( [System.Management.Automation.DebugRecord] )       { $output | . $DebugScriptBlock }
                            ( [System.Management.Automation.InformationRecord] ) { $output | . $InformationScriptBlock }
                            default                                              { $output | . $OutputScriptBlock }
                        }
                    } catch {
                        # Catch thrown errors to prevent the function from stopping
                        $message = $_ | Out-String
                        Write-Host $message -ForegroundColor Red
                        $exceptions += $_
                    }
                }
            }

            if ($RunspaceInfo.Handle.IsCompleted) {
                Write-Host "Runspace is completed with status: $($RunspaceInfo.Runspace.InvocationStateInfo.State)"
                $RunspaceInfo.Handled = $true
                $RunspaceInfo.Runspace.EndInvoke($RunspaceInfo.Handle) | Out-Null
            } elseif ($TimeoutSeconds -gt 0) { 
                $runtimeSeconds = (New-TimeSpan -Start $startTime).TotalSeconds
                if ($runtimeSeconds -gt $TimeoutSeconds) {
                    Write-Warning "Stopping Runspace - Timeout of ${TimeoutSeconds} seconds reached after ${runtimeSeconds} seconds"
                    $RunspaceInfo.Runspace.Stop()
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