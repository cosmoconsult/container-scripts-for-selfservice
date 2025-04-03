class RunspaceInfo {
    [System.Management.Automation.Runspaces.RunspacePool] $RunspacePool
    [Powershell] $Runspace
    [System.Management.Automation.PSDataCollection[System.Object]]$Output
    [IAsyncResult] $Handle
    [Bool] $Handled
}