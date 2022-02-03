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


try {
    if (! $Tenant) {
        $Tenant     = default
    }
    $companies  = [System.Collections.ArrayList]@() + ((Get-NAVCompany $ServerInstance -Tenant $Tenant -ErrorAction SilentlyContinue) | Where-Object { $_.CompanyName -ne "My Company" })

    foreach ($company in $companies) {
        Invoke-NAVCodeunit `
            -CodeunitId         9178 `
            -ServerInstance     $ServerInstance `
            -Tenant             $Tenant `
            -MethodName         'SaveExperienceTierCurrentCompany' `
            -Argument           "Premium" `
            -CompanyName        "$($company.CompanyName)"
    }
} catch {
    Write-Host "Error: $($_.Exception)" -ForegroundColor Red
}