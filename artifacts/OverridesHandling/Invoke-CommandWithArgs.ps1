function Invoke-CommandWithArgs {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock,
        [object[]]$Arguments
    )
    $namedArgs = @{}
    $positionalArgs = @()
    $name = $null
    foreach ($arg in $Arguments) {
        if ($arg -like '-*') {
            if ($name) {
                $namedArgs[$name] = $true
            }
            $name = $arg.TrimStart('-').TrimEnd(':')
        } elseif ($name) {
            if ($namedArgs.ContainsKey($name)) {
                $namedArgs[$name] = @($namedArgs[$name], $arg)
            } else {
                $namedArgs[$name] = $arg    
            }
            $name = $null
        } else {
           $positionalArgs += $arg
        }
    }
    if ($name) {
        $namedArgs[$name] = $true
    }
    
    & $ScriptBlock
}
Export-ModuleMember -Function Invoke-CommandWithArgs