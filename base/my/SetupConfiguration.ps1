Write-Host "Start Setup Configuration"

# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)

$scripts = @(
                        (Join-Path $PSScriptRoot "EnablePerformanceCounter.ps1")
                   )



foreach ($script in $scripts){
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}
