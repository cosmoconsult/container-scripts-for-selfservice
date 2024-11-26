function Invoke-AsyncScript {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )
    $runspace = [powershell]::Create();
    $runspace.RunspacePool = $RunspacePool;

    $runspace.AddScript({
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
    $runspace.AddParameter("ScriptBlock", $ScriptBlock) | Out-Null;
    $runspace.AddParameter("Parameters", $Parameters) | Out-Null;

    $result = $runspace.BeginInvoke();
    
    [pscustomobject]@{
        Runspace = $runspace;
        Result = $result
    }
}
Export-ModuleMember -Function Invoke-AsyncScript