enum ArtifactsLogEntryKind {
    FOB
    App
    RIM
    DLL
    Font
}

enum ArtifactsLogEntrySeverity {
    Info
    Warn
    Error
    Debug
}

enum ArtifactsLogEntrySuccess {
    Success
    Fail
    Skip
}

class ArtifactsLogEntry {
    [DateTime] $Time
    [string] $Message
    [object] $Data
    [ArtifactsLogEntrySeverity] $Severity
    [Nullable[ArtifactsLogEntrySuccess]] $Success
    [Nullable[ArtifactsLogEntryKind]] $Kind
}