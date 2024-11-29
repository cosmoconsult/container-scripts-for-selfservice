function Open-RunspacePool {
    [cmdletbinding()]
    Param()
    
    $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    $initialSessionState.ImportPSModule(@((Get-Module).Path));

    $runspacePool = [runspacefactory]::CreateRunspacePool(1, [Environment]::ProcessorCount, $initialSessionState, $Host);
    $runspacePool.Open();
    $runspacePool
}
Export-ModuleMember -Function Open-RunspacePool

