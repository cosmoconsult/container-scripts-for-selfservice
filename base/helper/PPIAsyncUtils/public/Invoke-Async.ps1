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

    $script:runspaces += [pscustomobject]@{
        RunspacePool = $RunspacePool;
        Runspace = $powershell;
        Result = $powershell.BeginInvoke()
    }

    $powershell
}
Export-ModuleMember -Function Invoke-Async