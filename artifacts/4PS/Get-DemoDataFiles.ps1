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

        return $files
    }

}

Export-ModuleMember -Function Get-DemoDataFiles