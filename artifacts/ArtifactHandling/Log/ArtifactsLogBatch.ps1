$script:artifactsLogBatchFlushThreshold = 50
$script:artifactsLogBatch = [System.Collections.Generic.List[ArtifactsLogEntry]]::new()

function Write-ArtifactsLogBatch {
    if ($script:artifactsLogBatch.Count -gt 0) {
        $script:artifactsLogBatch | Add-ArtifactsLog -Quiet
        $script:artifactsLogBatch.Clear()
    }
}

function Push-ArtifactsLogBatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ArtifactsLogEntry]$Entry
    )

    process {
        $script:artifactsLogBatch.Add($Entry)
        if ($script:artifactsLogBatch.Count -ge $script:artifactsLogBatchFlushThreshold) {
            Write-ArtifactsLogBatch
        }
    }
}
