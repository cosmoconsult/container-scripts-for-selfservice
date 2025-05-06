Write-Host "Handling multiple owners"

if ($env:owner -eq $null) {
    Write-Host "No owners found in env variable, skipping."
    return
}

$navuserpasswordAuth = $true
if ($env:auth -ieq "aad") {
    $navuserpasswordAuth = $false
}

$accounts = @($env:owner.Split(","))

foreach ($account in $accounts) {
    Write-Host "  Processing account: $account"
    $shortenedAccount = $account.Split("@")[0]
    $userNameToSet = $account
    if ($navuserpasswordAuth) {
        $userNameToSet = $shortenedAccount
    }

    # Check if account already exists
    $BcUser = Get-NAVServerUser -ServerInstance $ServerInstance -tenant $tenant | Where-Object { $_.UserName -ieq $shortenedAccount -or $_.UserName -like "$($shortenedAccount)@*" }
    if($BcUser) {
        '  User {0} already exists in the database.' -f $userNameToSet | Write-Host 

        Set-NAVServerUser `
            -ServerInstance $ServerInstance `
            -UserName $userNameToSet `
            -State Enabled `
            -tenant $tenant `
            -AuthenticationEmail $account

        '  User {0} is now set to enabled.' -f $userNameToSet | Write-Host
    } else {
        New-NavServerUser `
            -ServerInstance $ServerInstance `
            -UserName $userNameToSet `
            -tenant $tenant `
            -AuthenticationEmail $account

        '  Added user {0}  into Business Central.' -f $userNameToSet | Write-Host
    }

    # Set user permission set
    $PermissionSetIDs = (Get-NAVServerUserPermissionSet `
                        -UserName $userNameToSet `
                        -tenant $tenant `
                        -ServerInstance $ServerInstance).PermissionSetID
    if ($PermissionSet -in $PermissionSetIDs) {
        '  User {0} already has the PermissionSet {1}.' -f $userNameToSet, $PermissionSet | Write-Host
    } else {
        New-NavServerUserPermissionSet `
            -ServerInstance  $ServerInstance `
            -UserName $userNameToSet `
            -tenant $tenant `
            -PermissionSetId $PermissionSet

        '  Added permission set {0} on user {1} in Business Central.' -f $PermissionSet, $userNameToSet | Write-Host
    }
}