function Get-ArtifactJson {
    [CmdletBinding()]
    param (
        [string]$path,
        [string]$filter = "artifact.json",
        [int]$maxDepth = 2
    )    
    process {
        try {
            if (! $path) {
                Write-Host "`$path is Empty -> SKIP search for artifact.json" -f Yellow  | Out-String
                return;
            }
            $current = (Get-Item -Path $path -ErrorAction SilentlyContinue)
            if (! $current) { return }
            if (! $current.PSIsContainer) { $current = $current.Directory }
            do {            
                $items = (Get-ChildItem -File -LiteralPath $current.FullName -Filter $filter -Recurse -Depth $maxDepth -ErrorAction SilentlyContinue)
                $artifactJson = ($items | Select-Object -First 1 | Get-Content -ErrorAction SilentlyContinue)
                $current = $current.Parent
            } until ($artifactJson -or ! $current)
            if ($artifactJson) {
                return ($artifactJson | ConvertFrom-Json -ErrorAction SilentlyContinue)
            }
        }
        catch {
            Write-Host "Get Artifact Json for $path Error: $($_.Exception.Message)" -f Red  | Out-String
        }        
    }
}
Export-ModuleMember -Function Get-ArtifactJson
