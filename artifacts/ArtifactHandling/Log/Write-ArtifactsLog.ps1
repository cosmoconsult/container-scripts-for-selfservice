function Write-ArtifactsLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [string]$message = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [ValidateSet("", "FOB", "App", "RIM", "DLL", "Font")]
        [string]$kind = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [ValidateSet("Info", "Warn", "Error", "Debug")]
        [string]$severity = "Info",
        [string]$suppressedWarnings = $env:SUPPRESSED_WARNINGS,
        [string]$suppressedErrors = $env:SUPPRESSED_ERRORS
    )

    process {
        if ("$message" -eq "") { return }

        $message = "$message".Trim()

        switch ($severity) {
            "Warn" {
                if (-not $suppressedWarningsPattern) {
                    $suppressedWarningsPattern = Get-DecodedSuppressionPattern -encodedPattern $suppressedWarnings
                }
                if (($suppressedWarningsPattern) -and ($message -match $suppressedWarningsPattern)) {
                    $severity = "Info"
                }
            }
            "Error" {
                if (-not $suppressedErrorsPattern) {
                    $suppressedErrorsPattern = Get-DecodedSuppressionPattern -encodedPattern $suppressedErrors
                }
                if (($suppressedErrorsPattern) -and ($message -match $suppressedErrorsPattern)) {
                    $severity = "Info"
                }
            }
        }

        $info = "$("$kind".PadRight(4))$("[$severity]".ToUpper().PadLeft(6))"

        if (! $message) { Write-Host "$info "; return }
        switch ($severity) {
            "Info"  { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" } } }
            "Warn"  { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" -f Yellow } } }
            "Error" { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" -f Red } } }
            "Debug" { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" -f DarkRed } } }
        }
    }
}
Export-ModuleMember -Function Write-ArtifactsLog

function Get-DecodedSuppressionPattern {
    param (
        [string]$encodedPattern
    )
    if (-not $encodedPattern) {
        return $null
    }
    try {
        return [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($encodedPattern))
    }
    catch {
        return $null
    }
}
