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

            $dynamicParameter = ConvertTo-DynamicParameter -Parameter $param

            $script:DynamicParameters[$commandKey].Add($dynamicParameter.Name, $dynamicParameter)
        }
    }
    return $script:DynamicParameters[$commandKey]
}
Export-ModuleMember -Function ConvertTo-DynamicParameters