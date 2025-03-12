$global:cosmoRunspacePool = $null
$global:cosmoRunspaces = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[pscustomobject]]]::new()

if ($env:cosmoAsyncRunspaces -is [int] -and $env:cosmoAsyncRunspaces -gt 0) {
    Write-Host "##[group]Intialize Async Runspace Pool with ${env:cosmoAsyncRunspaces} runspaces"
    $global:cosmoRunspacePool = Open-RunspacePool -MaxRunspaces $env:cosmoAsyncRunspaces -Modules @((Get-Module -Name 'PPI*').Path)
    Write-Host "##[endgroup]"
}