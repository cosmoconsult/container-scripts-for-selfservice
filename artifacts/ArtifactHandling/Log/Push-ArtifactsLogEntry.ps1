function Push-ArtifactsLogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline)]
        [ArtifactsLogEntry]$Entry
    )

    begin {
        $entries = @()
    }

    process {
        $entries += $Entry
    }
    
    end {
        $entries | Add-ArtifactsLog
    }
}
Export-ModuleMember -Function Push-ArtifactsLogEntry
