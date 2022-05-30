# extended copy of https://github.com/microsoft/nav-docker/blob/master/generic/Run/SetupNavUsers.ps1

# INPUT
#     $auth
#     $username (optional)
#     $securePassword (optional)
#
# OUTPUT
#

if ($auth -eq "Windows") {
    if ($username -ne "") {
        if (!(Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam -ErrorAction Ignore | Where-Object { $_.UserName.EndsWith("\$username", [System.StringComparison]::InvariantCultureIgnoreCase) -or $_.UserName -eq $username })) {
            Write-Host "Creating SUPER user"
            New-NavServerUser -ServerInstance $ServerInstance @tenantParam -WindowsAccount $username
            New-NavServerUserPermissionSet -ServerInstance $ServerInstance @tenantParam -WindowsAccount $username -PermissionSetId SUPER
        }
    }
} else {
    if (!(Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam -ErrorAction Ignore | Where-Object { $_.UserName -eq $username })) {
        Write-Host "Creating SUPER user"
        New-NavServerUser -ServerInstance $ServerInstance @tenantParam -Username $username -Password $securePassword -AuthenticationEMail $authenticationEMail
        New-NavServerUserPermissionSet -ServerInstance $ServerInstance @tenantParam -username $username -PermissionSetId SUPER
    } else {
        # found existing user with given name
        if ($env:mode -eq "4ps") {
            # in 4PS mode, we assume .bak with modified base app, so we push the user anyway
            Set-NavServerUser -ServerInstance $ServerInstance @tenantParam -Username $username -Password $securePassword -AuthenticationEMail $authenticationEMail
        }
    }
}
