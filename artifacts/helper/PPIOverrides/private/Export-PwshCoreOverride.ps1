$script:PwshCoreOverrides = @{}

function Export-PwshCoreOverride() {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Command
    )

    begin {
        $scriptBlock = {
            [CmdletBinding()]
            Param()
    
            DynamicParam {
                $override = $script:PwshCoreOverrides[$MyInvocation.MyCommand.Name]
                $pwshCoreSession = Request-PwshCoreSession
                if (!$pwshCoreSession) { return }
                $overwrittenParameters = Invoke-Command -Session $pwshCoreSession -ScriptBlock {
                    if (! (Get-Module $using:override.ModuleName)) {
                        Import-Module $using:override.ModulePath -wa SilentlyContinue
                    }
                    (Get-Command $using:override.CommandName).Parameters | Select-Object -Property *
                }
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
                        Import-Module $using:override.ModulePath -wa SilentlyContinue
                    }
                    & $using:override.CommandName @using:PSBoundParameters | Select-Object -Property *
                }
            }
        }
    }

    process {
        if (! $Command) { return }

        $overrideName = $Command.Name
        $script:PwshCoreOverrides[$overrideName] = @{ 
            ModuleName = $Command.ModuleName
            ModulePath = $Command.Module.Path
            CommandName = '{0}\{1}' -f $Command.ModuleName, $Command.Name
        }

        Set-Item -Path "function:script:$overrideName" -Value $scriptBlock
        Export-ModuleMember -Function $overrideName
    }
}