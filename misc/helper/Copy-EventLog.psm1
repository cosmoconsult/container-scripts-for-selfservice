<#
 .Synopsis
  Get the Event log as an .evtx
 .Description
  Get the Event log as an .evtx file and copies it to C:\inetpub\wwwroot\http
 .Parameter logName
  Name of the log you want to get (default is Application)
 .Example
  Get-BcContainerEventLog
 .Example
  Get-BcContainerEventLog -logname Security
#>
function Copy-EventLog {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$false)]
        [string] $logname = "Application"
    )

    Write-Host "Getting event log for $containername"

    $eventLogFolder = "C:\inetpub\wwwroot\http"
    if (!(Test-Path $eventLogFolder)) {
        New-Item $eventLogFolder -ItemType Directory | Out-Null
    }
    $logfilename = ($logname + [DateTime]::Now.ToString("yyyy-MM-ddHH.mm.ss") + ".evtx")
    $eventLogName = Join-Path $eventLogFolder $logfilename
    $locale = (Get-WinSystemLocale).Name

    wevtutil epl $logname "$eventLogName"
    wevtutil al "$eventLogName" /locale:$locale
    
    Write-Host "got eventlog"
    Write-Host ("Eventlogname:" + $logfilename)
}


Export-ModuleMember -Function Copy-EventLog