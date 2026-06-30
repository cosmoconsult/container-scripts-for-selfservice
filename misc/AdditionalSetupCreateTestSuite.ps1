Write-Host "Create DEFAULT Test Suite"

Write-Host "Collecting information about the current user, server instance, tenant, and company..."
$me = whoami
$Companies = Get-NAVCompany -ServerInstance $ServerInstance @tenantParam | Where-Object { $_.CompanyName -ne "My Company" }
$myaccount = Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam | Where-Object { $_.WindowsAccount -eq $me }

if ($null -eq $myaccount) {
    Write-Host "Adding $me as a user to the tenant $tenantId and assigning SUPER permission set"
    New-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me
    New-NAVServerUserPermissionSet -WindowsAccount $me -PermissionSetId SUPER -ServerInstance $ServerInstance @tenantParam
}

foreach ($Company in $Companies) {
    Write-Host "Creating DEFAULT Test Suite in the company $($Company.CompanyName) of the tenant $tenantId"
    try {
        Invoke-NAVCodeunit -ServerInstance $ServerInstance @tenantParam -CompanyName $Company.CompanyName -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument 'DEFAULT' -ErrorAction Stop
    }
    catch {
        Write-Host "Error creating DEFAULT Test Suite: $($_.Exception.Message)"
    }
}

if ($null -eq $myaccount) {
    Write-Host "Removing $me as a user from the tenant $tenantId"
    Remove-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me
}
