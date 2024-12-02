function Push-ArtifactsLogEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [ArtifactsLogEntry]$Entry
    )
    
    Add-ArtifactsLog `
        -message $Entry.Message `
        -time ( Get-Date $Entry.Time -format 'o' ) `
        -kind $Entry.Kind `
        -severity $Entry.Severity `
        -success $Entry.Success `
        -data $Entry.Data
}
Export-ModuleMember -Function Push-ArtifactsLogEntry
