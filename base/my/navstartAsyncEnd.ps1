if (! $global:cosmoRunspacePool) {
    return
}

Write-Host "##[group]Close Async Runspace Pool"
Close-RunspacePool -RunspacePool $global:cosmoRunspacePool
Write-Host "##[endgroup]"