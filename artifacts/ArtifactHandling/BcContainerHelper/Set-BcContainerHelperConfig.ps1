function Set-BcContainerHelperConfig {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [string]$Key,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [object]$Value,

        [string]$Path
    )

    begin {
        if (! $Path) {
            $Path = "C:\ProgramData\BcContainerHelper\BcContainerHelper.config.json"
        }

        if (Test-Path $Path) {
            Write-Host "Reading BcContainerHelper config from $Path"
            $config = Get-Content $Path | ConvertFrom-Json
        } else {
            $config = [pscustomobject]@{}
        }
    }

    process {
        Write-Host "Setting $Key to $( $Value | ConvertTo-Json -Compress )"
        if ($config.PSObject.Properties.Name -contains $Key) {
            $config[$Key] = $Value
        } else {
            $config | Add-Member -MemberType NoteProperty -Name $Key -Value $Value
        }
    }

    end {
        Write-Host "Writing BcContainerHelper config to $Path"
        $Path | ConvertTo-Json | Set-Content $configFile
    }
}
Export-ModuleMember -Function Set-BcContainerHelperConfig