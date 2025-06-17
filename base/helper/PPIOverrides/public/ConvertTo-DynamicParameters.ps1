$script:DynamicParameters = @{}

function ConvertTo-DynamicParameters() {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [object]$Parameters = $null
    )
    $commandKey = $CommandName
    
    if (! $script:DynamicParameters.ContainsKey($commandKey)) {
        $params = $Parameters
        if (! $params) {
            $params = (Get-Command $CommandName).Parameters
        }
        if (! $params) {
            throw ("Parameters not found for command: {0}" -f $CommandName)
            return
        }

        $script:DynamicParameters[$commandKey] = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        function _cmdlet_() { [cmdletbinding()]Param() }
        $excludedParams = @((Get-Command _cmdlet_).Parameters.Values.Name)

        foreach ($param in $params.Values) {
            if ($param.Name -in $excludedParams) {
                continue
            }

            $dynamicParamType = [type]"System.Object"
            try {
                $dynamicParamType = [type]($param.ParameterType.ToString())
            } catch {}

            $dynamicParam = New-Object System.Management.Automation.RuntimeDefinedParameter(
                $param.Name,
                $dynamicParamType,
                ( $param.Attributes | Where-Object { $_ -is [System.Attribute] } )
            )

            # Add deserialized parameter attributes
            $param.Attributes | Where-Object { $_ -is [PSObject] } | Where-Object { $_.TypeId -eq 'System.Management.Automation.ParameterAttribute' } | ForEach-Object {
                $paramAttribute = $_
                $dynamicParamParameterAttribute = New-Object $paramAttribute.TypeId
                $dynamicParamParameterAttribute.PSObject.Properties | 
                    Where-Object { $_.IsSettable } | 
                    ForEach-Object {
                        if ($paramAttribute.$($_.Name)) {
                            $_.Value = $paramAttribute.$($_.Name)
                        }
                    }
                $dynamicParam.Attributes.Add($dynamicParamParameterAttribute)
            }

            # Add fallback parameter attribute
            $dynamicParamParameterAttribute = $dynamicParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1
            if (!$dynamicParamParameterAttribute) {
                $dynamicParamParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
                $dynamicParamParameterAttribute.ParameterSetName = "__AllParameterSets"
                $dynamicParam.Attributes.Add($dynamicParamParameterAttribute)
            }

            # Add aliases
            if ($param.Aliases) {
                $dynamicParamAliasAttribute = $dynamicParam.Attributes | Where-Object { $_ -is [System.Management.Automation.AliasAttribute] } | Select-Object -First 1
                if (! $dynamicParamAliasAttribute) {
                    $dynamicParamAliasAttribute = New-Object System.Management.Automation.AliasAttribute($param.Aliases)
                    $dynamicParam.Attributes.Add($dynamicParamAliasAttribute)
                }
            }

            $script:DynamicParameters[$commandKey].Add($dynamicParam.Name, $dynamicParam)
        }
    }
    return $script:DynamicParameters[$commandKey]
}
Export-ModuleMember -Function ConvertTo-DynamicParameters