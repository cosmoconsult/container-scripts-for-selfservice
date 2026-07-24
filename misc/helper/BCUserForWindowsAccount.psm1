<#
 .Synopsis
  Ensures a BC user exists for a Windows account.
 .Example
  New-BCUserForWindowsAccount -ServerInstance $ServerInstance -TenantParam $tenantParam -WindowsAccount $windowsAccount
#>
function New-BCUserForWindowsAccount {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,

        [Parameter(Mandatory = $true)]
        [hashtable]$TenantParam,

        [Parameter(Mandatory = $true)]
        [string]$WindowsAccount
    )

    $bcUserObject = Get-NAVServerUser -ServerInstance $ServerInstance @TenantParam | Where-Object { $_.UserName -eq $WindowsAccount } | Select-Object -First 1
    $bcUser = $bcUserObject.UserName
    Write-Host "BC user: $bcUser"

    if ($null -eq $bcUser) {
        Write-Host "Adding BC user $WindowsAccount for Windows account $WindowsAccount"
        New-NAVServerUser -ServerInstance $ServerInstance @TenantParam -WindowsAccount $WindowsAccount | Out-Null
        return $true
    }

    $windowsAccountIdentity = [System.Security.Principal.NTAccount]$WindowsAccount
    $windowsSecurityId = $windowsAccountIdentity.Translate([System.Security.Principal.SecurityIdentifier]).Value
    if ($bcUserObject.WindowsSecurityId -ne $windowsSecurityId) {
        Write-Host "Setting BC user $bcUser to Windows account $WindowsAccount"
        Set-NAVServerUser -ServerInstance $ServerInstance @TenantParam -UserName $bcUser -NewWindowsAccount $WindowsAccount | Out-Null
    }

    return $false
}
Export-ModuleMember -Function New-BCUserForWindowsAccount

<#
 .Synopsis
  Assigns a BC permission set to a Windows account when it is not already assigned.
 .Example
  Set-BCUserPermissionSetForWindowsAccount -ServerInstance $ServerInstance -TenantParam $tenantParam -WindowsAccount $windowsAccount -PermissionSetId SUPER
#>
function Set-BCUserPermissionSetForWindowsAccount {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,

        [Parameter(Mandatory = $true)]
        [hashtable]$TenantParam,

        [Parameter(Mandatory = $true)]
        [string]$WindowsAccount,

        [Parameter(Mandatory = $true)]
        [string]$PermissionSetId
    )

    $bcUserPermissionSets = @(Get-NAVServerUserPermissionSet -ServerInstance $ServerInstance @TenantParam -WindowsAccount $WindowsAccount | Select-Object -ExpandProperty PermissionSetID)
    Write-Host "BC user permission sets: $($bcUserPermissionSets -join ', ')"

    if ($bcUserPermissionSets -notcontains $PermissionSetId) {
        Write-Host "Granting $PermissionSetId permission set to BC user $WindowsAccount"
        New-NAVServerUserPermissionSet -WindowsAccount $WindowsAccount -PermissionSetId $PermissionSetId -ServerInstance $ServerInstance @TenantParam | Out-Null
    }
}
Export-ModuleMember -Function Set-BCUserPermissionSetForWindowsAccount

<#
 .Synopsis
  Removes a BC user for a Windows account.
 .Example
  Remove-BCUserForWindowsAccount -ServerInstance $ServerInstance -TenantParam $tenantParam -WindowsAccount $windowsAccount
#>
function Remove-BCUserForWindowsAccount {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string]$ServerInstance,

        [Parameter(Mandatory = $true)]
        [hashtable]$TenantParam,

        [Parameter(Mandatory = $true)]
        [string]$WindowsAccount
    )

    try {
        Write-Host "Removing BC user $WindowsAccount"
        Remove-NAVServerUser -ServerInstance $ServerInstance @TenantParam -WindowsAccount $WindowsAccount -Force
    }
    catch {
        Write-Host "Error removing user: $($_.Exception.Message)"
    }
}
Export-ModuleMember -Function Remove-BCUserForWindowsAccount