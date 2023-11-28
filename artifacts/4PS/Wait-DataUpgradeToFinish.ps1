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
        [parameter(Mandatory=$true)]
        [string]$ServerInstance,
        [string]$Tenant
    )
    PROCESS
    {
        if (!$Tenant) {
            $Tenant = 'default'
        }

        try {
            Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $tenant -Progress
        }
        catch { 
            Write-Host "Couldn't get the progress of the NAVDataUpgrade, maybe none is running"
        }

        try {
            # Make sure that Upgrade Process completed successfully.
            $errors = Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $tenant -ErrorOnly
        }
        catch { 
            Write-Host "Couldn't get the errors of the NAVDataUpgrade, maybe none is running"
        }
    
        if(!$errors)
        {

            Write-Host "no errors detected - process has been completed successfully"
            return;
        }

        # Stop the suspended process
        try {
            Stop-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $tenant -Force
        }
        catch { 
            Write-Host "Couldn't stop the NAVDataUpgrade, maybe none is running"
        }

        $errorMessage = "Errors occurred during the Microsoft Dynamics NAV data upgrade process: " + [System.Environment]::NewLine
        foreach($nextErrorRecord in $errors)
        {
            $errorMessage += ("Codeunit ID: " + $nextErrorRecord.CodeunitId + ", Function: " + $nextErrorRecord.FunctionName + ", Error: " + $nextErrorRecord.Error + ", Company: " + $nextErrorRecord.CompanyName + [System.Environment]::NewLine)
        }

        Write-Host $errorMessage
    }
}

Export-ModuleMember -Function Wait-DataUpgradeToFinish
