Write-Host "::group::Create DEFAULT Test Suite"

Write-Host "Collecting information about the server instance, tenant and companies..."

Write-Host "Server instance: $ServerInstance"
if ($tenantParam.ContainsKey('Tenant')) {
    Write-Host "Tenant: $($tenantParam.Tenant)"
} else {
    Write-Host "Tenant: None (single-tenant scope)"
}
$companies = @(Get-NAVCompany -ServerInstance $ServerInstance @tenantParam | Select-Object -ExpandProperty CompanyName | Where-Object { $_ -ne "My Company" })
Write-Host "Companies: $($companies -join ', ')"

Write-Host "Ensure OS user is a BC user and has the SUPER permission set..."

$me = whoami
Write-Host "OS user: $me"
$bcUser = Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam | Select-Object -ExpandProperty UserName | Where-Object { $_ -eq $me } | Select-Object -First 1
Write-Host "BC user: $bcUser"

if ($null -eq $bcUser) {
    Write-Host "Adding BC user $me"
    New-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me
}

$bcUserPermissionSets = @(Get-NAVServerUserPermissionSet -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me | Select-Object -ExpandProperty PermissionSetID)
Write-Host "BC user permission sets: $($bcUserPermissionSets -join ', ')"

if ($bcUserPermissionSets -notcontains "SUPER") {
    Write-Host "Granting BC user the SUPER permission set"
    New-NAVServerUserPermissionSet -WindowsAccount $me -PermissionSetId SUPER -ServerInstance $ServerInstance @tenantParam
}

foreach ($company in $companies) {
    try {
        Write-Host "Creating DEFAULT Test Suite in the company $company"
        Invoke-NAVCodeunit -ServerInstance $ServerInstance @tenantParam -CompanyName $company -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument 'DEFAULT' -ErrorAction Stop
    }
    catch {
        Write-Host "Error creating DEFAULT Test Suite: $($_.Exception.Message)"
    }
}

if ($null -eq $bcUser) {
    try {
        Write-Host "Removing BC user $me"
        Remove-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me
    }
    catch {
        Write-Host "Error removing user: $($_.Exception.Message)"
    }
}

Write-Host "::endgroup::"