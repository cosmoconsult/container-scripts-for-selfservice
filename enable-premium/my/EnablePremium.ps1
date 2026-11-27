if ([string]::IsNullOrEmpty($env:enablePremium) -or $($env:enablePremium).ToLower() -ne "true") {
    return;
}

Import-Module "C:\run\my\AssignPremiumPlanToUser.psm1"

if (!$tenantId) { $tenantId = "default" }

Get-NavServerUser -serverInstance $ServerInstance -tenant $tenantId | Where-Object LicenseType -eq "FullUser" | ForEach-Object {
    Invoke-AssignPremiumPlanToUser -Tenant $tenantId -BcUser $_
}

if ($env:IsBcSandbox -eq "Y") {
    try {
        $companies = [System.Collections.ArrayList]@() + ((Get-NAVCompany $ServerInstance -Tenant $tenantId -ErrorAction SilentlyContinue) | Where-Object { $_.CompanyName -ne "My Company" })

        $me = whoami
        $userexist = Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId | Where-Object username -eq $me
        $companyParam = @{}
        if ($companyName -and $version.Major -gt 9) {
            $companyParam += @{
                "Company"       = $CompanyName
                "Force"         = $true
                "WarningAction" = "SilentlyContinue"
            }
        }
        if (!($userexist)) {
            New-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -WindowsAccount $me @companyParam
            New-NAVServerUserPermissionSet -ServerInstance $ServerInstance -Tenant $tenantId -WindowsAccount $me -PermissionSetId SUPER
            Start-Sleep -Seconds 1
        }
        elseif ($userexist.state -eq "Disabled") {
            Set-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenantId -WindowsAccount $me -state Enabled @companyParam
        }

        foreach ($company in $companies) {
            Write-Host "Change experience at company information for $($company.CompanyName) to 'Premium' ..." -NoNewline
            Invoke-NAVCodeunit `
                -CodeunitId         9178 `
                -ServerInstance     $ServerInstance `
                -Tenant             $tenantId `
                -MethodName         'SaveExperienceTierCurrentCompany' `
                -Argument           "Premium" `
                -CompanyName        "$($company.CompanyName)"
            Write-Host "SUCCESS"
        }
    }
    catch {
        Write-Host "Error during set premium experience at company: $($company.CompanyName)"
        Write-Host "  Error Message: $($_.Exception)" -ForegroundColor Red
    }
}