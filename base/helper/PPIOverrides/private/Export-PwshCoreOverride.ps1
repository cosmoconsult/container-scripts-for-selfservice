# Import PPI Powershell Core Utils
if (! (Get-Module 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -Global -Force
}

$script:PwshCoreOverrideInfos = @{}

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
                $pwshCoreParameters = @()
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
                if ($overrideInfo.UseRemoteSession) {
                    $pwshCoreSession = Request-PwshCoreSession
                    if (!$pwshCoreSession) { return }
                    $pwshCoreParameters = @(Invoke-Command -Session $pwshCoreSession -ScriptBlock $pwshCoreParametersScriptBlock -ArgumentList $overrideInfo)
                } else {
                    $pwshCoreParameters = Invoke-Pwsh -ScriptBlock $pwshCoreParametersScriptBlock -ArgumentList $overrideInfo
                }

                $overwrittenParameters = @{}
                foreach ($pwshCoreParameter in $pwshCoreParameters) {
                    $overwrittenParameters[$pwshCoreParameter.Name] = $pwshCoreParameter
                }
                ConvertTo-DynamicParameters -CommandName $overrideInfo.CommandName -Parameters $overwrittenParameters
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
                if ($overrideInfo.UseRemoteSession) {
                    $pwshCoreSession = Request-PwshCoreSession
                    if (!$pwshCoreSession) { return }
                    Invoke-Command -Session $pwshCoreSession -ScriptBlock $pwshCoreScriptBlock -ArgumentList $overrideInfo, $PSBoundParameters
                } else {
                    Invoke-Pwsh -ScriptBlock $pwshCoreScriptBlock -ArgumentList $overrideInfo, $PSBoundParameters
                }
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

function Invoke-Pwsh {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ScriptBlock]$ScriptBlock,
        [object[]]$ArgumentList
    )

    pwsh -NoProfile -c {
        param($ScriptBlock, $ArgumentList)
        $InformationPreference = "Continue"
        $WarningPreference = "Continue"
        $VerbosePreference = "Continue"
        $ErrorActionPreference = "Continue"

        . ( [ScriptBlock]::create($ScriptBlock) ) @ArgumentList *>&1
    } -Args $ScriptBlock, $ArgumentList 2>&1 |
        ForEach-Object {
            if ($_ -isnot [PSObject]) { return $_ }
            elseif ($_ -is [System.Management.Automation.ErrorRecord])                                       { Write-Error $_ }
            elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.ErrorRecord')       { Write-Error $_ }
            elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.WarningRecord')     { Write-Warning $_ }
            elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.VerboseRecord')     { Write-Verbose $_ }
            elseif ($_.PSObject.TypeNames -eq 'Deserialized.System.Management.Automation.InformationRecord') { Write-Host $_ }
            else { return $_ }
        }
}

