# Import PPI Powershell Core Utils
if (! (Get-Module 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -Global -Force
}

$script:PwshCoreOverrideInfos = @{}
$script:PwshCoreOverrideParameters = @{}

function Export-PwshCoreOverride() {
    [CmdletBinding(DefaultParameterSetName = 'ModuleImportPath')]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [Parameter(Mandatory)]
        [string]$ModuleName,
        [Parameter(ParameterSetName = 'ModuleImportPath', Mandatory)]
        [string]$ModuleImportPath,
        [Parameter(ParameterSetName = 'ModuleImportScriptBlock', Mandatory)]
        [scriptblock]$ModuleImportScriptBlock,

        [bool]$UseRemoteSession = $true
    )

    begin {
        if ($UseRemoteSession) {
            Write-Verbose "Exporting $CommandName with PowerShell Core remote session."
        }
        else {
            Write-Verbose "Exporting $CommandName with PowerShell Core direct execution."
            # Validate that PowerShell Core (pwsh) is available up front for the BC28+ path
            try {
                Get-Command pwsh -ErrorAction Stop | Out-Null
            }
            catch {
                throw "PowerShell Core ('pwsh') is required but was not found. Ensure that PowerShell Core is installed and 'pwsh' is available on PATH."
            }
        }

        $scriptBlock = {
            [CmdletBinding()]
            param()

            dynamicparam {
                $overrideInfo = $script:PwshCoreOverrideInfos[$MyInvocation.MyCommand.Name]

                if ($overrideParameters = $script:PwshCoreOverrideParameters[$MyInvocation.MyCommand.Name]) {
                    return $overrideParameters
                }

                $pwshCoreParameters = @{}
                $pwshCoreParametersScriptBlock = {
                    param($OverrideInfo)
                    if (! (Get-Module $OverrideInfo.ModuleName)) {
                        if ($OverrideInfo.ModuleImportPath) {
                            Import-Module $OverrideInfo.ModuleImportPath -wa SilentlyContinue
                        }
                        else {
                            . ( [ScriptBlock]::create($OverrideInfo.ModuleImportScriptBlock) )
                        }
                    }
                    # Get parameters and their attributes for the command
                    (Get-Command $OverrideInfo.CommandName).Parameters.Values | Select-Object -Property *
                }

                Invoke-CommandInPwshCore `
                    -ScriptBlock $pwshCoreParametersScriptBlock `
                    -ArgumentList $overrideInfo `
                    -UseRemoteSession $overrideInfo.UseRemoteSession |
                    ForEach-Object {
                        $pwshCoreParameters[$_.Name] = $_
                    }

                return $script:PwshCoreOverrideParameters[$MyInvocation.MyCommand.Name] = ConvertTo-DynamicParameters -CommandName $overrideInfo.CommandName -Parameters $pwshCoreParameters
            }

            begin {
                $MyInvocation.MyCommand.Parameters.Values | Where-Object { ! $_.IsDynamic } | ForEach-Object {
                    $PSBoundParameters.Remove($_.Name) | Out-Null
                }
            }

            process {
                $overrideInfo = $script:PwshCoreOverrideInfos[$MyInvocation.MyCommand.Name]

                $pwshCoreScriptBlock = {
                    param($OverrideInfo, $Parameters)
                    if (! (Get-Module $OverrideInfo.ModuleName)) {
                        if ($OverrideInfo.ModuleImportPath) {
                            Import-Module $OverrideInfo.ModuleImportPath -wa SilentlyContinue
                        }
                        else {
                            . ( [ScriptBlock]::create($OverrideInfo.ModuleImportScriptBlock) )
                        }
                    }

                    # Convert deserialized parameters
                    @( $Parameters.GetEnumerator() ) |
                        Where-Object { $_.Value -is [PSObject] } |
                        Where-Object { $_.Value.PSObject.TypeNames -like 'Deserialized.*' } |
                        ForEach-Object {
                            if ($_.Value.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.SwitchParameter') {
                                # Handle switch parameters specially since they lose their type and we just get a boolean value
                                $Parameters[$_.Name] = [switch]$_.Value.IsPresent
                            } else {
                                $Parameters[$_.Name] = $_.Value.ToString()
                            }
                        }

                    & $OverrideInfo.CommandName @Parameters | Select-Object -Property *
                }

                Invoke-CommandInPwshCore `
                    -ScriptBlock $pwshCoreScriptBlock `
                    -ArgumentList $overrideInfo, $PSBoundParameters `
                    -UseRemoteSession $overrideInfo.UseRemoteSession `
                    -ErrorAction $ErrorActionPreference `
                    -InformationAction $InformationPreference `
                    -WarningAction $WarningPreference `
                    -Verbose:($VerbosePreference -eq 'Continue')
            }
        }
    }

    process {
        $script:PwshCoreOverrideInfos[$CommandName] = @{
            ModuleName              = $ModuleName
            ModuleImportPath        = $ModuleImportPath
            ModuleImportScriptBlock = $ModuleImportScriptBlock
            CommandName             = '{0}\{1}' -f $ModuleName, $CommandName
            UseRemoteSession        = $UseRemoteSession
        }

        Set-Item -Path "function:script:$CommandName" -Value $scriptBlock
        Export-ModuleMember -Function $CommandName
    }
}