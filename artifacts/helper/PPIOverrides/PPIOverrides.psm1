$script:DynamicParameters = @{}

function Get-DynamicParameters() {
    Param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.CommandInfo]$TargetCommand,
        [Parameter(ParameterSetName = "SourceCommand", Mandatory = $true)]
        [System.Management.Automation.CommandInfo]$SourceCommand,
        [Parameter(ParameterSetName = "SourceCommandName", Mandatory = $true)]
        [string]$SourceCommandName,
        [Parameter(ParameterSetName = "SourceParameters", Mandatory = $true)]
        [hashtable]$SourceParameters
    )

    $key = '{0}\{1}' -f $TargetCommand.ModuleName, $TargetCommand.Name
    
    if (! $script:DynamicParameters.ContainsKey($key)) {
        if ($SourceCommandName) {
            $SourceCommand = Get-Command $SourceCommandName
        }
        if ($SourceCommand) {
            $sourceParams = $SourceCommand.Parameters
        }
        if ($SourceParameters) {
            $sourceParams = $SourceParameters
        }
        if (! $sourceParams) {
            throw "Source parameters not defined or found"
            return
        }

        $script:DynamicParameters[$key] = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        function _cmdlet_() { [cmdletbinding()]Param() }
        $excludeParams = @((Get-Command _cmdlet_).Parameters.Values.Name)

        foreach ($sourceParam in $sourceParams.Values) {
            if ($sourceParam.Name -in $excludeParams) {
                continue
            }

            $sourceParamType = [type]"System.Object"
            try {
                if ($sourceParam.ParameterType.ToString() -like 'System.*') {
                    $sourceParamType = [type]($sourceParam.ParameterType)
                }
            }
            catch {}

            $targetParam = New-Object System.Management.Automation.RuntimeDefinedParameter(
                $sourceParam.Name,
                $sourceParamType,
                $sourceParam.Attributes
            )

            $targetParamAttribute = $targetParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] } | Select-Object -First 1
            if (!$targetParamAttribute) {
                $targetParamAttribute = New-Object System.Management.Automation.ParameterAttribute
                $targetParamAttribute.ParameterSetName = "__AllParameterSets"
                $targetParam.Attributes.Add($targetParamAttribute)
            }

            $script:DynamicParameters[$key].Add($targetParam.Name, $targetParam)
        }
    }
    return $script:DynamicParameters[$key]
}

. (Join-Path $PSScriptRoot "Invoke-WebRequest.ps1")
. (Join-Path $PSScriptRoot "Expand-Archive.ps1")

. (Join-Path $PSScriptRoot "NavAppManagement.ps1")