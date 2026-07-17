$permissionSetId = "SUPER"
$testSuiteName = "DEFAULT"

Write-Host "##[group]Create $testSuiteName Test Suite"

Write-Host "Collecting information about the server instance, tenant and companies..."

Write-Host "Server instance: $ServerInstance"
if ($tenantParam.ContainsKey('Tenant')) {
    Write-Host "Tenant: $($tenantParam.Tenant)"
} else {
    Write-Host "Tenant: None (single-tenant scope)"
}
$companies = @(Get-NAVCompany -ServerInstance $ServerInstance @tenantParam | Select-Object -ExpandProperty CompanyName | Where-Object { $_ -ne "My Company" })
Write-Host "Companies: $($companies -join ', ')"

Write-Host "Ensure OS user is a BC user and has the $permissionSetId permission set..."

$osUserIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$osUser = $osUserIdentity.Name
Write-Host "OS user: $osUser"
$bcUserObject = Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam | Where-Object { $_.UserName -eq $osUser } | Select-Object -First 1
$bcUser = $bcUserObject.UserName
Write-Host "BC user: $bcUser"

if ($null -eq $bcUser) {
    Write-Host "Adding BC user $osUser for OS user $osUser"
    New-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $osUser
} else {
    if ($bcUserObject.WindowsSecurityId -ne $osUserIdentity.User.Value) {
        Write-Host "Setting BC user $bcUser to OS user $osUser"
        Set-NAVServerUser -ServerInstance $ServerInstance @tenantParam -UserName $bcUser -NewWindowsAccount $osUser
    }
}

$bcUserPermissionSets = @(Get-NAVServerUserPermissionSet -ServerInstance $ServerInstance @tenantParam -WindowsAccount $osUser | Select-Object -ExpandProperty PermissionSetID)
Write-Host "BC user permission sets: $($bcUserPermissionSets -join ', ')"

if ($bcUserPermissionSets -notcontains $permissionSetId) {
    Write-Host "Granting $permissionSetId permission set to BC user $osUser"
    New-NAVServerUserPermissionSet -WindowsAccount $osUser -PermissionSetId $permissionSetId -ServerInstance $ServerInstance @tenantParam
}

foreach ($company in $companies) {
    try {
        Write-Host "Creating $testSuiteName Test Suite in the company $company"
        Invoke-NAVCodeunit -ServerInstance $ServerInstance @tenantParam -CompanyName $company -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument $testSuiteName -ErrorVariable err
    }
    catch {
        Write-Host "Error creating $testSuiteName Test Suite: $($_.Exception.Message)"
    }
}

if ($null -eq $bcUser) {
    try {
        Write-Host "Removing BC user $osUser"
        Remove-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $osUser
    }
    catch {
        Write-Host "Error removing user: $($_.Exception.Message)"
    }
}

Write-Host "##[endgroup]"