Import-Module (Join-Path $PSScriptRoot "helper\k8s-bc-helper.psd1")

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

$osUser = whoami
Write-Host "OS user: $osUser"

$bcUserCreated = New-BCUserForWindowsAccount -ServerInstance $ServerInstance -TenantParam $tenantParam -WindowsAccount $osUser
Set-BCUserPermissionSetForWindowsAccount -ServerInstance $ServerInstance -TenantParam $tenantParam -WindowsAccount $osUser -PermissionSetId "SUPER"

$testSuiteName = "DEFAULT"
foreach ($company in $companies) {
    try {
        Write-Host "Creating $testSuiteName Test Suite in the company $company"
        Invoke-NAVCodeunit -ServerInstance $ServerInstance @tenantParam -CompanyName $company -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument $testSuiteName -ErrorAction Stop
    }
    catch {
        Write-Host "Error creating $testSuiteName Test Suite: $($_.Exception.Message)"
    }
}

if ($bcUserCreated) {
    Remove-BCUserForWindowsAccount -ServerInstance $ServerInstance -TenantParam $tenantParam -WindowsAccount $osUser
}

Write-Host "##[endgroup]"