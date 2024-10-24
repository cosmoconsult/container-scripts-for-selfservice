
function Invoke-CommandInPwshCore() {
    # Must be a simple function for correct splatting
    Param(
        [scriptblock]$ScriptBlock
    )
    if ($PSVersionTable.PSEdition -eq 'Core') {
        & $ScriptBlock @args @commonCmdLetParams
        return
    }

    $pwshCoreSession = Request-PwshCoreSession
    if (!$pwshCoreSession) { return }

    # Invoke scriptblock in session
    Invoke-Command -Session $pwshCoreSession -ScriptBlock {
        $scriptBlock = [scriptBlock]::create($using:ScriptBlock)
        & $scriptBlock @using:args
    }
}
Export-ModuleMember -Function Invoke-CommandInPwshCore