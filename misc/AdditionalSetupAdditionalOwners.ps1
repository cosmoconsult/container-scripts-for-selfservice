Write-Host "Handling multiple owners"

if ($env:IsBuildContainer -eq "true") {
    Write-Host "Running in a build container, skipping."
    return
}

if ($env:owner -eq $null -or $env:owner -eq "") {
    Write-Host "No owners found in env variable, skipping."
    return
}

$navuserpasswordAuth = $true
if ($env:auth -ieq "aad") {
    $navuserpasswordAuth = $false
}

$PermissionSet = "SUPER"

$accounts = @($env:owner.Split(","))

Wait-NAVTenantReady -ServerInstance $ServerInstance -Tenant $tenantId -Retries 60 -OutputPrefix "  "


foreach ($account in $accounts) {
    Write-Host "  Processing account: $account"
    $shortenedAccount = $account.Split("@")[0]
    $userNameToSet = $account
    if ($navuserpasswordAuth) {
        $userNameToSet = $shortenedAccount
    }

    # Check if account already exists
    $BcUser = Get-NAVServerUser -ServerInstance $ServerInstance -tenant $tenantId | Where-Object { $_.UserName -ieq $shortenedAccount -or $_.UserName -like "$($shortenedAccount)@*" }
    if($BcUser) {
        if ($BcUser.State -eq "Disabled") {
            '  User {0} already exists in the database, but is disabled.' -f $userNameToSet | Write-Host 

            Set-NAVServerUser `
                -ServerInstance $ServerInstance `
                -UserName $userNameToSet `
                -State Enabled `
                -tenant $tenantId `
                -AuthenticationEmail $account `
                -password $securePassword

            '  User {0} is now set to enabled and has the default password.' -f $userNameToSet | Write-Host
        } else {
            '  User {0} already exists in the database and is enabled, doing nothing.' -f $userNameToSet | Write-Host 
            continue
        }
    } else {
        '  User {0} does not exist in the database.' -f $userNameToSet | Write-Host 
        if ($navuserpasswordAuth) {
            New-NavServerUser `
                -ServerInstance $ServerInstance `
                -UserName $userNameToSet `
                -tenant $tenantId `
                -password $securePassword
        } else {
            New-NavServerUser `
                -ServerInstance $ServerInstance `
                -UserName $userNameToSet `
                -tenant $tenantId `
                -AuthenticationEmail $account
        }

        '  Added user {0}  into Business Central.' -f $userNameToSet | Write-Host
    }

    # Set user permission set
    $PermissionSetIDs = (Get-NAVServerUserPermissionSet `
                        -UserName $userNameToSet `
                        -tenant $tenantId `
                        -ServerInstance $ServerInstance).PermissionSetID
    if ($PermissionSet -in $PermissionSetIDs) {
        '  User {0} already has the PermissionSet {1}.' -f $userNameToSet, $PermissionSet | Write-Host
    } else {
        New-NavServerUserPermissionSet `
            -ServerInstance  $ServerInstance `
            -UserName $userNameToSet `
            -tenant $tenantId `
            -PermissionSetId $PermissionSet

        '  Added permission set {0} on user {1} in Business Central.' -f $PermissionSet, $userNameToSet | Write-Host
    }
}