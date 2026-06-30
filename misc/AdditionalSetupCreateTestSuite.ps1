Write-Host "Create DEFAULT Test Suite"

Write-Host "Collecting information about the current user, server instance, tenant, and company..."
$me = whoami
$Companies = Get-NAVCompany -ServerInstance $ServerInstance @tenantParam | Where-Object { $_.CompanyName -ne "My Company" }
$myaccount = Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam | Where-Object { $_.WindowsAccount -eq $me }

Write-Host "Debug: ServerInstance=$ServerInstance, tenantId=$tenantId, currentUser=$me"
if ($tenantParam.ContainsKey('Tenant')) {
    Write-Host "Debug: tenantParam contains Tenant='$($tenantParam.Tenant)'"
}
else {
    Write-Host "Debug: tenantParam has no Tenant key (single-tenant scope)"
}
Write-Host "Debug: Companies found (excluding 'My Company')=$($Companies.Count)"
Write-Host "Debug: Matching WindowsAccount user found=$($null -ne $myaccount)"

if ($null -eq $myaccount) {
    Write-Host "Adding $me as a user to the tenant $tenantId and assigning SUPER permission set"
    New-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me
    New-NAVServerUserPermissionSet -WindowsAccount $me -PermissionSetId SUPER -ServerInstance $ServerInstance @tenantParam
    Write-Host "Debug: Create + SUPER assignment commands executed for $me"
}
else {
    Write-Host "Debug: User already exists, skip create path"
}

foreach ($Company in $Companies) {
    Write-Host "Creating DEFAULT Test Suite in the company $($Company.CompanyName) of the tenant $tenantId"
    try {
        Invoke-NAVCodeunit -ServerInstance $ServerInstance @tenantParam -CompanyName $Company.CompanyName -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument 'DEFAULT' -ErrorAction Stop
        Write-Host "Debug: CreateTestSuite succeeded in company '$($Company.CompanyName)'"
    }
    catch {
        Write-Host "Error creating DEFAULT Test Suite: $($_.Exception.Message)"
    }
}

if ($null -eq $myaccount) {
    Write-Host "Removing $me as a user from the tenant $tenantId"
    Remove-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me
    Write-Host "Debug: Remove command executed for $me"
}
else {
    Write-Host "Debug: Cleanup skipped (user was not created by this script)"
}
