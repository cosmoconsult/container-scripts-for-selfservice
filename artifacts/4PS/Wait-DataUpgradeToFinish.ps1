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
        
        Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $tenant -Progress

        # Make sure that Upgrade Process completed successfully.
        $errors = Get-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $tenant -ErrorOnly
    
        if(!$errors)
        {

            # no errors detected - process has been completed successfully
            return;
        }

        # Stop the suspended process
        Stop-NAVDataUpgrade -ServerInstance $ServerInstance -Tenant $tenant -Force

        $errorMessage = "Errors occurred during the Microsoft Dynamics NAV data upgrade process: " + [System.Environment]::NewLine
        foreach($nextErrorRecord in $errors)
        {
            $errorMessage += ("Codeunit ID: " + $nextErrorRecord.CodeunitId + ", Function: " + $nextErrorRecord.FunctionName + ", Error: " + $nextErrorRecord.Error + ", Company: " + $nextErrorRecord.CompanyName + [System.Environment]::NewLine)
        }

        Write-Error $errorMessage
    }
}

Export-ModuleMember -Function Wait-DataUpgradeToFinish