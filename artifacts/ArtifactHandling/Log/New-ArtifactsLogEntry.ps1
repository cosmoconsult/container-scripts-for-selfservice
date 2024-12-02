function New-ArtifactsLogEntry {
    [CmdletBinding()]
    param (
        [DateTime]$Time = [DateTime]::Now,
        [string]$Message = "",
        [System.Object]$data = $null,
        [ArtifactsLogEntryKind]$Kind = [ArtifactsLogEntryKind]::Unknown,
        [ArtifactsLogEntrySeverity]$Severity = [ArtifactsLogEntrySeverity]::Info,
        [ArtifactsLogEntrySuccess]$Success = [ArtifactsLogEntrySuccess]::Unknown
    )

    $entry = [ArtifactsLogEntry]::new()
    $entry.Time = $Time
    $entry.Message = $Message
    $entry.Data = $data
    $entry.Kind = $Kind
    $entry.Severity = $Severity
    $entry.Success = $Success
    $entry
}
Export-ModuleMember -Function New-ArtifactsLogEntry
