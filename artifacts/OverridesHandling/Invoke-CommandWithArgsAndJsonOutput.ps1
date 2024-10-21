function Invoke-CommandWithArgsAndJsonOutput{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [object[]]$Arguments
    )
    ($out = Invoke-CommandWithArgs -ScriptBlock $ScriptBlock -Arguments $Arguments -ea Continue -InformationVariable info -WarningVariable warn -ErrorVariable err) *>$null
    @{
        info = @(if ($info) { $info | ForEach-Object { $_.MessageData.Message.ToString() } })
        warn = @(if ($warn) { $warn | ForEach-Object { $_.Message.ToString() } })
        err  = @(if ($err) { $err | ForEach-Object { $_.Exception.Message.ToString() } })
        out = @(if ($out) { $out })
    } | ConvertTo-Json -Depth 100 -ea SilentlyContinue -wa SilentlyContinue -InformationAction SilentlyContinue
    if ($err) { exit 1 }
}
Export-ModuleMember -Function Invoke-CommandWithArgsAndJsonOutput