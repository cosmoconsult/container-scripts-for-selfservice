function ConvertTo-DynamicParameter() {
    Param(
        [Parameter(Mandatory)]
        [object]$Parameter
    )

    # Define type of dynamic parameter (fallback to System.Object if type is not recognized)
    try {
        $dynamicParameterType = [type]($Parameter.ParameterType.ToString())
    } catch {
        $dynamicParameterType = [type]"System.Object"
    }

    # Create dynamic parameter
    $dynamicParameter = New-Object System.Management.Automation.RuntimeDefinedParameter(
        $Parameter.Name,
        $dynamicParameterType,
        ( $Parameter.Attributes | Where-Object { $_ -is [System.Attribute] } )
    )

    # Add deserialized parameter attributes
    $Parameter.Attributes | Where-Object { $_ -is [PSObject] } | Where-Object { $_.TypeId.ToString() -eq 'System.Management.Automation.ParameterAttribute' } | ForEach-Object {
        $parameterAttribute = $_
        $dynamicParameterAttribute = New-Object $parameterAttribute.TypeId
        $dynamicParameterAttribute.PSObject.Properties |
            Where-Object { $_.IsSettable } |
            ForEach-Object {
                if ($parameterAttribute.$($_.Name)) {
                    $_.Value = $parameterAttribute.$($_.Name)
                }
            }
        $dynamicParameter.Attributes.Add($dynamicParameterAttribute)
    }

    # Add fallback parameter attribute
    $dynamicParameterAttribute = $dynamicParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1
    if (!$dynamicParameterAttribute) {
        $dynamicParameterAttribute = New-Object System.Management.Automation.ParameterAttribute
        $dynamicParameterAttribute.ParameterSetName = "__AllParameterSets"
        $dynamicParameter.Attributes.Add($dynamicParameterAttribute)
    }

    # Add aliases
    if ($Parameter.Aliases) {
        $dynamicParameterAttribute = $dynamicParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.AliasAttribute] } | Select-Object -First 1
        if (! $dynamicParameterAttribute) {
            $dynamicParameterAttribute = New-Object System.Management.Automation.AliasAttribute($Parameter.Aliases)
            $dynamicParameter.Attributes.Add($dynamicParameterAttribute)
        }
    }

    return $dynamicParameter
}
Export-ModuleMember -Function ConvertTo-DynamicParameter