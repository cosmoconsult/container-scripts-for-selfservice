$script:DynamicParameters = @{}

function Get-DynamicParameters() {
    Param(
        [Parameter(Mandatory = $true)]
        [object]$TargetCommand = $null,
        [object]$SourceCommand = $null,
        [string]$SourceCommandName = $null,
        [scriptblock]$SourceParamsScript = $null
    )

    $key = '{0}\{1}' -f $TargetCommand.ModuleName, $TargetCommand.Name
    
    if (! $script:DynamicParameters.ContainsKey($key)) {
        if ($SourceCommandName) {
            $SourceCommand = Get-Command $SourceCommandName
        }
        if ($SourceCommand) {
            $sourceParams = $SourceCommand.Parameters
        } elseif($SourceParamsScript) {
            $sourceParams = & $SourceParamsScript
        }

        if (! $sourceParams) {
            throw "Source parameters not defined or found"
        }

        $script:DynamicParameters[$key] = New-Object System.Management.Automation.RuntimeDefinedParameterDictionary

        function _cmdlet_() { [cmdletbinding()]Param() }
        $excludeParams = @((Get-Command _cmdlet_).Parameters.Values.Name)

        foreach ($sourceParam in $SourceParams.Values) {
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

function Import-Module([string]$Name) {
    # Must be a simple function for correct splatting
    if ($Name -notin @($MyInvocation.MyCommand.Modul.Name, $MyInvocation.MyCommand.Modul.Path)) {
        Microsoft.PowerShell.Core\Import-Module -Name $Name @args -Global
    }
}

. (Join-Path $PSScriptRoot "Invoke-WebRequest.ps1")
. (Join-Path $PSScriptRoot "Expand-Archive.ps1")

. (Join-Path $PSScriptRoot "NavAppManagement.ps1")