Write-Host "Start Setup NAV Users"

if (($env:cosmoServiceRestart -eq $false) -and ![string]::IsNullOrWhiteSpace($env:bakfile)) {
    Write-Host " - Importing license to restored database mydatabase at $DatabaseServer\$DatabaseInstance"
    Invoke-Sqlcmd -Database "mydatabase" -Query "truncate table [dbo].[Tenant License State]" -ServerInstance "$DatabaseServer\$DatabaseInstance"

    if ([string]::IsNullOrWhiteSpace($env:licensefile)) {
        $licenseToImport = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Cronus.*").FullName
    }
    else {
        $licenseToImport = $env:licensefile
    }

    Import-NAVServerLicense -ServerInstance $ServerInstance -LicenseFile $licenseToImport -Database NavDatabase
    Set-NAVServerInstance -ServerInstance $ServerInstance -Restart

    Write-Host " - Deactivate all users to ensure license compliance"
    Get-NAVServerUser -ServerInstance $ServerInstance | Where-Object { $_.UserName.ToLower() -ne $env:username.ToLower() } | % {
        Write-Host " - Disable $($_.UserName)"
        Set-NAVServerUser -UserName $_.UserName -State Disabled -ServerInstance $ServerInstance -ErrorAction Continue
    }
}


Push-Location
# invoke default
. (Join-Path $runPath $MyInvocation.MyCommand.Name)

Pop-Location

$scripts = @(
                (Join-Path $PSScriptRoot "EnablePremium.ps1")
)



foreach ($script in $scripts) {
    if (Test-Path -Path $script) {
        Write-Host "Execute $script"
        . ($script)
    }
}
