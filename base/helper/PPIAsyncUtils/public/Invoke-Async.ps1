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

    $inputData = New-Object System.Management.Automation.PSDataCollection[System.Object]
    $inputData.Complete();
    $inputData.Dispose();

    $outputData = New-Object System.Management.Automation.PSDataCollection[System.Object]

    $runspaceInfo = [RunspaceInfo]@{
        RunspacePool = $RunspacePool;
        Runspace     = $powershell;
        Output       = $outputData;
        Handle       = $powershell.BeginInvoke($inputData, $outputData)
    }

    $script:runspaces += $runspaceInfo
    return $runspaceInfo
}
Export-ModuleMember -Function Invoke-Async