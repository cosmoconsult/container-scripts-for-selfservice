function Get-SafeArtifactUri {
    param (
        [string] $Uri
    )

    return "$Uri" -replace '(?<prefix>[?&]pat=)[^&]*|(?<prefix>/filebrowser/api/public/dl/)[^/?#]+', '${prefix}***REDACTED***'
}

Export-ModuleMember -Function Get-SafeArtifactUri