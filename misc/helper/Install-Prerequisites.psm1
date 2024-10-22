<#
 .Synopsis
  Install Open SSH in Container and activates PubKey authentification
 .Example
  Install-OpenSSH
#>
function Install-OpenSSH {
  Write-Host "##[group]Install OpenSSH"
  if (!(Test-Path -Path "C:\pubKey\pubkey.pub")) {
    Write-Output "No ssh key found, ssh disabled"
    return
  }
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

  Write-Output "Downloading OpenSSH"
  $ProgressPreference = "SilentlyContinue"
  Invoke-WebRequest "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v8.0.0.0p1-Beta/OpenSSH-Win64.zip" -OutFile OpenSSH-Win64.zip -UseBasicParsing
  
  Write-Output "Expanding OpenSSH"
  Expand-Archive OpenSSH-Win64.zip C:\\
  Remove-Item -Force OpenSSH-Win64.zip
  
  Push-Location C:\\OpenSSH-Win64
  
  Write-Output "Installing OpenSSH"
  & .\\install-sshd.ps1
  
  Write-Output "Generating host keys"
  .\\ssh-keygen.exe -A
  
  Write-Output "Fixing host file permissions"
  & .\\FixHostFilePermissions.ps1 -Confirm:$false
  
  Write-Output "Fixing user file permissions"
  & .\\FixUserFilePermissions.ps1 -Confirm:$false
  
  Pop-Location
  
  $newPath = 'C:\\OpenSSH-Win64;' + [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::Machine)
  [Environment]::SetEnvironmentVariable("PATH", $newPath, [EnvironmentVariableTarget]::Machine)
  
  @"
  Port 22
  SyslogFacility LOCAL0
  PubkeyAuthentication yes
  PasswordAuthentication no
  ClientAliveInterval 60
  Subsystem	sftp	sftp-server.exe
  Match Group administrators
         AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
"@ | Out-File "C:\ProgramData\ssh\sshd_config" -Encoding utf8

  
  $path = "c:\ProgramData\ssh\administrators_authorized_keys" 
  
  $sshkey = Get-Content("C:\pubKey\pubkey.pub") 
  $sshKey | Out-File $path -Encoding utf8

  $acl = Get-Acl -Path $path
  $acl.SetSecurityDescriptorSddlForm("O:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)")
  Set-Acl -Path $path -AclObject $acl
  
  # make powershell default shell
  New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -PropertyType String -Force
  
  # create user
  New-LocalUser -Name "sshuser" -NoPassword
  Add-LocalGroupMember -Group "Administrators" -Member "sshuser"
  
  
  Write-Output "Setting sshd service startup type to 'Automatic'"
  Set-Service sshd -StartupType Automatic
  Set-Service ssh-agent -StartupType Automatic
  Write-Output "Setting sshd service restart behavior"
  sc.exe failure sshd reset= 86400 actions= restart/500
  Start-Service sshd
  
  Write-Host "##[endgroup]"
}

Export-ModuleMember -Function Install-OpenSSH

<#
 .Synopsis
  Install Chocolatey in Container
 .Example
  Install-Chocolatey
#>
function Install-Chocolatey {
    Write-Host "##[group]Install Chocolatey"
    Set-ExecutionPolicy Bypass -Scope Process -Force; 
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; 
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    refreshenv
    Write-Output "Installation Chocolatey completed"
    Write-Host "##[endgroup]"
}

Export-ModuleMember -Function Install-Chocolatey


<#
 .Synopsis
  Install Nodejs in Container
 .Example
  Install-Nodejs
#>
function Install-Nodejs {
    Write-Host "##[group]Install Nodejs"
    choco install nodejs.install --version 20.17.0 -y
    Import-Module $env:ChocolateyInstall\helpers\chocolateyProfile.psm1
    refreshenv
    Write-Output "Installation Nodejs completed"
    Write-Host "##[endgroup]"
}

Export-ModuleMember -Function Install-Nodejs


