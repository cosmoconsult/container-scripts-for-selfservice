function Set-ArtifactsLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName=$true)]
        [System.Object]$artifactsLog,
        [Parameter(Mandatory=$false)]
        [string]$artifactsLogFile = "C:/inetpub/wwwroot/http/artifacts.log.json"
    )
    
    process {
        if ($artifactsLog) {
            $artifactsLog | ConvertTo-JSON -Depth 50 -ErrorAction SilentlyContinue | Set-Content -Path $artifactsLogFile -Force -ErrorAction SilentlyContinue
        }
    }
}
Export-ModuleMember -Function Set-ArtifactsLog