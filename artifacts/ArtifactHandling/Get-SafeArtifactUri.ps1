function Get-SafeArtifactUri {
    param (
        [string] $Uri
    )

    $safeUri = "$Uri" -replace '([?&]pat=)[^&#"]*', '$1***REDACTED***' # Redact PAT query parameters
    $safeUri = $safeUri -replace '("pat"\s*:\s*")[^"]*(")', '$1***REDACTED***$2' # Redact PAT values in artifact JSON
    $safeUri = $safeUri -replace '(/filebrowser/api/public/dl/)[^/?#"]+', '$1***REDACTED***' # Redact filebrowser download tokens
    return $safeUri
}

Export-ModuleMember -Function Get-SafeArtifactUri