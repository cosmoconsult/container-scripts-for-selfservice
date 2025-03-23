function Invoke-Async {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )
    $powershell = [powershell]::Create();
    $powershell.RunspacePool = $RunspacePool;

    $powershell.AddScript({
        [cmdletbinding()]
        param(
            [scriptblock]$ScriptBlock,
            [hashtable]$Parameters = @{}
        );
        try {
            . ( [scriptblock]::Create($ScriptBlock) ) @Parameters *>&1
        } catch {
            $_
        }
    }) | Out-Null;
    $powershell.AddParameter("ScriptBlock", $ScriptBlock) | Out-Null;
    $powershell.AddParameter("Parameters", $Parameters.Clone()) | Out-Null;

    $input = New-Object System.Management.Automation.PSDataCollection[System.Object]
    $input.Complete();
    $input.Dispose();

    $output = New-Object System.Management.Automation.PSDataCollection[System.Object]

    $runspaceInfo = [RunspaceInfo]@{
        RunspacePool = $RunspacePool;
        Runspace     = $powershell;
        Output       = $output;
        Handle       = $powershell.BeginInvoke($input, $output)
    }

    $script:runspaces += $runspaceInfo
    return $runspaceInfo
}
Export-ModuleMember -Function Invoke-Async