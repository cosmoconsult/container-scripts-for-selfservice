if (! $global:runspacePool) {
    return
}

Write-Host "##[group]Close Async Runspace Pool"
Close-RunspacePool -RunspacePool $global:runspacePool
Write-Host "##[endgroup]"