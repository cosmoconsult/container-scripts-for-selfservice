# run any PS script async in the background and hold a lock file while it's running. Pipe all output to a log file and return the current status (started, running, finished, failed)
[CmdletBinding()]
param (
    [Parameter(Mandatory = $false, Position = 0)]
    [string]
    $ScriptPath,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]
    $Id,

    [Parameter(Mandatory = $false, Position = 2)]
    [switch]
    $OnlyGetStatus
)

# create lock file to prevent multiple executions with a name based on the script name
$lockFile = "$Id.lock"  # holds status
$scriptLog = "$Id.log"
$scriptLogErr = "$Id.err.log"

if ($OnlyGetStatus -and (-not (Test-Path $lockFile))) {
    return [PSCustomObject]@{
        id = $Id
        state = "NotStarted"
    } | ConvertTo-Json
}

# create lock file if it doesn't exist, else throw an error
if (-not (New-Item -Type File -Path $lockFile -ErrorAction SilentlyContinue)) {
    if (Test-Path $scriptLog) {
        $stdOut = (Get-Content -Path $scriptLog -Raw).psobject.BaseObject
    }

    if (Test-Path $scriptLogErr) {
        $stdErr = (Get-Content -Path $scriptLogErr -Raw).psobject.BaseObject
    }

    return [PSCustomObject]@{
        id = $Id
        state = (Get-Content -Path $lockFile -Raw).psobject.BaseObject
        stdOut = $stdOut
        stdErr = $stdErr
    } | ConvertTo-Json
}

try {
    Remove-Item -Path $scriptLog -Force -ErrorAction SilentlyContinue
    Remove-Item -Path $scriptLogErr -Force -ErrorAction SilentlyContinue
    Set-Content -Path $lockFile -Value "Started"

    $ps = "powershell"
    if ($PSVersionTable.PSEdition -eq "Core") {
        $ps = "pwsh"
    }

    # run script in the background and redirect all output to a log file, store exit code
    $p = Start-Process -FilePath $ps -ArgumentList "-File $ScriptPath" -NoNewWindow -RedirectStandardOutput $scriptLog -RedirectStandardError $scriptLogErr -PassThru
    $handle = $p.Handle  # cache the handle

    Set-Content -Path $lockFile -Value "InProgress"

    $p.WaitForExit();
    if ($p.ExitCode -ne 0) {
        Set-Content -Path $lockFile -Value "CompletedWithError"
    }
    else {
        Set-Content -Path $lockFile -Value "CompletedSuccessfully"
    }
}
catch {
    # remove lock file when something goes wrong
    Remove-Item -Path $lockFile -Force -ErrorAction SilentlyContinue
}

