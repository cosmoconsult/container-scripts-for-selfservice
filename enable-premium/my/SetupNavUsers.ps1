# Invoke default behavior
. (Join-Path $runPath $MyInvocation.MyCommand.Name)

if ([string]::IsNullOrEmpty($env:enablePremium) -or $($env:enablePremium).ToLower() -ne "true") {
    return;
}

Get-NavServerUser -serverInstance $ServerInstance -tenant default | Where-Object LicenseType -eq "FullUser" | ForEach-Object {
    $UserId = $_.UserSecurityId
    Write-Host "Assign Premium plan for $($_.Username)"
    Invoke-Sqlcmd -ErrorAction Ignore -ServerInstance 'localhost\SQLEXPRESS' -Query "USE [$TenantId]
    INSERT INTO [dbo].[User Plan`$63ca2fa4-4f03-4f2b-a480-172fef340d3f] ([Plan ID],[User Security ID]) VALUES ('{8e9002c0-a1d8-4465-b952-817d2948e6e2}','$userId')"
}

if ($env:IsBcSandbox -eq "Y") {
    try {
        if (! $Tenant) {
            $Tenant     = "default"
        }
        $companies  = [System.Collections.ArrayList]@() + ((Get-NAVCompany $ServerInstance -Tenant $Tenant -ErrorAction SilentlyContinue) | Where-Object { $_.CompanyName -ne "My Company" })

        $me = whoami
        $userexist = Get-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenant | Where-Object username -eq $me
        $companyParam = @{}
        if ($companyName -and $version.Major -gt 9) {
            $companyParam += @{
                "Company" = $CompanyName
                "Force" = $true
                "WarningAction" = "SilentlyContinue"
            }
        }
        if (!($userexist)) {
            New-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenant -WindowsAccount $me @companyParam
            New-NAVServerUserPermissionSet -ServerInstance $ServerInstance -Tenant $tenant -WindowsAccount $me -PermissionSetId SUPER
            Start-Sleep -Seconds 1
        } elseif ($userexist.state -eq "Disabled") {
            Set-NAVServerUser -ServerInstance $ServerInstance -Tenant $tenant -WindowsAccount $me -state Enabled @companyParam
        }

        foreach ($company in $companies) {
            Write-Host "Change experience at company information for $($company.CompanyName) to 'Premium' ..." -NoNewline
            Invoke-NAVCodeunit `
                -CodeunitId         9178 `
                -ServerInstance     $ServerInstance `
                -Tenant             $Tenant `
                -MethodName         'SaveExperienceTierCurrentCompany' `
                -Argument           "Premium" `
                -CompanyName        "$($company.CompanyName)"
            Write-Host "SUCCESS"
        }
    } catch {
        Write-Host "Error during set premium experience at company: $($company.CompanyName)"
        Write-Host "  Error Message: $($_.Exception)" -ForegroundColor Red
    }
}