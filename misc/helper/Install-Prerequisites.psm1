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

    $maxRetries = 3
    $retryCount = 0
    $success = $false

    while (-not $success -and $retryCount -lt $maxRetries) {
        try {
            Invoke-WebRequest "https://github.com/PowerShell/Win32-OpenSSH/releases/download/v9.5.0.0p1-Beta/OpenSSH-Win64.zip" -OutFile OpenSSH-Win64.zip -UseBasicParsing
            $success = $true
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                $waitTime = [math]::Pow(2, ($retryCount+2))
                Write-Warning "Download failed. Retrying in $waitTime seconds... (Attempt $retryCount of $maxRetries)"
                Start-Sleep -Seconds $waitTime
            }
            else {
                Write-Warning "Download failed after $maxRetries attempts: $_"
                Write-Warning "SSH installation aborted, a connection via SSH to this container will not work."
            }
        }
    }
  
    if ($success) {
        Write-Output "Download completed successfully."

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
  LoginGraceTime 5
  MaxStartups 60:30:100
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
    
        # pwsh as default shell for BC24+
        $bcVersion = [Version](Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Microsoft.Dynamics.Nav.Server.exe").VersionInfo.FileVersion
        if ($bcVersion -and $bcVersion.Major -ge 24) {
            $defaultShellPath = where.exe 'pwsh.exe' | Select-Object -last 1
        }

        if (! $defaultShellPath) {
            # fallback to powershell as default shell
            $defaultShellPath = "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
        }

        # set default shell
        New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value $defaultShellPath -PropertyType String -Force | Out-Null
    
        # create user
        New-LocalUser -Name "sshuser" -NoPassword | Out-Null
        Add-LocalGroupMember -Group "Administrators" -Member "sshuser"
    
    
        Write-Output "Setting sshd service startup type to 'Automatic'"
        Set-Service sshd -StartupType Automatic
        Set-Service ssh-agent -StartupType Automatic
        Write-Output "Setting sshd service restart behavior"
        sc.exe failure sshd reset= 86400 actions= restart/500
        Start-Service sshd
    }
  
    Write-Host "##[endgroup]"
}

Export-ModuleMember -Function Install-OpenSSH

