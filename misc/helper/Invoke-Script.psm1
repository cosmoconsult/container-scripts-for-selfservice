function Invoke-Script {
    param (
        [Parameter(Mandatory = $true, Position = 0)]
        [string]
        $ScriptPath
    )

    $usePwsh = $false #DEBUG

    if ($usePwsh) {
        if (-not $global:PowerShellSession) {
            $configurationName = 'PowerShell.7'
            write-host "Create new PowerShell session"
            $global:PowerShellSession = New-PSSession -ConfigurationName $configurationName

            Invoke-Command -Session $session -ScriptBlock { 

                $ErrorActionPreference = 'Stop'
                $runPath = "c:\Run"
                $myPath = Join-Path $runPath "my"

                function Get-MyFilePath([string]$FileName) {
                    if ((Test-Path $myPath -PathType Container) -and (Test-Path (Join-Path $myPath $FileName) -PathType Leaf)) {
                    (Join-Path $myPath $FileName)
                    }
                    else {
                    (Join-Path $runPath $FileName)
                    }
                }

                [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

                . (Get-MyFilePath "prompt.ps1")  | Out-Null
                . (Get-MyFilePath "ServiceSettings.ps1") | Out-Null
                . (Get-MyFilePath "HelperFunctions.ps1") | Out-Null


                Set-Location $runPath
            } 
        }

        Invoke-Command -Session $global:PowerShellSession -FilePath $ScriptPath

    }
    else {
        . ($ScriptPath)
    }
}

Export-ModuleMember -Function Invoke-Script