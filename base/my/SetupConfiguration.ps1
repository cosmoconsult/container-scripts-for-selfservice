Write-Host "Start Setup Configuration"

$scripts = @(
                        (Join-Path $PSScriptRoot "EnablePerformanceCounter.ps1")
                   )
Push-Location
# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)

Pop-Location

foreach ($script in $scripts){
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}
