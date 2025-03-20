class RunspaceInfo {
    [System.Management.Automation.Runspaces.RunspacePool] $RunspacePool
    [Powershell] $Runspace
    [IAsyncResult] $Handle
    [Bool] $Handled
}