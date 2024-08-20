Write-Host "Finding users with duplicate AuthenticationEmail and fixing disabled duplicate users"

$duplicateAadUserSets = Get-NAVServerUser -ServerInstance $ServerInstance -Tenant "default" | where { $_.AuthenticationEmail -ne '' } | group 'AuthenticationEmail' | Where { $_.Count -gt 1 } 

foreach ($duplicateAadUserSet in $duplicateAadUserSets)
{
    $disabledDuplicateUsers = $duplicateAadUserSet.Group | Where-Object { $_.State -eq 'Disabled' }

    foreach ($disabledDuplicateUser in $disabledDuplicateUsers)
    {
        Write-Host "Fixing AuthenticationEmail of duplicate user $($_.UserName)"

        # moving to a non-existent email as removing doesn't work
        Set-NAVServerUser -ServerInstance $ServerInstance -UserName $_.UserName -AuthenticationEmail "none@example.com"
    }
}