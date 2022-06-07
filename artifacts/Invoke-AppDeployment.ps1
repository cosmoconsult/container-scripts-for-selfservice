[CmdletBinding()]
param (
    [string]$AppToDeploy, 
    [string]$Username,
    [string]$Password
)

# copied from https://www.waldo.be/2020/06/15/deploying-from-devops-the-right-way-enabling-external-deployment-in-onprem-business-central-environments/
if (-not (Get-Module -ListAvailable -Name ALOps.ExternalDeployer)) {
    Install-PackageProvider -Name NuGet -Force
    Install-module ALOps.ExternalDeployer -Force
    Import-module ALOps.ExternalDeployer 
    Install-ALOpsExternalDeployer 
    New-ALOpsExternalDeployer -ServerInstance BC
}

if (-not("dummy" -as [type])) {
    add-type -TypeDefinition @"
using System;
using System.Net;
using System.Net.Security;
using System.Security.Cryptography.X509Certificates;

public static class Dummy {
    public static bool ReturnTrue(object sender,
        X509Certificate certificate,
        X509Chain chain,
        SslPolicyErrors sslPolicyErrors) { return true; }

    public static RemoteCertificateValidationCallback GetDelegate() {
        return new RemoteCertificateValidationCallback(Dummy.ReturnTrue);
    }
}
"@
}

[System.Net.ServicePointManager]::ServerCertificateValidationCallback = [dummy]::GetDelegate()

# copied from https://github.com/waldo1001/Cloud.Ready.Software.PowerShell/blob/master/PSScripts/DevOps/DeployWithAutomationAPI.ps1

$APIBaseURL = "https://localhost:7048/BC/API/microsoft/automation/beta"

$pwd = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential ($Username, $pwd)

$Companies = Invoke-RestMethod -Method Get `
    -Uri "$APIBaseURL/companies" `
    -Credential $Credential

$companyId = $Companies.value[0].id

#GetExtensions
$getExtensions = Invoke-RestMethod -Method Get `
    -Uri "$APIBaseURL/companies($companyId)/extensions" `
    -Credential $Credential -UseBasicParsing

$getExtensions.value.displayName

#Publish Extension
Invoke-RestMethod -Method Patch `
    -Uri "$APIBaseURL/companies($companyId)/extensionUpload(0)/content" `
    -Credential $credential `
    -ContentType "application/octet-stream" `
    -Headers @{"If-Match" = "*" } `
    -InFile $AppToDeploy | Out-Null
