Write-Host "Create DEFAULT Test Suite"

$companies = Get-NAVCompany -ServerInstance $ServerInstance @tenantParam

foreach ($Company in $companies) {
    Write-Host "Creating DEFAULT Test Suite in the company $($Company.CompanyName)"
    try {
        Invoke-NAVCodeunit -ServerInstance $ServerInstance @tenantParam -CompanyName $Company.CompanyName -CodeunitId 130456 -MethodName 'CreateTestSuite' -Argument 'DEFAULT' -ErrorAction Stop
    }
    catch {
        Write-Host "Error creating DEFAULT Test Suite: $($_.Exception.Message)"
    }
}