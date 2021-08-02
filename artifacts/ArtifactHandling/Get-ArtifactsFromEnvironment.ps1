function Get-ArtifactsFromEnvironment {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false, ValueFromPipelineByPropertyName=$true)]
        [Alias("FullName")]
        [string]$path = $null,
        [Parameter(Mandatory=$false)]
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }
    }
    
    process {
        if ("$env:AZURE_DEVOPS_PACKAGES" -eq "" -and "$env:AZURE_DEVOPS_ARTIFACTS" -eq "" -and "$env:TEST_APPS_MICROSOFT" -eq "") {
            Write-Host "not packages / artifacts found"
            $artifacts    = [System.Collections.ArrayList]@()
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

        $artifacts = @()
        try {
            if ("$env:AZURE_DEVOPS_PACKAGES" -ne "") {
                $packages  = "$env:AZURE_DEVOPS_PACKAGES".Split(@(',', ';'))
                Write-Host "Artifacts from AZURE_DEVOPS_PACKAGES ..."
                
                $packages | ForEach-Object {
                    $artifacts += @{
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
            if ("$env:AZURE_DEVOPS_ARTIFACTS" -ne "") 
            {
                Write-Host "Artifacts from AZURE_DEVOPS_ARTIFACTS ..."
                $base64       = "$env:AZURE_DEVOPS_ARTIFACTS"
                if ("$base64" -ne "") {
                    $artifactJson = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($base64))
                    if ("$artifactJson" -ne "" -and $artifactJson[0] -ne "{") {
                        $artifactJson = [System.Text.Encoding]::ASCII.GetString([System.Convert]::FromBase64String($base64))
                    }
                } else {
                    $artifactJson = '{"artifacts":[]}'
                }
                Write-Host "Artifacts: $artifactJson"
                $envArtifacts = ($artifactJson | ConvertFrom-Json -ErrorAction SilentlyContinue)
                $artifacts = $envArtifacts.artifacts
                if (! $artifacts) {
                    $artifacts = @()
                }
                if ($envArtifacts.devopsArtifacts) {
                    $artifacts += $envArtifacts.devopsArtifacts
                }
            }
            if ("$env:TEST_APPS_MICROSOFT" -ne "") 
            {
                Write-Host "Artifacts from TEST_APPS_MICROSOFT ..."
                $testApps  = "$env:AZURE_DEVOPS_PACKAGES".Split(@(',', ';'))
                
                $testApps | ForEach-Object {
                    $artifacts += @{
                        name = "Microsoft Tests - $_";
                        url = "c:\\Applications\\BaseApp\\Test\\Microsoft_Tests-$_.app";
                        target = "app";
                    }
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