function New-ArtifactsLogEntry {
    [CmdletBinding()]
    param (
        [DateTime]$Time = [DateTime]::Now,
        [string]$Message = "",
        [System.Object]$Data = $null,
        [ArtifactsLogEntrySeverity]$Severity = [ArtifactsLogEntrySeverity]::Info,
        [Nullable[ArtifactsLogEntrySuccess]]$Success = $null,
        [Nullable[ArtifactsLogEntryKind]]$Kind = $null
    )

    $entry = [ArtifactsLogEntry]::new()
    $entry.Time = $Time
    $entry.Message = $Message
    $entry.Data = $Data
    $entry.Severity = $Severity
    $entry.Success = $Success
    $entry.Kind = $Kind
    $entry
}
Export-ModuleMember -Function New-ArtifactsLogEntry
