function Get-ArtifactsFromEnvironment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
        [Alias("FullName")]
        [string]$path = $null,
        [Parameter(Mandatory = $false)]
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
    }
    
    process {
        $artifacts = [System.Collections.ArrayList]@()

        if (-not $env:IsBuildContainer) {
            Write-Host "Adding AL-Test-Runner app as default app artifact"
            $bcMajorVersion = Get-BcMajorVersion
            if ($bcMajorVersion -ge 22) {
                $testRunnerUrl = "https://cosmoalpaca.blob.core.windows.net/cosmoalpaca/James%20Pearson_Test%20Runner%20Service.zip?sp=r&st=2025-02-14T08:40:03Z&se=2999-02-14T16:40:03Z&spr=https&sv=2022-11-02&sr=b&sig=DpVpYH88eAF4UCQfKw3e1dMUI75bshubC9ygJh4Jous%3D"
            } elseif ($bcMajorVersion -ge 15) {
                $testRunnerUrl = "https://cosmoalpaca.blob.core.windows.net/cosmoalpaca/James%20Pearson_Test%20Runner%20Service_pre22.zip?sp=r&st=2025-02-14T08:40:18Z&se=2999-02-14T16:40:18Z&spr=https&sv=2022-11-02&sr=b&sig=swgRlSaRzQYABMYNjyhmyVnNVxv4nZkxhRkI3tmL5gs%3D"
            }
            $artifacts += [PSCustomObject]@{
                name = "AL Test Runner"
                url = $testRunnerUrl
                type = "app"
            }
        }
        

        if ("$env:AZURE_DEVOPS_PACKAGES" -eq "" -and (-not $global:extendedEnv.AzureDevOpsArtifacts)) {
            Write-Host "not packages / artifacts found"
            if (("$path" -ne "") -and (Test-Path "$path")) {
                $artifactJson = (Get-Content $path -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue)
                if ($artifactJson.artifacts) {
                    $artifacts.AddRange($artifactJson.artifacts)
                }
                if ($artifactJson.devopsArtifacts) {
                    $artifacts.AddRange($artifactJson.devopsArtifacts)
                }   
            }
            return $artifacts
        }

        try {
            if ("$env:AZURE_DEVOPS_PACKAGES" -ne "") {
                $packages = "$env:AZURE_DEVOPS_PACKAGES".Split(@(',', ';'))
                Write-Host "Artifacts from AZURE_DEVOPS_PACKAGES ..."
                
                $packages | ForEach-Object {
                    $artifacts += [PSCustomObject]@{
                        name         = "$_";
                        organization = "$($env:AZURE_DEVOPS_ORGANIZATION)";
                        project      = "$($env:AZURE_DEVOPS_PROJECT)";
                        scope        = "$($env:AZURE_DEVOPS_ARTIFACT_SCOPE)";
                        feed         = "$($env:AZURE_DEVOPS_ARTIFACT_FEED)";
                        view         = "$($env:AZURE_DEVOPS_ARTIFACT_VIEW)";
                        url          = "$($env:AZURE_DEVOPS_ARTIFACT_URL)";
                        type         = "upack";
                    }
                }
            } 
            if ($global:extendedEnv.AzureDevOpsArtifacts) {
                Write-Host "Artifacts from AZURE_DEVOPS_ARTIFACTS ..."
                $base64 = $global:extendedEnv.AzureDevOpsArtifacts
                if ("$base64" -ne "") {
                    $artifactJson = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($base64))
                    if ("$artifactJson" -ne "" -and $artifactJson[0] -ne "{") {
                        $artifactJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($base64))
                    }
                }
                else {
                    $artifactJson = '{"artifacts":[]}'
                }

                Write-Host "Artifacts: $artifactJson"
                $envArtifacts = ($artifactJson | ConvertFrom-Json -ErrorAction SilentlyContinue)
                if ($envArtifacts.artifacts) {
                    $artifacts.AddRange($envArtifacts.artifacts)
                }
                if ($envArtifacts.devopsArtifacts) {
                    $artifacts.AddRange($envArtifacts.devopsArtifacts)
                }

                if ($env:IsBuildContainer) {
                    $artifacts = $artifacts | Where-Object { -not ($_.ignorein -contains "build") }
                }
                else {
                    $artifacts = $artifacts | Where-Object { -not ($_.ignorein -contains "dev") }
                }
            }
        }
        catch {
            Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient
        }
        return $artifacts        
    }
    
    end {
        Write-Host "$($artifacts.Count) Artifact(s) found."
    }
}
Export-ModuleMember -Function Get-ArtifactsFromEnvironment