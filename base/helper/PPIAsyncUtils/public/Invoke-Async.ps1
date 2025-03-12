function Invoke-Async {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [hashtable]$Parameters = @{},
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool
    )
    Write-Host "Invoke-Async - Begin"
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

    Write-Host "Invoke-Async - BeginInvoke"
    $result = $powershell.BeginInvoke();
    
    $runspace = [pscustomobject]@{
        RunspacePool = $RunspacePool;
        Runspace = $powershell;
        Result = $result
    }
    $runspace

    $script:runspaces += $runspace

    Write-Host "Invoke-Async - End"
}
Export-ModuleMember -Function Invoke-Async