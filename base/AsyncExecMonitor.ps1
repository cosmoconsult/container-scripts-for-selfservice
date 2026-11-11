[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Payload
)

$ErrorActionPreference = 'Stop'
$request = $null
$worker = $null
$workerStartAttempted = $false
$workerStartFailed = $false
$startupAcknowledged = $false

function Write-StartupResult {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Result
    )

    $temporaryPath = "$Path.$PID.tmp"
    $json = ConvertTo-Json -InputObject $Result -Compress -Depth 10
    [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath, $Path)
}

try {
    $requestJson = [System.Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($Payload))
    $request = $requestJson | ConvertFrom-Json -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $request.ScriptPath -PathType Leaf)) {
        throw "Script '$($request.ScriptPath)' does not exist"
    }

    $powerShell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    $argumentList = @('-File', "`"$($request.ScriptPath)`"")
    foreach ($arg in @($request.RemainingArgs)) {
        $arg = [string]$arg
        if ($arg -match '[\s"]') {
            $argumentList += "`"$($arg -replace '"', '\"')`""
        }
        else {
            $argumentList += $arg
        }
    }

    $workerStartParameters = @{
        FilePath = $powerShell
        ArgumentList = $argumentList
        WorkingDirectory = $request.WorkingDirectory
        RedirectStandardOutput = $request.ScriptLog
        RedirectStandardError = $request.ScriptLogErr
        PassThru = $true
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $workerStartParameters.WindowStyle = 'Hidden'
    }
    $workerStartAttempted = $true
    try {
        $worker = Start-Process @workerStartParameters
    }
    catch {
        $workerStartFailed = $true
        throw
    }
    if (-not $worker) {
        throw 'PowerShell did not return a worker process handle'
    }

    Set-Content -LiteralPath $request.LockFile -Value 'InProgress' -ErrorAction Stop
    Write-StartupResult -Path $request.StartupResultFile -Result ([PSCustomObject]@{
        id = $request.Id
        state = 'Started'
        workerId = $worker.Id
    })
    $startupAcknowledged = $true
}
catch {
    $failureMessage = $_.Exception.Message
    $workerStopped = -not $workerStartAttempted -or $workerStartFailed
    if ($worker) {
        try {
            $worker.Refresh()
            if (-not $worker.HasExited) {
                Stop-Process -Id $worker.Id -Force -ErrorAction Stop
                $worker.WaitForExit()
                $worker.Refresh()
            }
            $workerStopped = $worker.HasExited
        }
        catch {
            $failureMessage = "$failureMessage; worker cleanup failed: $($_.Exception.Message)"
            try {
                $worker.Refresh()
                $workerStopped = $worker.HasExited
            }
            catch {
                $workerStopped = $false
            }
        }
    }

    if ($workerStopped -and $request -and $request.Id -and $request.StartupResultFile) {
        try {
            Set-Content -LiteralPath $request.LockFile -Value 'CompletedWithError' -ErrorAction Stop
            Write-StartupResult -Path $request.StartupResultFile -Result ([PSCustomObject]@{
                id = $request.Id
                state = 'NotStarted'
                stdErr = $failureMessage
            })
        }
        catch {
            [Console]::Error.WriteLine("Async monitor could not publish the confirmed startup failure for '$($request.Id)': $($_.Exception.Message)")
        }
    }
    else {
        [Console]::Error.WriteLine("Async monitor could not confirm that execution '$($request.Id)' has no worker: $failureMessage")
    }
    exit 1
}

try {
    $worker.WaitForExit()
    $finalState = if ($worker.ExitCode -ne 0) { 'CompletedWithError' } else { 'CompletedSuccessfully' }
    Set-Content -LiteralPath $request.LockFile -Value $finalState -ErrorAction Stop
}
catch {
    $message = "Async monitor failed while recording execution '$($request.Id)' status: $($_.Exception.Message)"
    [Console]::Error.WriteLine($message)
    if ($startupAcknowledged) {
        try {
            Set-Content -LiteralPath $request.LockFile -Value 'CompletedWithError' -ErrorAction Stop
        }
        catch {
            [Console]::Error.WriteLine("Could not update execution status file '$($request.LockFile)': $($_.Exception.Message)")
        }
    }
    exit 1
}
