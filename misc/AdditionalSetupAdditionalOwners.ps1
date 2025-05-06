Write-Host "Handling multiple owners"

if ($env:owner -eq $null) {
    Write-Host "No owners found in env variable, skipping."
    return
}

$navuserpasswordAuth = $true
if ($env:auth -ieq "aad") {
    $navuserpasswordAuth = $false
}

$PermissionSet = "SUPER"

$accounts = @($env:owner.Split(","))

Write-Host "  Wait for container to be operational"
for ($i = 0; $i -lt 60; $i++) {
    $TenantState = (Get-NavTenant -ServerInstance BC -Tenant default).State
    if (($TenantState -eq "Mounted") -or ($TenantState -eq "Operational")) {
        break;
    }

    Write-Host "  Tenant not operational yet (try $i), sleeping 10s"
    Start-Sleep -Seconds 10
}


foreach ($account in $accounts) {
    Write-Host "  Processing account: $account"
    $shortenedAccount = $account.Split("@")[0]
    $userNameToSet = $account
    if ($navuserpasswordAuth) {
        $userNameToSet = $shortenedAccount
    }

    # Check if account already exists
    $BcUser = Get-NAVServerUser -ServerInstance $ServerInstance -tenant default | Where-Object { $_.UserName -ieq $shortenedAccount -or $_.UserName -like "$($shortenedAccount)@*" }
    if($BcUser) {
        if ($BcUser.State -eq "Disabled") {
            '  User {0} already exists in the database, but is disabled.' -f $userNameToSet | Write-Host 

            Set-NAVServerUser `
                -ServerInstance $ServerInstance `
                -UserName $userNameToSet `
                -State Enabled `
                -tenant default `
                -AuthenticationEmail $account `
                -password $securePassword

            '  User {0} is now set to enabled and has the default password.' -f $userNameToSet | Write-Host
        } else {
            '  User {0} already exists in the database and is enabled, doing nothing.' -f $userNameToSet | Write-Host 
        }
    } else {
        '  User {0} does not exist in the database.' -f $userNameToSet | Write-Host 
        if ($navuserpasswordAuth) {
            New-NavServerUser `
                -ServerInstance $ServerInstance `
                -UserName $userNameToSet `
                -tenant default `
                -password $securePassword
        } else {
            New-NavServerUser `
                -ServerInstance $ServerInstance `
                -UserName $userNameToSet `
                -tenant default `
                -AuthenticationEmail $account
        }

        '  Added user {0}  into Business Central.' -f $userNameToSet | Write-Host
    }

    # Set user permission set
    $PermissionSetIDs = (Get-NAVServerUserPermissionSet `
                        -UserName $userNameToSet `
                        -tenant default `
                        -ServerInstance $ServerInstance).PermissionSetID
    if ($PermissionSet -in $PermissionSetIDs) {
        '  User {0} already has the PermissionSet {1}.' -f $userNameToSet, $PermissionSet | Write-Host
    } else {
        New-NavServerUserPermissionSet `
            -ServerInstance  $ServerInstance `
            -UserName $userNameToSet `
            -tenant default `
            -PermissionSetId $PermissionSet

        '  Added permission set {0} on user {1} in Business Central.' -f $PermissionSet, $userNameToSet | Write-Host
    }
}