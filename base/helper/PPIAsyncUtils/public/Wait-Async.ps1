function Wait-Async {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [RunspaceInfo]$RunspaceInfo,

        [int]$TimeoutSeconds = 0,

        [scriptblock]$ErrorScriptBlock       = { throw $_ },
        [scriptblock]$WarningScriptBlock     = { Write-Warning $_ },
        [scriptblock]$VerboseScriptBlock     = { Write-Verbose $_ },
        [scriptblock]$DebugScriptBlock       = { Write-Debug $_ },
        [scriptblock]$InformationScriptBlock = { Write-Host $_ },
        [scriptblock]$OutputScriptBlock      = { $_ }
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
                        switch($output.GetType()) {
                            ( [System.Management.Automation.ErrorRecord] )       { $scriptBlock = $ErrorScriptBlock }
                            ( [System.Management.Automation.WarningRecord] )     { $scriptBlock = $WarningScriptBlock }
                            ( [System.Management.Automation.VerboseRecord] )     { $scriptBlock = $VerboseScriptBlock }
                            ( [System.Management.Automation.DebugRecord] )       { $scriptBlock = $DebugScriptBlock }
                            ( [System.Management.Automation.InformationRecord] ) { $scriptBlock = $InformationScriptBlock }
                            default                                              { $scriptBlock = $OutputScriptBlock }
                        }
                        $output | ForEach-Object $scriptBlock
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