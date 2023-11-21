function Invoke-4PSArtifactHandling {
    [cmdletbinding()]
    PARAM
    (
        [parameter(Mandatory = $true)]
        [string]$username,
        [parameter(Mandatory = $true)]
        [SecureString]$securepassword,
        [parameter(Mandatory = $true)]
        [hashtable]$tenantParam
    )
    PROCESS {
        if ($env:mode -eq "4ps") {
            Write-Host "4PS mode found"
            c:\Run\prompt.ps1

            $appDatabaseName = Get-AppDatabaseName
            Write-Host "  app database name is: $appDatabaseName"

            if ($env:cosmoServiceRestart -eq $true) {
                Write-Host "4PS initialization skipped as this seems to be a service restart"
            }
            elseif ("CRONUS" -eq $appDatabaseName -or "default" -eq $appDatabaseName) {
                Write-Host "4PS initialization skipped as this seems to be a Microsoft standard database"
            }
            else {
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

                $use4PSContainerInitializer = $env:AZP_SERVICE_DISPLAYNAME -notlike "*Skip4PSContainerInitializer*"
                $sysAppInfoFS = Get-NAVAppInfo -Path 'C:\Applications\system application\source\Microsoft_System Application.app'

                if ($use4PSContainerInitializer) {    
                    $initializerVersion = ''
                    if ($sysAppInfoFS.Version.Major -eq 21) {
                        $initializerVersion = "$($sysAppInfoFS.Version.Major).$($sysAppInfoFS.Version.Minor).2.0"
                    }
                    elseif ($sysAppInfoFS.Version.Major -gt 21) {
                        $initializerVersion = "$($sysAppInfoFS.Version.Major).$($sysAppInfoFS.Version.Minor).0.0"
                    }
                    elseif ($sysAppInfoFS.Version.Major -eq 20) {
                        $initializerVersion = '2.0.0.0'
                    }
                    elseif ($sysAppInfoFS.Version.Major -eq 19) {
                        $initializerVersion = '1.0.0.0'
                    }
                    else {
                        Write-Error "Container seems to have a version where we don't have a matching initializer app: $($sysAppInfoFS.Version.Major).$($sysAppInfoFS.Version.Minor)"
                    }

                    $initializerPath = "C:\AzureFileShare\bc-data\extension\4PS B.V._Container initializer_$initializerVersion.app"
                    if (-not (Test-Path $initializerPath)) {
                        Write-Error "Couldn't find the expected initializer app at $initializerPath"
                    }
                    Publish-NAVApp -ServerInstance BC -Path $initializerPath -SkipVerification -Scope Tenant
                    Sync-NAVApp -ServerInstance BC -Name 'Container initializer'
                    Install-NAVApp -ServerInstance BC -Name 'Container initializer'
                }
                else {
                    Write-Host "Skipping installation of container initializer app at $initializerPath as it's disabled by environment variable"
                }

                $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securepassword)
                $unsecurepassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

                $firstRun = $true
                $files = Get-DemoDataFiles
                foreach ($demoDataFile in $files) {
                    $demoDataFileName = $demoDataFile | ForEach-Object { $_.Name }
                    "  Using XML file {0}" -f $demoDataFile.FullName | Write-Host 
                    if ($demoDataFileName -match 'DemoData_(.*)_.xml') {
                        $companyName = $Matches[1]
                        Write-Host "  Initialize company $companyName"
                        Write-Host "    Init setup tables"
                        Invoke-NavCodeunit `
                            -ServerInstance BC `
                            -CompanyName $companyName `
                            -Codeunitid 2 `
                            -MethodName 'InitSetupTables' `
                            -TimeZone ServicesDefaultTimeZone `
                            -ErrorAction SilentlyContinue 
                        
                        Write-Host "    Import setup data from XML file"
                        Invoke-NavCodeunit `
                            -ServerInstance BC `
                            -CompanyName $companyName `
                            -CodeunitId 11012268 `
                            -MethodName ImportSetupDataFromXmlFile `
                            -Argument "$($demoDataFile.FullName)"
                        
                        if ($use4PSContainerInitializer) {
                            if ($sysAppInfoFS.Version.Major -le 20) {
                                # Only required on 20 and older
                                Write-Host "    Run manual data upgrade 4PS"
                                Invoke-NavCodeunit `
                                    -ServerInstance BC `
                                    -CompanyName $companyName `
                                    -CodeunitId 50189 `
                                    -MethodName RunManualDataUpgrade `
                                    -Argument "$firstRun"
                            }   

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
                                    
                                Write-Host "    Set FSA redirect URI"
                                Invoke-NAVCodeunit `
                                    -ServerInstance BC `
                                    -CompanyName $companyName `
                                    -CodeunitId 50189 `
                                    -MethodName CreateRedirectUri `
                                    -Argument "https://fps-alpaca.westeurope.cloudapp.azure.com/$($(hostname).Split("-")[0])-fsa-generic-app/gapcheck/callback"

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
                            }
                            
                            Set-NAVServerConfiguration -KeyName "ServicesDefaultCompany" -KeyValue "$companyName" -ServerInstance BC
                            
                            $firstRun = $false
                        }
                        if ($use4PSContainerInitializer) {
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

                            if ($sysAppInfoFS.Version.Major -gt 20) {
                                # Only available on 21 and newer
                                Write-Host "    Initialize Container Information"
                                Invoke-NAVCodeunit `
                                    -ServerInstance BC `
                                    -CompanyName $companyName `
                                    -CodeunitId 50189 `
                                    -MethodName InitContainer `
                                    -Argument "$($env:AZP_SERVICE_DISPLAYNAME)"
                            }
                        }
                    }
                }
                if ($firstRun -and $use4PSContainerInitializer) {
                    Write-Host "  Looks like no company has been created from demo data, creating an empty one"
                    New-NAVCompany -CompanyName "Empty Company" -ServerInstance BC
                }
                
                if ((Get-NAVServerUser -ServerInstance BC @tenantParam -ErrorAction Ignore | Where-Object { $_.UserName -eq $username })) {
                    # found existing user with given name
                    # in 4PS mode, we assume .bak with modified base app, so we push the password again as the standard user setup script would ignore this
                    if ($env:Auth -eq "aad") {
                        Set-NavServerUser -ServerInstance BC @tenantParam -Username $username -Password $securePassword -AuthenticationEMail $authenticationEMail
                    }
                    else {
                        Set-NavServerUser -ServerInstance BC @tenantParam -Username $username -Password $securePassword 
                    }
                }

                Write-Host "  Add Control Add-Ins"
                $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.BusinessChart' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\BusinessChart\Microsoft.Dynamics.Nav.Client.BusinessChart.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.FlowIntegration' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\FlowIntegration\Microsoft.Dynamics.Nav.Client.FlowIntegration.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.OAuthIntegration' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\OAuthIntegration\Microsoft.Dynamics.Nav.Client.OAuthIntegration.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.PageReady' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\PageReady\Microsoft.Dynamics.Nav.Client.PageReady.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.PowerBIManagement' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\PowerBIManagement\Microsoft.Dynamics.Nav.Client.PowerBIManagement.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.RoleCenterSelector' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\RoleCenterSelector\Microsoft.Dynamics.Nav.Client.RoleCenterSelector.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.SatisfactionSurvey' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\SatisfactionSurvey\Microsoft.Dynamics.Nav.Client.SatisfactionSurvey.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.VideoPlayer' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\VideoPlayer\Microsoft.Dynamics.Nav.Client.VideoPlayer.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.WebPageViewer' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\WebPageViewer\Microsoft.Dynamics.Nav.Client.WebPageViewer.zip" -ErrorAction SilentlyContinue
                New-NAVAddin -ServerInstance BC -AddinName 'Microsoft.Dynamics.Nav.Client.WelcomeWizard' -PublicKeyToken 31bf3856ad364e35 -ResourceFile "$serviceTierFolder\Add-ins\WelcomeWizard\Microsoft.Dynamics.Nav.Client.WelcomeWizard.zip" -ErrorAction SilentlyContinue
                Restart-NAVServerInstance BC
                
                $timespent4PS = [Math]::Round([DateTime]::Now.Subtract($startTime4PS).Totalseconds)
                Write-Host "  4PS initialization took $timespent4PS seconds"
            }
        }
    }
}

Export-ModuleMember -Function Invoke-4PSArtifactHandling
