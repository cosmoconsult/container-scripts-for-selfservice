if (! $global:alpacaRunspacePool) {
    return
}

Write-Host "##[group]Close Async Runspace Pool"
Close-RunspacePool -RunspacePool $global:alpacaRunspacePool
Write-Host "##[endgroup]"