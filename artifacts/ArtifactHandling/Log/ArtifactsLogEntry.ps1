enum ArtifactsLogEntryKind {
    Unknown
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
    Unknown
    Success
    Fail
    Skip
}

class ArtifactsLogEntry {
    [DateTime] $Time
    [string] $Message
    [object] $Data
    [ArtifactsLogEntryKind] $Kind
    [ArtifactsLogEntrySeverity] $Severity
    [ArtifactsLogEntrySuccess] $Success
}