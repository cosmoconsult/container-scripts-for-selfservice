function Open-RunspacePool {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $false)]
        [string[]]$Modules = @(),
        [Parameter(Mandatory = $false)]
        [int]$MinRunspaces = 1,
        [Parameter(Mandatory = $false)]
        [int]$MaxRunspaces = [Environment]::ProcessorCount
    )
    
    $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    if ($Modules) {
        $initialSessionState.ImportPSModule($Modules);
    }

    $runspacePool = [runspacefactory]::CreateRunspacePool($MinRunspaces, $MaxRunspaces, $initialSessionState, $Host);
    $runspacePool.Open();
    $runspacePool
}
Export-ModuleMember -Function Open-RunspacePool

