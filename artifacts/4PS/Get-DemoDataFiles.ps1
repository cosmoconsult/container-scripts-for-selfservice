function Get-DemoDataFiles {
    [cmdletbinding()]
    PARAM
    (
    )
    PROCESS {
        $files = @()
        if (Test-Path -Path "c:\demodata") {
            $files = Get-ChildItem "c:\demodata" -Filter *.xml |
            Where-Object { 
                if ($env:IsBuildContainer -and !$_.Name.Contains('Test Automation')) {
                    "Skipping XML file {0} as it's no Test Automation database and it seems to be a build container" -f $_.FullName | Write-Host
                    return $false;
                }
                return $true;
            } | Sort-Object Name -Descending
        }

        if ($files.Count -gt 0) {
            return $files
        }

        $resolvedArtifacts = @()
        if ($global:cosmoArtifacts -and $global:cosmoArtifacts.Artifacts -and $global:cosmoArtifacts.Artifacts.All) {
            $resolvedArtifacts = @($global:cosmoArtifacts.Artifacts.All | Where-Object { $_.target -eq 'demodata' })
        }
        
        $files = $resolvedArtifacts |
            ForEach-Object {
                [pscustomobject]@{
                    Name = $_.name
                    FullName = "resolved://demodata/$($_.name)"
                    AssetName = $_.name
                    Artifact = $_
                }
            } |
            Where-Object {
                if ($env:IsBuildContainer -and !$_.Name.Contains('Test Automation')) {
                    "Skipping demo data artifact {0} as it's no Test Automation database and it seems to be a build container" -f $_.Name | Write-Host
                    return $false
                }
                return $true
            } |
            Sort-Object Name -Descending

        return $files
    }

}

Export-ModuleMember -Function Get-DemoDataFiles