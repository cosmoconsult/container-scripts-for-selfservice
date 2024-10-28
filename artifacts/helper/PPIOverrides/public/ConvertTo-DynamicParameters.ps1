$script:DynamicParameters = @{}

function ConvertTo-DynamicParameters() {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        [hashtable]$Parameters = $null
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
                if ($param.ParameterType.ToString() -like 'System.*') {
                    $dynamicParamType = [type]($param.ParameterType)
                }
            }
            catch {}

            $dynamicParam = New-Object System.Management.Automation.RuntimeDefinedParameter(
                $param.Name,
                $dynamicParamType,
                $param.Attributes
            )

            $dynamicParamParameterAttribute = $dynamicParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1
            if (!$dynamicParamParameterAttribute) {
                $dynamicParamParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
                $dynamicParamParameterAttribute.ParameterSetName = "__AllParameterSets"
                $dynamicParam.Attributes.Add($dynamicParamParameterAttribute)
            }

            $script:DynamicParameters[$commandKey].Add($dynamicParam.Name, $dynamicParam)
        }
    }
    return $script:DynamicParameters[$commandKey]
}
Export-ModuleMember -Function ConvertTo-DynamicParameters