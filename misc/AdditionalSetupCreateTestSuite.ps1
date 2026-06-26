Write-Host "Create DEFAULT Test Suite"

Write-Host "Collecting information about the current user, server instance, tenant, and company..."
$me = whoami
$Companies = Get-NAVCompany -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object { $_.CompanyName -ne "My Company" }
$myaccount = Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object { $_.WindowsAccount -eq $me }

if ($null -eq $myaccount) {
    Write-Host "Adding $me as a user to the tenant $tenantId and assigning SUPER permission set"
    New-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -WindowsAccount $me
    New-NAVServerUserPermissionSet -WindowsAccount $me -PermissionSetId SUPER -ServerInstance $ServerInstance -Tenant $tenantId
}

foreach ($Company in $Companies) {
    Write-Host "Creating DEFAULT Test Suite in the company $($Company.CompanyName) of the tenant $($Tenant.Id)"
    try {
        Invoke-NAVCodeunit -ServerInstance $ServerInstance.ServerInstance -Tenant $Tenant.Id -CompanyName $Company.CompanyName -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument 'DEFAULT' -ErrorAction Stop
    }
    catch {
        Write-Host "Error creating DEFAULT Test Suite: $($_.Exception.Message)"
    }
}

if ($null -eq $myaccount) {
    Write-Host "Removing $me as a user from the tenant $($Tenant.Id)"
    Remove-NAVServerUser -ServerInstance $ServerInstance.ServerInstance -Tenant $Tenant.Id -WindowsAccount $me
}