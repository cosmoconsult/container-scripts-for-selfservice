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
            Write-Host "Initializing BcContainerHelper config"
            $config = [pscustomobject]@{}
        }
    }

    process {
        Write-Host "Setting $Key"
        if ($config.PSObject.Properties.Name -contains $Key) {
            $config[$Key] = $Value
        } else {
            $config | Add-Member -MemberType NoteProperty -Name $Key -Value $Value
        }
    }

    end {
        Write-Host "Writing BcContainerHelper config to $Path"
        if (! (Test-Path $Path)) {
            New-Item -ItemType File -Path $Path -Force | Out-Null
        }
        $config | ConvertTo-Json | Set-Content $Path
    }
}
Export-ModuleMember -Function Set-BcContainerHelperConfig