function Invoke-PwshOverwriting {
    param(
        [string[]]$commandNames
    )
    begin {
        function New-PwshCoreWrapper {
            # Generic function factory
            param(
                [string]$FunctionName
            )

            $scriptBlock = {
                [CmdletBinding()]
                param(
                    [Parameter(ValueFromRemainingArguments)]
                    $RemainingArgs # Unused parameter to allow passing all args to pwsh without binding issues
                )

                dynamicparam {
                    # Get the function name from the enclosing scope
                    $targetFunction = $MyInvocation.MyCommand.Name

                    # Create a dynamic parameter dictionary
                    $paramDict = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

                    # Build parameters from the stored function info
                    $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
                    $functionParams[$targetFunction].Values | Where-Object { $_.Name -notin $commonParameters } | ForEach-Object {
                        $paramInfo = $_

                        $attributes = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

                        # Get all ParameterAttribute instances to support multiple parameter sets
                        $paramAttributes = $paramInfo.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }

                        if ($paramAttributes) {
                            # Add each parameter set definition
                            foreach ($paramAttr in $paramAttributes) {
                                $newParamAttr = New-Object System.Management.Automation.ParameterAttribute
                                $newParamAttr.Mandatory = $paramAttr.Mandatory
                                $newParamAttr.Position = $paramAttr.Position
                                $newParamAttr.ParameterSetName = $paramAttr.ParameterSetName
                                $newParamAttr.ValueFromPipeline = $paramAttr.ValueFromPipeline
                                $newParamAttr.ValueFromPipelineByPropertyName = $paramAttr.ValueFromPipelineByPropertyName
                                $newParamAttr.ValueFromRemainingArguments = $paramAttr.ValueFromRemainingArguments
                                $attributes.Add($newParamAttr)
                            }
                        }
                        else {
                            # No explicit ParameterAttribute, create a default one
                            $paramAttr = New-Object System.Management.Automation.ParameterAttribute
                            $attributes.Add($paramAttr)
                        }

                        # Add other attributes (ValidateSet, ValidateRange, etc.)
                        $paramInfo.Attributes | Where-Object { $_ -isnot [System.Management.Automation.ParameterAttribute] } | ForEach-Object {
                            $attributes.Add($_)
                        }

                        $runtimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter(
                            $paramInfo.Name,
                            $paramInfo.ParameterType,
                            $attributes
                        )
                        $paramDict.Add($paramInfo.Name, $runtimeParam)
                    }

                    return $paramDict
                }

                process {
                    $targetFunction = $MyInvocation.MyCommand.Name

                    # Convert Version parameters to strings before serialization
                    $paramsToSerialize = @{}
                    foreach ($key in $PSBoundParameters.Keys) {
                        $value = $PSBoundParameters[$key]
                        if ($value -is [System.Version]) {
                            $paramsToSerialize[$key] = $value.ToString()
                            Write-Verbose "[$targetFunction] Converting Version parameter $key from [$($value.GetType().Name)] to string: $($value.ToString())"
                        }
                        else {
                            $paramsToSerialize[$key] = $value
                        }
                    }

                    Write-Verbose "[$targetFunction] Captured Parameters: $($paramsToSerialize | ConvertTo-Json -Compress)"

                    # Serialize parameters to JSON for passing to pwsh
                    $paramsJson = $paramsToSerialize | ConvertTo-Json -Compress -Depth 10

                    pwsh -NoProfile -c {
                        param([string]$jsonParams, [string]$cmdName)

                        Write-Verbose "[$cmdName] Received JSON: $jsonParams"
                        $params = $jsonParams | ConvertFrom-Json

                        # Convert JSON object to hashtable for splatting
                        $ht = @{}
                        $params.PSObject.Properties | ForEach-Object {
                            $name = $_.Name
                            $value = $_.Value

                            Write-Verbose "[$cmdName] Processing param: $name = $value (Type: $($value.GetType().FullName))"

                            # Automatically detect switch parameters by checking for IsPresent property
                            if ($value -is [PSCustomObject] -and $value.PSObject.Properties['IsPresent']) {
                                if ($value.IsPresent -eq $true) {
                                    Write-Verbose "  Switch param $name detected and set to true"
                                    $ht[$name] = $true
                                }
                            }
                            # Handle regular parameters
                            else {
                                $ht[$name] = $value
                            }
                        }

                        Write-Verbose "[$cmdName] Reconstructed Parameters: $($ht | ConvertTo-Json -Compress)"

                        . c:\run\prompt.ps1 -silent
                        & $cmdName @ht
                    } -args $paramsJson, $targetFunction
                }
            }.GetNewClosure()

            # Create the function in the script scope
            Set-Item -Path "function:script:$FunctionName" -Value $scriptBlock
        }

        # Ensure the module containing the target commands is loaded in the current session to retrieve parameter metadata
        if (! (Get-Module 'Microsoft.Dynamics.Nav.Management')) {
            Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service\Admin\NavAdminTool.ps1" | ForEach-Object { . $_ }
        }
    }
    process {
        $functionNames = $commandNames
        # Collect parameters for all functions we want to wrap

        $functionParams = @{}
        foreach ($functionName in $functionNames) {
            $functionParams[$functionName] = (Get-Command $functionName).Parameters
        }

        # Create wrapper functions for all target functions
        foreach ($functionName in $functionNames) {
            if ($functionParams[$functionName]) {
                Write-Host "Creating wrapper for $functionName"
                New-PwshCoreWrapper -FunctionName $functionName
            }
        }
    }
}