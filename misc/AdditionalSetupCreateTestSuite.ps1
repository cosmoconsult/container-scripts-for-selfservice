Write-Host "Create DEFAULT Test Suite"

Write-Host "Collecting information about the current user, server instance, tenant, and company..."
$me = whoami
$isOnPremArtifact = ($env:ArtifactUrl -match "(?i)[\\/]onprem[\\/]")
$createdTempUser = $false
$Companies = Get-NAVCompany -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object { $_.CompanyName -ne "My Company" }
$myaccount = Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object { $_.WindowsAccount -eq $me }

if ($null -eq $myaccount) {
    Write-Host "Adding $me as a user to the tenant $tenantId and assigning SUPER permission set"
    try {
        New-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -WindowsAccount $me -ErrorAction Stop
        $createdTempUser = $true
    }
    catch {
        Write-Warning "Skipping New-NAVServerUser: $($_.Exception.Message)"
    }

    try {
        New-NAVServerUserPermissionSet -WindowsAccount $me -PermissionSetId SUPER -ServerInstance $ServerInstance -Tenant $tenantId -ErrorAction Stop
    }
    catch {
        Write-Warning "Skipping New-NAVServerUserPermissionSet: $($_.Exception.Message)"
    }
}

foreach ($Company in $Companies) {
    Write-Host "Creating DEFAULT Test Suite in the company $($Company.CompanyName) of the tenant $tenantId"
    try {
        Invoke-NAVCodeunit -ServerInstance $ServerInstance -Tenant $tenantId -CompanyName $Company.CompanyName -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument 'DEFAULT' -ErrorAction Stop
    }
    catch {
        Write-Host "Error creating DEFAULT Test Suite: $($_.Exception.Message)"
    }
}

if ($createdTempUser) {
    Write-Host "Removing $me as a user from the tenant $tenantId"
    try {
        if ($isOnPremArtifact) {
            $tempUser = Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object { $_.WindowsAccount -eq $me } | Select-Object -First 1
            if ($null -ne $tempUser) {
                try {
                    Remove-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -InputObject $tempUser -ErrorAction Stop
                }
                catch {
                    if ($_.Exception.Message -match "Object reference not set to an instance of an object" -and -not [string]::IsNullOrWhiteSpace($tempUser.UserName)) {
                        Write-Warning "Remove-NAVServerUser via InputObject failed in onprem, retrying via UserName '$($tempUser.UserName)'"
                        Remove-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -UserName $tempUser.UserName -ErrorAction Stop
                    }
                    else {
                        throw
                    }
                }
            }
            else {
                Write-Host "Skipping Remove-NAVServerUser: user $me not found anymore"
            }
        }
        else {
            Remove-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -WindowsAccount $me -ErrorAction Stop
        }
    }
    catch {
        Write-Warning "Skipping Remove-NAVServerUser: $($_.Exception.Message)"
    }
}
