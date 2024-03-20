# run any PS script async in the background and hold a lock file while it's running. Pipe all output to a log file and return the current status (started, running, finished, failed)
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, Position = 0)]
    [string]
    $ScriptPath,

    [Parameter(Mandatory = $false, Position = 1)]
    [switch]
    $OnlyGetStatus
)

# create lock file to prevent multiple executions with a name based on the script name
$lockFile = "$ScriptPath.lock"  # holds status
$scriptLog = "$ScriptPath.log"
$scriptLogErr = "$ScriptPath.err.log"

# create lock file if it doesn't exist, else throw an error
if (-not (New-Item -Type File -Path $lockFile -ErrorAction SilentlyContinue)) {
    $status = Get-Content -Path $lockFile;

    if ($status.Contains("finished")) {
        Remove-Item -Path $lockFile -Force
    }

    if (Test-Path $scriptLog) {
        $status += "`n`n"
        $status += Get-Content -Path $scriptLog -Raw
    }

    if (Test-Path $scriptLogErr) {
        $status += "`n`n"
        $status += Get-Content -Path $scriptLogErr -Raw
    }

    return $status
}

if ($OnlyGetStatus) {
    return "not started"
}

try {
    Remove-Item -Path $scriptLog -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $scriptLogErr -Force -ErrorAction SilentlyContinue
    Set-Content -Path $lockFile -Value "started"

    $ps = "powershell"
    if ($PSVersionTable.PSEdition -eq "Core") {
        $ps = "pwsh"
    }

    # run script in the background and redirect all output to a log file, store exit code
    $p = Start-Process -FilePath $ps -ArgumentList "-File $ScriptPath" -NoNewWindow -RedirectStandardOutput $scriptLog -RedirectStandardError $scriptLogErr -PassThru
    $handle = $p.Handle  # cache the handle

    Set-Content -Path $lockFile -Value "running"

    $p.WaitForExit();
    Set-Content -Path $lockFile -Value "finished (exit code: $($p.ExitCode))"
}
catch {
    # remove lock file when something goes wrong
    Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
}

