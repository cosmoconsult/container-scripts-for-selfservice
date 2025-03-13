$global:cosmoRunspacePool = $null

# $env:cosmoAsyncRunspaces = "1"
[int]$maxRunspaces = 0
if ([int]::TryParse($env:cosmoAsyncRunspaces, [ref]$maxRunspaces) -and $maxRunspaces -gt 0) {
    Write-Host "##[group]Intialize Async Runspace Pool with ${maxRunspaces} runspaces"
    $global:cosmoRunspacePool = Open-RunspacePool -MaxRunspaces $maxRunspaces -Modules @((Get-Module -Name 'PPI*').Path)
    Write-Host "##[endgroup]"
}