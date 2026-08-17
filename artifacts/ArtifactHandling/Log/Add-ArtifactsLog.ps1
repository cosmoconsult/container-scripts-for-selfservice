function Add-ArtifactsLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [string]$message = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [string]$time = (Get-Date -format "o"),
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [ValidateSet("", "FOB", "App", "RIM", "DLL", "Font")]
        [string]$kind = "",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [ValidateSet("Info", "Warn", "Error", "Debug")]
        [string]$severity = "Info",
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [ValidateSet("", "success", "fail", "skip")]
        [string]$success = $null,
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName)]
        [System.Object]$data = $null,

        [Parameter(Mandatory = $false)]
        [string]$artifactsLogFile = "C:/inetpub/wwwroot/http/artifacts.log.json",
        [switch]$Quiet
    )

    begin {
        $artifactsLog = Get-ArtifactsLog -artifactsLogFile $artifactsLogFile
    }

    process {
        if ("$message" -eq "") { return }

        $message = "$message".Trim()

        $logEntry = @{ "time" = $time; "type" = $kind; "message" = $message; "severity" = $severity; "success" = $success }

        if ($data) {
            try {
                $logEntry["data"] = ($data | ConvertTo-Json -Depth 1 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
            }
            catch {
                # avoid aborting
            }
        }
        switch ($kind) {
            "FOB" { $artifactsLog.Log += @($logEntry); }
            "App" { $artifactsLog.Log += @($logEntry); }
            "RIM" { $artifactsLog.Log += @($logEntry); }
            Default { $artifactsLog.Log += @($logEntry); }
        }

        if (! $Quiet) {
            Write-ArtifactsLog -message $message -kind $kind -severity $severity
        }
    }

    end {
        $artifactsLog | Set-ArtifactsLog -artifactsLogFile $artifactsLogFile -ErrorAction SilentlyContinue
    }
}
Export-ModuleMember -Function Add-ArtifactsLog
