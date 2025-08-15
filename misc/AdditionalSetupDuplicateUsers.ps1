Write-Host "Finding users with duplicate AuthenticationEmail and fixing disabled duplicate users"

$duplicateAadUserSets = Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId | where { $_.AuthenticationEmail -ne '' } | group 'AuthenticationEmail' | Where { $_.Count -gt 1 } 

foreach ($duplicateAadUserSet in $duplicateAadUserSets)
{
    $disabledDuplicateUsers = $duplicateAadUserSet.Group | Where-Object { $_.State -eq 'Disabled' }

    foreach ($disabledDuplicateUser in $disabledDuplicateUsers)
    {
        # moving to a non-existent email as removing doesn't work
        if ($disabledDuplicateUser.UserName) {
            Write-Host "Fixing AuthenticationEmail of duplicate user $($disabledDuplicateUser.UserName)"
            Set-NAVServerUser -Tenant $tenantId -ServerInstance $ServerInstance -UserName $disabledDuplicateUser.UserName -AuthenticationEmail "none@example.com" -State Disabled
        }
    }
}
