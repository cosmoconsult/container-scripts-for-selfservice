# Start a script asynchronously and return after a detached monitor owns its status and cleanup.
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
    $OnlyGetStatus,

    [Parameter(Mandatory = $false, ValueFromRemainingArguments = $true)]
    $RemainingArgs
)

$ErrorActionPreference = 'Stop'
$workingDirectory = (Get-Location).Path
$lockFile = Join-Path $workingDirectory "$Id.lock"
$scriptLog = Join-Path $workingDirectory "$Id.log"
$scriptLogErr = Join-Path $workingDirectory "$Id.err.log"
$startupResultFile = Join-Path $workingDirectory "$Id.startup.json"
$monitorLog = Join-Path $workingDirectory "$Id.monitor.log"
$monitorLogErr = Join-Path $workingDirectory "$Id.monitor.err.log"

function Write-JsonLine {
    param ([Parameter(Mandatory)]$Value)

    [Console]::Out.WriteLine(($Value | ConvertTo-Json -Compress -Depth 10))
}

function Exit-NotStarted {
    param (
        [Parameter(Mandatory)]
        [string]$Message,
        [switch]$RemoveLock
    )

    if ($RemoveLock -and (Test-Path -LiteralPath $lockFile)) {
        Remove-Item -LiteralPath $lockFile -Force -ErrorAction SilentlyContinue
    }
    [Console]::Error.WriteLine($Message)
    Write-JsonLine ([PSCustomObject]@{
        id = $Id
        state = 'NotStarted'
        stdErr = $Message
    })
    exit 1
}

function Get-ExecutionStatus {
    $state = [string](Get-Content -LiteralPath $lockFile -Raw)
    if ([string]::IsNullOrWhiteSpace($state)) {
        $state = 'InProgress'
    }
    $status = [PSCustomObject]@{
        id = $Id
        state = $state.Trim()
    }
    if (Test-Path -LiteralPath $scriptLog) {
        $status | Add-Member -NotePropertyName stdOut -NotePropertyValue (Get-Content -LiteralPath $scriptLog -Raw)
    }
    if (Test-Path -LiteralPath $scriptLogErr) {
        $status | Add-Member -NotePropertyName stdErr -NotePropertyValue (Get-Content -LiteralPath $scriptLogErr -Raw)
    }
    return ($status | ConvertTo-Json -Compress -Depth 10)
}

$parsedId = [Guid]::Empty
if (-not [Guid]::TryParse($Id, [ref]$parsedId)) {
    Exit-NotStarted "Execution id '$Id' is not a valid GUID"
}

if ($OnlyGetStatus -and -not (Test-Path -LiteralPath $lockFile)) {
    Write-JsonLine ([PSCustomObject]@{
        id = $Id
        state = 'NotStarted'
    })
    return
}

if ($OnlyGetStatus) {
    [Console]::Out.WriteLine((Get-ExecutionStatus))
    return
}

try {
    $null = New-Item -Type File -Path $lockFile -Value 'InProgress' -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine("Could not reserve execution id '$Id'; it may already exist: $($_.Exception.Message)")
    exit 1
}

try {
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        throw 'ScriptPath is required when starting an execution'
    }
    $ScriptPath = [System.IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw "Script '$ScriptPath' does not exist"
    }
    $monitorScriptPath = Join-Path $PSScriptRoot 'AsyncExecMonitor.ps1'
    if (-not (Test-Path -LiteralPath $monitorScriptPath -PathType Leaf)) {
        throw "Async monitor '$monitorScriptPath' does not exist"
    }

    foreach ($path in @($scriptLog, $scriptLogErr, $startupResultFile, $monitorLog, $monitorLogErr)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
        }
    }

    $request = [PSCustomObject]@{
        Id = $Id
        ScriptPath = $ScriptPath
        WorkingDirectory = $workingDirectory
        RemainingArgs = @($RemainingArgs)
        LockFile = $lockFile
        ScriptLog = $scriptLog
        ScriptLogErr = $scriptLogErr
        StartupResultFile = $startupResultFile
    }
    $requestJson = ConvertTo-Json -InputObject $request -Compress -Depth 10
    $requestPayload = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($requestJson))
    $powerShell = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh' } else { 'powershell' }
    $monitorArguments = "-NoProfile -File `"$monitorScriptPath`" -Payload $requestPayload"
    $monitorStartParameters = @{
        FilePath = $powerShell
        ArgumentList = $monitorArguments
        WorkingDirectory = $workingDirectory
        RedirectStandardOutput = $monitorLog
        RedirectStandardError = $monitorLogErr
        PassThru = $true
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $monitorStartParameters.WindowStyle = 'Hidden'
    }
}
catch {
    Exit-NotStarted "Could not prepare the async monitor: $($_.Exception.Message)" -RemoveLock
}

try {
    $monitorProcess = Start-Process @monitorStartParameters
}
catch {
    [Console]::Error.WriteLine("Could not confirm async monitor startup for '$Id'; worker status is unknown: $($_.Exception.Message)")
    exit 1
}

$startupDeadline = [DateTime]::UtcNow.AddSeconds(30)
while ([DateTime]::UtcNow -lt $startupDeadline) {
    if (Test-Path -LiteralPath $startupResultFile) {
        try {
            $startupResult = Get-Content -LiteralPath $startupResultFile -Raw | ConvertFrom-Json -ErrorAction Stop
        }
        catch {
            [Console]::Error.WriteLine("Async monitor returned an invalid startup result for '$Id': $($_.Exception.Message)")
            exit 1
        }

        if ($startupResult.id -ne $Id) {
            [Console]::Error.WriteLine("Async monitor returned a startup result for unexpected id '$($startupResult.id)'")
            exit 1
        }
        if ($startupResult.state -eq 'Started') {
            Write-JsonLine ([PSCustomObject]@{
                id = $Id
                state = 'Started'
            })
            exit 0
        }
        if ($startupResult.state -eq 'NotStarted' -and -not [string]::IsNullOrWhiteSpace($startupResult.stdErr)) {
            [Console]::Error.WriteLine([string]$startupResult.stdErr)
            Write-JsonLine ([PSCustomObject]@{
                id = $Id
                state = 'NotStarted'
                stdErr = [string]$startupResult.stdErr
            })
            exit 1
        }
        [Console]::Error.WriteLine("Async monitor returned an invalid startup state for '$Id'")
        exit 1
    }

    $monitorProcess.Refresh()
    if ($monitorProcess.HasExited) {
        $monitorError = if (Test-Path -LiteralPath $monitorLogErr) {
            (Get-Content -LiteralPath $monitorLogErr -Raw).Trim()
        }
        else {
            ''
        }
        [Console]::Error.WriteLine("Async monitor exited before confirming ownership for '$Id'. Worker status is unknown. $monitorError")
        exit 1
    }
    Start-Sleep -Milliseconds 50
}

[Console]::Error.WriteLine("Timed out waiting for async monitor startup acknowledgment for '$Id'. Worker status is unknown.")
exit 1
