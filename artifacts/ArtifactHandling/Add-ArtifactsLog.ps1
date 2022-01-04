function Add-ArtifactsLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$message  = "",        
        [Parameter(Mandatory=$false)]
        [string]$time     = (Get-Date -format "o"),
        [Parameter(Mandatory=$false)]
        [ValidateSet("", "FOB", "App", "RIM", "DLL", "Font")]
        [string]$kind = "",
        [Parameter(Mandatory=$false)]
        [ValidateSet("Info", "Warn", "Error", "Debug")]
        [string]$severity = "Info",
        [Parameter(Mandatory=$false)]
        [ValidateSet("", "success", "fail", "skip")]
        [string]$success = $null,
        [Parameter(Mandatory=$false)]
        [System.Object]$data = $null,
        [Parameter(Mandatory=$false)]
        [string]$artifactsLogFile = "C:/inetpub/wwwroot/http/artifacts.log.json",
        [switch]$lowerCase,
        [string]$suppressedWarnings = $env:SUPPRESSED_WARINGS,
        [string]$suppressedErrors = $env:SUPPRESSED_ERRORS
    )
    
    begin {
        $artifactsLog = Get-ArtifactsLog -artifactsLogFile $artifactsLogFile
    }
    
    process {
        if ("$message" -eq "") { return }

        $message = "$message".Trim()
        $logEntry = @{ "time"= $time; "type"=$kind; "message" = $message; "severity" = $severity; "success" = $success }

        if ($data) {
            $logEntry["data"] = ($data | ConvertTo-Json -Depth 1 -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue)
        }
        switch ($kind) {
            "FOB" { $artifactsLog.Log += @($logEntry); }
            "App" { $artifactsLog.Log += @($logEntry); }
            "RIM" { $artifactsLog.Log += @($logEntry); }
            Default { $artifactsLog.Log += @($logEntry); }
        }
        
        switch ($severity) {
            "Warn"  { 
                if (($suppressedWarnings) -and ($message -match $suppressedWarnings)) {
                    $severity = "Info"
                }
            }
            "Error" { 
                if (($suppressedErrors) -and ($message -match $suppressedErrors)) {
                    $severity = "Info"
                }
            }
        }

        $info   = "$("$kind".PadRight(4))$("[$severity]".ToUpper().PadLeft(6))"

        if (! $message) { Write-Host "$info "; return }
        switch ($severity) {
            "Info"  { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" } } }
            "Warn"  { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" -f Yellow } } }
            "Error" { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" -f Red } } }
            "Debug" { foreach ($m in "$message".Trim().Split([System.Environment]::NewLine)) { if ($m) { Write-Host "$info $($m.trim())" -f DarkRed } } }
        }
    }
    
    end {
        $artifactsLog | Set-ArtifactsLog -artifactsLogFile $artifactsLogFile -ErrorAction SilentlyContinue
    }
}
Export-ModuleMember -Function Add-ArtifactsLog