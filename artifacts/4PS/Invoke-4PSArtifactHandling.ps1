function Invoke-4PSArtifactHandling {
    [cmdletbinding()]
    PARAM
    (
        [parameter(Mandatory=$true)]
        [string]$username,
        [parameter(Mandatory=$true)]
        [SecureString]$securepassword,
        [parameter(Mandatory=$true)]
        [hashtable]$tenantParam
    )
    PROCESS
    {
        if ($env:mode -eq "4ps") {
            Write-Host "4PS mode found"
            c:\Run\prompt.ps1

            if ($env:cosmoServiceRestart -eq $true) {
                Write-Host "4PS initialization skipped as this seems to be a service restart"
            } else {
                Write-Host "4PS initialization starts"
                $startTime4PS = [DateTime]::Now
                $me = whoami
                $userexist = Get-NAVServerUser -ServerInstance BC | Where-Object username -eq $me
                if (! $userexist) {
                    New-NAVServerUser -ServerInstance BC -WindowsAccount $me -Force -ErrorAction SilentlyContinue
                    New-NAVServerUserPermissionSet -ServerInstance BC -WindowsAccount $me -PermissionSetId SUPER -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 1
                }

                $userexist = Get-NAVServerUser -ServerInstance BC | Where-Object username -eq $username
                if (! $userexist) {
                    New-NAVServerUser -ServerInstance BC -Username $username -Password $securepassword -Force -ErrorAction SilentlyContinue
                }
                else {
                    Set-NAVServerUser -ServerInstance BC -Username $username -Password $securepassword -Force -ErrorAction SilentlyContinue
                }
                New-NAVServerUserPermissionSet -ServerInstance BC -Username $username -PermissionSetId SUPER -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1

                Publish-NAVApp -ServerInstance BC -Path 'C:\AzureFileShare\bc-data\extension\4PS B.V._Container initializer_1.0.0.0.app' -SkipVerification -Scope Tenant
                Sync-NAVApp -ServerInstance BC -Name 'Container initializer'
                Install-NAVApp -ServerInstance BC -Name 'Container initializer'

                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securepassword)
                $unsecurepassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

                $files = Get-ChildItem "c:\azurefileshare\bc-data\demo" -Filter *.xml | Sort-Object Name -Descending
                $firstRun = $true
                foreach ($demoDataFile in $files) {
                    $demoDataFileName = $demoDataFile | ForEach-Object { $_.Name }
                    "  Using XML file {0}" -f $demoDataFile.FullName | Write-Host 
                    if ($demoDataFileName -match 'DemoData_(.*)_.xml') {
                        $companyName = $Matches[1]
                        Write-Host "  Create and initialize company $companyName"
                        New-NAVCompany -CompanyName $companyName -ServerInstance BC

                        Write-Host "    Init setup tables"
                        Invoke-NavCodeunit `
                            -ServerInstance BC `
                            -CompanyName $companyName `
                            -Codeunitid 2 `
                            -MethodName 'InitSetupTables' `
                            -TimeZone ServicesDefaultTimeZone `
                            -ErrorAction SilentlyContinue 
                        
                        if ($env:IsBuildContainer -ne "true") {
                            Write-Host "    Import setup data from XML file"
                            Invoke-NavCodeunit `
                                -ServerInstance BC `
                                -CompanyName $companyName `
                                -CodeunitId 11012268 `
                                -MethodName ImportSetupDataFromXmlFile `
                                -Argument "$($demoDataFile.FullName)"
                        } else {
                            Write-Host "    Skip import setup data from XML file as this seems to be a build container"
                        }                
                            
                        Write-Host "    Run manual data upgrade 4PS"
                        Invoke-NavCodeunit `
                            -ServerInstance BC `
                            -CompanyName $companyName `
                            -CodeunitId 50189 `
                            -MethodName RunManualDataUpgrade `
                            -Argument "$firstRun"
                            
                        if ($env:IsBuildContainer -ne "true") {
                            Write-Host "    Initialize FSA setup"
                            Invoke-NavCodeunit `
                                -ServerInstance BC `
                                -CompanyName $companyName `
                                -CodeunitId 50189 `
                                -MethodName InitializeFSASetup

                            Write-Host "    Initialize OSA setup"
                            Invoke-NavCodeunit `
                                -ServerInstance BC `
                                -CompanyName $companyName `
                                -CodeunitId 50189 `
                                -MethodName InitializeOSASetup

                            if ($firstRun) {
                                Write-Host "    Initialize WebServices"
                                Invoke-NavCodeunit `
                                    -ServerInstance BC `
                                    -CompanyName $companyName `
                                    -CodeunitId 50189 `
                                    -MethodName PublishAllWebServices

                                Write-Host "    Initialize FSA"
                                Invoke-NavCodeunit `
                                    -ServerInstance BC `
                                    -CompanyName $companyName `
                                    -CodeunitId 50189 `
                                    -MethodName InitializeFSA

                                Write-Host "    Initialize OSA"
                                Invoke-NavCodeunit `
                                    -ServerInstance BC `
                                    -CompanyName $companyName `
                                    -CodeunitId 11128546 `
                                    -MethodName InitializeOSA

                                Write-Host "    Initialize License"
                                Invoke-NavCodeunit `
                                    -ServerInstance BC `
                                    -CompanyName $companyName `
                                    -CodeunitId 50189 `
                                    -MethodName CreateLicenses
                                $firstRun = $false
                            }

                            Write-Host "    Initialize General User ($username / $unsecurepassword) in $companyName"
                            Invoke-NAVCodeunit `
                                -ServerInstance BC `
                                -CompanyName $companyName `
                                -CodeunitId 50189 `
                                -MethodName CreateGeneralAppUser `
                                -Argument "$($username.PadRight(100))$($unsecurepassword.PadRight(64))"

                            Write-Host "    Initialize FSA User"
                            Invoke-NAVCodeunit `
                                -ServerInstance BC `
                                -CompanyName $companyName `
                                -CodeunitId 50189 `
                                -MethodName CreateFSAUser `
                                -Argument "$($username.PadRight(100))$($unsecurepassword.PadRight(64))"

                            Write-Host "    Initialize OSA User"
                            Invoke-NAVCodeunit `
                                -ServerInstance BC `
                                -CompanyName $companyName `
                                -CodeunitId 50189 `
                                -MethodName CreateOSAUser `
                                -Argument "$($username.PadRight(100))$($unsecurepassword.PadRight(64))"
                        } else {
                            Write-Host "    Skip app, app user and app license init as this seems to be a build container"
                        }
                    }
                }
                
                if ((Get-NAVServerUser -ServerInstance $ServerInstance @tenantParam -ErrorAction Ignore | Where-Object { $_.UserName -eq $username })) {
                    # found existing user with given name
                    # in 4PS mode, we assume .bak with modified base app, so we push the password again as the standard user setup script would ignore this
                    Set-NavServerUser -ServerInstance $ServerInstance @tenantParam -Username $username -Password $securePassword -AuthenticationEMail $authenticationEMail
                }
                
                $timespent4PS = [Math]::Round([DateTime]::Now.Subtract($startTime4PS).Totalseconds)
                Write-Host "  4PS initialization took $timespent4PS seconds"
            }
        }
    }
}

Export-ModuleMember -Function Invoke-4PSArtifactHandling