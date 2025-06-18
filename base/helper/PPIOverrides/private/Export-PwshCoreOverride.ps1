# Import PPI Powershell Core Utils
if (! (Get-Module 'PPIPowershellCoreUtils')) {
    Import-Module "c:\run\helper\PPIPowershellCoreUtils\PPIPowershellCoreUtils.psm1" -Global -Force
}

$script:PwshCoreOverrides = @{}

function Export-PwshCoreOverride() {
    [CmdletBinding(DefaultParameterSetName = 'ModuleImportPath')]
    Param(
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
            Param()
    
            DynamicParam {
                $override = $script:PwshCoreOverrides[$MyInvocation.MyCommand.Name]
                $pwshCoreSession = Request-PwshCoreSession
                if (!$pwshCoreSession) { return }
                $overwrittenParameters = @{}
                Invoke-Command -Session $pwshCoreSession -ScriptBlock {
                    if (! (Get-Module $using:override.ModuleName)) {
                        if ($using:override.ModuleImportPath) {
                            Import-Module $using:override.ModuleImportPath -wa SilentlyContinue
                        } else {
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
                $MyInvocation.MyCommand.Parameters.Values | Where-Object { ! $_.IsDynamic } | Foreach-Object {
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
                        } else {
                            . ( [ScriptBlock]::create($using:override.ModuleImportScriptBlock) )
                        }
                    }

                    $parameters = Convert-DeserializedParameters -Parameters $using:PSBoundParameters

                    & $using:override.CommandName @parameters | Select-Object -Property *
                }
            }
        }
    }

    process {
        $script:PwshCoreOverrides[$CommandName] = @{ 
            ModuleName = $ModuleName
            ModuleImportPath = $ModuleImportPath
            ModuleImportScriptBlock = $ModuleImportScriptBlock
            CommandName = '{0}\{1}' -f $ModuleName, $CommandName
        }

        Set-Item -Path "function:script:$CommandName" -Value $scriptBlock
        Export-ModuleMember -Function $CommandName
    }
}

function Convert-DeserializedParameters() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )
    
    @( $Parameters.GetEnumerator() ) | 
        Where-Object { $_.Value -is [PSObject] } | 
        Where-Object { $_.Value.PSObject.TypeNames -match '^Deserialized\.' } |
        ForEach-Object { $Parameters[$_.Name] = $_.Value.ToString() }

    return $Parameters
}