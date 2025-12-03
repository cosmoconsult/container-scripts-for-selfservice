function Invoke-AssignPremiumPlanToUser {
    param(
        [String]$Tenant = "default",
        [Object]$BcUser

    )
    Write-Host "Assign Premium plan for $($BcUser.Username)"
    $UserId = $BcUser.UserSecurityId
    Invoke-Sqlcmd -ErrorAction Ignore -ServerInstance 'localhost\SQLEXPRESS' -Query "USE [$tenantId]
        INSERT INTO [dbo].[User Plan`$63ca2fa4-4f03-4f2b-a480-172fef340d3f] ([Plan ID],[User Security ID]) VALUES ('{8e9002c0-a1d8-4465-b952-817d2948e6e2}','$UserId')"
}
Export-ModuleMember -Function Invoke-AssignPremiumPlanToUser