# https://github.com/microsoft/navcontainerhelper/blob/main/ContainerHandling/Set-BcContainerKeyVaultAadAppAndCertificate.ps1

function Set-AlpacaContainerKeyVaultAadAppAndCertificate{
    Param(
        $serverInstance = "BC",
        $enablePublisherValidation = $false,
        $pfxFile = "C:/azurefileshare/common/AlpacaContainerKeyVaultReader.pfx",
        $pfxPassword = ConvertTo-SecureString -String "P@ssw0rd" -AsPlainText -Force,
        $clientId = "6efd7c53-94d3-489e-95a4-30e25de612ba",
        $doNotRestartServiceTier = $false
    )
    Set-NAVServerConfiguration -ServerInstance $serverInstance -KeyName "AzureKeyVaultAppSecretsPublisherValidationEnabled" -KeyValue $enablePublisherValidation.ToString().ToLowerInvariant() -WarningAction SilentlyContinue
            
    $importedPfxCertificate = Import-PfxCertificate -FilePath $pfxFile -Password $pfxPassword -CertStoreLocation Cert:\LocalMachine\My
    Write-Host "Keyvault Certificate Thumbprint: $($importedPfxCertificate.Thumbprint)"
    
    # Give SYSTEM permission to use the PFX file's private key
    $keyName = $importedPfxCertificate.PrivateKey.Key.UniqueName
    $keyPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\$keyName"
    if ($PSVersionTable.PSVersion -ge "6.0.0") {
        Import-Module Microsoft.PowerShell.Security -Force
        $acl = [System.IO.FileSystemAclExtensions]::GetAccessControl([System.IO.DirectoryInfo]::new($keyPath), 'Access')
    }
    else {
        $acl = (Get-Item $keyPath).GetAccessControl('Access')
    }
    $permission = 'NT AUTHORITY\SYSTEM',"Full","Allow"
    $accessRule = new-object System.Security.AccessControl.FileSystemAccessRule $permission
    $acl.AddAccessRule($accessRule)
    Set-Acl $keyPath $acl
    #$acl.Access
    
    Set-NavServerConfiguration -ServerInstance $serverInstance -KeyName AzureKeyVaultClientCertificateStoreLocation -KeyValue "LocalMachine" -WarningAction SilentlyContinue
    Set-NavServerConfiguration -ServerInstance $serverInstance -KeyName AzureKeyVaultClientCertificateStoreName     -KeyValue "My" -WarningAction SilentlyContinue
    Set-NavServerConfiguration -ServerInstance $serverInstance -KeyName AzureKeyVaultClientCertificateThumbprint    -KeyValue $importedPfxCertificate.Thumbprint -WarningAction SilentlyContinue
    Set-NavServerConfiguration -ServerInstance $serverInstance -KeyName AzureKeyVaultClientId                       -KeyValue $clientId -WarningAction SilentlyContinue
    
    if (!$doNotRestartServiceTier) {
        Write-Host "Restarting Service Tier"
        Set-NAVServerInstance -ServerInstance $serverInstance -Restart
        while (Get-NavTenant $serverInstance | Where-Object { $_.State -eq "Mounting" }) {
            Start-Sleep -Seconds 1
        }
    }
}
Export-ModuleMember -Function Set-AlpacaContainerKeyVaultAadAppAndCertificate