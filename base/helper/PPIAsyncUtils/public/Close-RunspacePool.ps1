function Close-RunspacePool {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )
    
    # wait for all running runspaces of runspace pool
    $script:runspaces | 
        Where-Object { $_.RunspacePool -eq $RunspacePool } |
        Where-Object { $_.Runspace.InvocationStateInfo.State -eq 'Running' } |
        ForEach-Object {
            Wait-Async -Runspace $_.Runspace -Result $_.Result | Out-Null
        }
    
    $RunspacePool.Close();
    $RunspacePool.Dispose();
}
Export-ModuleMember -Function Close-RunspacePool

