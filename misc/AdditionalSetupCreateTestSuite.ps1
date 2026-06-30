Write-Host "Create DEFAULT Test Suite"

Write-Host "Collecting information about the current user, server instance, tenant, and company..."
$me = whoami
$createdTempUser = $false
$Companies = Get-NAVCompany -ServerInstance $ServerInstance @tenantParam | Where-Object { $_.CompanyName -ne "My Company" }
$myaccount = Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam | Where-Object { $_.WindowsAccount -eq $me }

if ($null -eq $myaccount) {
    Write-Host "Adding $me as a user to the tenant $tenantId and assigning SUPER permission set"
    try {
        New-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me -ErrorAction Stop
        $createdTempUser = $true
    }
    catch {
        Write-Warning "Create user failed: $($_.Exception.Message)"
    }

    try {
        New-NAVServerUserPermissionSet -WindowsAccount $me -PermissionSetId SUPER -ServerInstance $ServerInstance @tenantParam -ErrorAction Stop
    }
    catch {
        Write-Warning "Assign SUPER failed: $($_.Exception.Message)"
    }
}

foreach ($Company in $Companies) {
    Write-Host "Creating DEFAULT Test Suite in the company $($Company.CompanyName)"
    try {
        Invoke-NAVCodeunit -ServerInstance $ServerInstance @tenantParam -CompanyName $Company.CompanyName -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument 'DEFAULT' -ErrorAction Stop
    }
    catch {
        Write-Host "Error creating DEFAULT Test Suite: $($_.Exception.Message)"
    }
}

if ($createdTempUser) {
    if ($tenantParam.ContainsKey('Tenant')) {
        Write-Host "Disabling temporary user $me in tenant $($tenantParam.Tenant)"
    }
    else {
        Write-Host "Disabling temporary user $me (single-tenant scope)"
    }
    try {
        Set-NAVServerUser -ServerInstance $ServerInstance @tenantParam -UserName $me -State Disabled -ErrorAction Stop
    }
    catch {
        try {
            Set-NAVServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $me -State Disabled -ErrorAction Stop
        }
        catch {
            Write-Warning "Cleanup failed: $($_.Exception.Message)"
        }
    }
}