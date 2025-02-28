<#
    .SYNOPSIS
    Waits for DataUpgrade to finish
    .DESCRIPTION
    Waits for DataUpgrade to finish
    .EXAMPLE
    Wait-DataUpgradeToFinish -ServerInstance MyServerInstance 
    .PARAMETER ServerInstance
    The Nav/Bc Server Instance where dataupgrade must be checked, eg. 'ProdBc16'
    .PARAMETER Tenant
    The Tenant of the Server Instance where dataupgrade must be checked, eg. 'default'
#>

function Wait-DataUpgradeToFinish {
    [cmdletbinding()]
    PARAM
    (
        [parameter(Mandatory = $true)]
        [string]$ServerInstance,
        [string]$Tenant,
        [switch]$Retry = $false
    )
    PROCESS {
        if (!$Tenant) { $Tenant = 'default' }

        for ($i = 0; $i -lt 10; $i++) {        
            try {      
                Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $tenant -Progress
            }
            catch { 
                Write-Host "Couldn't get the progress of the NAVDataUpgrade, maybe none is running"
            }

            try {
                $errors = Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant -ErrorOnly
            }
            catch { 
                Write-Host "Couldn't get the errors of the NAVDataUpgrade, maybe none is running"
            }
        
            if (!$errors) {
                Write-Host "no errors detected - process has been completed successfully"
                return;
            }

            # Stop the suspended process
            try {
                Stop-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant -Force
            }
            catch { 
                Write-Host "Couldn't stop the NAVDataUpgrade, maybe none is running"
            }

            $errorMessage = "Errors occurred during the NAVDataUpgrade process: " + [System.Environment]::NewLine
            ($errors | Out-String).Trim().Replace("`r`n", "`n").Split("`n") | ForEach-Object { $errorMessage += $_ + [System.Environment]::NewLine }
            Write-Host $errorMessage

            if ($Retry) {
                Write-Host "Retrying in 10 seconds, current try is $i"
                Start-Sleep -Seconds 10
                Start-NAVDataUpgrade -SkipUserSessionCheck -FunctionExecutionMode Serial -ServerInstance $ServerInstance -SkipAppVersionCheck -Force -ErrorAction Stop -Tenant $tenant
            }
            else {
                Write-Host "Exiting as retry is not enabled"
                break;
            }
        }
    }
}

Export-ModuleMember -Function Wait-DataUpgradeToFinish
