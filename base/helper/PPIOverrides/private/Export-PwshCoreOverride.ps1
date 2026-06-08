# Import PPI Powershell Core Utils
if (! (Get-Module 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -Global -Force
}

$script:PwshCoreOverrides = @{}

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
        [scriptblock]$ModuleImportScriptBlock
    )

    begin {
        $scriptBlock = {
            [CmdletBinding()]
            param()

            dynamicparam {
                $override = $script:PwshCoreOverrides[$MyInvocation.MyCommand.Name]
                $pwshCoreSession = Request-PwshCoreSession
                if (!$pwshCoreSession) { return }
                $overwrittenParameters = @{}
                Invoke-Command -Session $pwshCoreSession -ScriptBlock {
                    if (! (Get-Module $using:override.ModuleName)) {
                        if ($using:override.ModuleImportPath) {
                            Import-Module $using:override.ModuleImportPath -wa SilentlyContinue
                        }
                        else {
                            . ( [ScriptBlock]::create($using:override.ModuleImportScriptBlock) )
                        }
                    }
                    # Get parameters and their attributes for the command
                    (Get-Command $using:override.CommandName).Parameters.Values | Select-Object -Property *
                } | ForEach-Object {
                    $overwrittenParameters[$_.Name] = $_;
                } | Out-Null
                ConvertTo-DynamicParameters -CommandName $override.CommandName -Parameters $overwrittenParameters
            }

            begin {
                $MyInvocation.MyCommand.Parameters.Values | Where-Object { ! $_.IsDynamic } | ForEach-Object {
                    $PSBoundParameters.Remove($_.Name) | Out-Null
                }
            }

            process {
                $override = $script:PwshCoreOverrides[$MyInvocation.MyCommand.Name]
                $pwshCoreSession = Request-PwshCoreSession
                if (!$pwshCoreSession) { return }
                Invoke-Command -Session $pwshCoreSession -ScriptBlock {
                    if (! (Get-Module $using:override.ModuleName)) {
                        if ($using:override.ModuleImportPath) {
                            Import-Module $using:override.ModuleImportPath -wa SilentlyContinue
                        }
                        else {
                            . ( [ScriptBlock]::create($using:override.ModuleImportScriptBlock) )
                        }
                    }

                    # Convert deserialized parameters to string
                    $parameters = $using:PSBoundParameters
                    @( $parameters.GetEnumerator() ) |
                    Where-Object { $_.Value -is [PSObject] } |
                    Where-Object { $_.Value.PSObject.TypeNames -match '^Deserialized\.' } |
                    ForEach-Object { $parameters[$_.Name] = $_.Value.ToString() }

                    & $using:override.CommandName @parameters | Select-Object -Property *
                }
            }
        }
    }

    process {
        $script:PwshCoreOverrides[$CommandName] = @{
            ModuleName              = $ModuleName
            ModuleImportPath        = $ModuleImportPath
            ModuleImportScriptBlock = $ModuleImportScriptBlock
            CommandName             = '{0}\{1}' -f $ModuleName, $CommandName
        }

        Set-Item -Path "function:script:$CommandName" -Value $scriptBlock
        Export-ModuleMember -Function $CommandName
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
                    [Parameter(Mandatory = $false, ValueFromRemainingArguments)]
                    $NotMappedArgs # Unused parameter to allow passing all args to pwsh without binding issues
                )

                dynamicparam {
                    # Get the function name from the enclosing scope
                    $targetFunction = $MyInvocation.MyCommand.Name

                    # Create a dynamic parameter dictionary
                    $paramDict = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

                    # Build parameters from the stored function info
                    $commonParameters = [System.Management.Automation.PSCmdlet]::CommonParameters + [System.Management.Automation.PSCmdlet]::OptionalCommonParameters
                    $global:functionParams[$targetFunction].Values | Where-Object { $_.Name -notin $commonParameters } | ForEach-Object {
                        $paramInfo = $_

                        $attributes = New-Object System.Collections.ObjectModel.Collection[System.Attribute]

                        $paramAttr = New-Object System.Management.Automation.ParameterAttribute
                        $attributes.Add($paramAttr)
                        foreach ($alias in $paramInfo.Aliases) {
                            $attributes.Add([System.Management.Automation.AliasAttribute]::new($alias))
                        }

                        <#
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
                        #>
                        $paramType = try { [Type]($paramInfo.ParameterType) } catch { [Type]::GetType('System.String') }

                        $runtimeParam = New-Object System.Management.Automation.RuntimeDefinedParameter(
                            $paramInfo.Name,
                            $paramType,
                            $attributes
                        )

                        $paramDict.Add($paramInfo.Name, $runtimeParam)
                    }

                    return $paramDict
                }

                process {
                    if ($NotMappedArgs -and @($NotMappedArgs).Count -gt 0) {
                        Write-Warning "Arguments '$($NotMappedArgs -join ' ')' are not mapped to the wrapper function. Ensure that these parameters are defined in the target function for proper handling."
                    }
                    $targetFunction = $MyInvocation.MyCommand.Name

                    # Prevent the wrapper's catch-all parameter from being forwarded.
                    if ($PSBoundParameters.ContainsKey('NotMappedArgs')) {
                        $PSBoundParameters.Remove('NotMappedArgs') | Out-Null
                    }

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

                        Write-Verbose "[$cmdName] Invoke Prompt"
                        c:\run\prompt.ps1 -silent

                        $command = Get-Command $cmdName -ErrorAction Stop

                        # Convert JSON object to hashtable for splatting
                        $ht = @{}
                        $params.PSObject.Properties | ForEach-Object {
                            $name = $_.Name
                            $value = $_.Value
                            $parameterType = $command.Parameters[$name].ParameterType

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
                                # Common JSON serialization pattern for wrapped scalar types: @{ Value = ... }
                                if (
                                    $value -is [PSCustomObject] -and
                                    $value.PSObject.Properties.Count -eq 1 -and
                                    $value.PSObject.Properties['Value']
                                ) {
                                    $value = $value.Value
                                }

                                if ($parameterType) {
                                    try {
                                        $ht[$name] = [System.Management.Automation.LanguagePrimitives]::ConvertTo($value, $parameterType)
                                    }
                                    catch {
                                        Write-Verbose "[$cmdName] Could not convert parameter '$name' to type '$($parameterType.FullName)'. Using raw value. Error: $($_.Exception.Message)"
                                        $ht[$name] = $value
                                    }
                                }
                                else {
                                    $ht[$name] = $value
                                }
                            }
                        }

                        Write-Verbose "[$cmdName] Reconstructed Parameters: $($ht | ConvertTo-Json -Compress)"

                        . c:\run\prompt.ps1 -silent
                        & $cmdName @ht
                    } -args $paramsJson, $targetFunction
                }
            }.GetNewClosure()

            # Create the function in the global scope
            Set-Item -Path "function:global:$FunctionName" -Value $scriptBlock
        }

        function Get-FunctionSignatures {
            param(
                [String[]]$functionNames
            )
            $xmlPath = "C:\run\my\functionSignatures.xml"
            if (-not (Test-Path $xmlPath)) {
                pwsh -NoProfile -c {
                    param([string]$xmlPath, [string[]]$functionNames)
                    C:\run\prompt.ps1 -silent
                    $functionNames | Get-Command | Export-Clixml -Path $xmlPath
                } -args $xmlPath, $functionNames
            }
            $Signatures = Import-Clixml -Path $xmlPath
            if ( $Signatures.Count -eq 0) {
                throw "Failed to retrieve function signatures for $($functionNames -join ', '). Ensure that the target functions exist and are accessible in the PowerShell Core session."
            }
            return $Signatures
        }
    }
    process {
        $functionNames = $commandNames
        # Collect parameters for all functions we want to wrap

        $global:functionParams = @{}
        $Signatures = Get-FunctionSignatures -functionNames $functionNames
        Write-Host "Retrieved function signatures for: $($Signatures.Name -join ', ')"
        foreach ($functionName in $functionNames) {
            $global:functionParams[$functionName] = $Signatures | Where-Object { $_.Name -eq $functionName } | Select-Object -ExpandProperty Parameters
        }

        # Create wrapper functions for all target functions
        foreach ($functionName in $functionNames) {
            if ($global:functionParams[$functionName]) {
                Write-Host "Creating wrapper for $functionName"
                New-PwshCoreWrapper -FunctionName $functionName
            }
        }
    }
}