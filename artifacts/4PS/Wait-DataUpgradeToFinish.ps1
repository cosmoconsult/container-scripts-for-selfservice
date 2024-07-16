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
        [string]$Tenant
    )
    PROCESS {
        if (!$Tenant) { $Tenant = 'default' }
        
        try {      
            do {
                Start-Sleep -Seconds 1 | Out-Null
                $status = Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant
            } while ( "$($status.State)" -in @("InProgress") )
        }
        catch { 
            Write-Host "Couldn't get the status of the NAVDataUpgrade, maybe none is running"
        }

        try {
            $errors = Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $Tenant -ErrorOnly
            $errorsString = $errors | Out-String
        }
        catch { 
            Write-Host "Couldn't get the errors of the NAVDataUpgrade, maybe none is running"
        }
    
        if (!$errors -and ("$($status.NumericProgress)" -eq 1)) {
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
        $errorsString.Trim().Replace("`r`n", "`n").Split("`n") | ForEach-Object { $errorMessage += $_ + [System.Environment]::NewLine }
        Write-Host $errorMessage
    }
}

Export-ModuleMember -Function Wait-DataUpgradeToFinish
