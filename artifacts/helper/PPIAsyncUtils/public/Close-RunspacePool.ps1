function Close-RunspacePool {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )
    $RunspacePool.Close();
    $RunspacePool.Dispose();
}
Export-ModuleMember -Function Close-RunspacePool

