function Close-RunspacePool {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )
    
    # wait for all running runspaces of runspace pool
    $script:runspaces | 
        Where-Object { $_.RunspacePool -eq $RunspacePool } |
        ForEach-Object { $_.Runspace } |
        Wait-Async | Out-Null
    
    $RunspacePool.Close();
    $RunspacePool.Dispose();
}
Export-ModuleMember -Function Close-RunspacePool

