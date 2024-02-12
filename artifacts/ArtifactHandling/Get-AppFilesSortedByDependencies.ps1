function Get-AppFilesSortedByDependencies {
    [CmdletBinding()]
    param(            
        [string] $Path,
        [string] $Filter = "*.app",
        [string[]] $ExcludeExpr = ".*Test_.*|.*Tests_.*",        
        [bool] $Distinct = $true,
        [Parameter(Mandatory = $false)]
        $Depth
    )
    
    begin {
        if (! (Get-Module -Name "Microsoft.Dynamics.Nav.Management")) {
            Write-Warning "Module Microsoft.Dynamics.Nav.Management not loaded"
        }

        function AddToDependencyTree() {
            param(
                [PSObject] $App,
                [PSObject[]] $DependencyArray,
                [PSObject[]] $AppCollection,
                [Int] $Order = 1
            )   
    
            foreach ($Dependency in $App.Dependencies) {
                $DependencyArray = AddToDependencyTree `
                    -App ($AppCollection | where AppId -eq $Dependency.AppId) `
                    -DependencyArray $DependencyArray `
                    -AppCollection $AppCollection `
                    -Order ($Order - 1)
            }
    
            if (-not($DependencyArray | where AppId -eq $App.AppId)) {
                $DependencyArray += $App
                try {
                    ($DependencyArray | where AppId -eq $App.AppId).ProcessOrder = $Order
                }
                catch { }
            }
            else {
                if (($DependencyArray | where AppId -eq $App.AppId).ProcessOrder -gt $Order) {
                    ($DependencyArray | where AppId -eq $App.AppId).ProcessOrder = $Order
                } 
            }
    
            $DependencyArray
        }
    }

    process {
        #Script execution
        #. (Join-Path $PSScriptRoot "GetDependencies_TestApps.ps1")

        if ($Path -eq "") {
            $Path = "C:\ProgramData\NavContainerHelper\DependencyApps"
        }
        $optionalParameters = @{}
        if ($Depth) {
            $optionalParameters["Depth"] = $Depth
        }
        Write-Host ("Seraching for apps excluding: {0}" -f $ExcludeExpr)
        $AllAppFiles = Get-ChildItem -LiteralPath "$Path" -Filter $Filter -Recurse @optionalParameters | Where { $_.Name -NotMatch $ExcludeExpr }

        $AllApps = [System.Collections.ArrayList]@()
        foreach ($AppFile in $AllAppFiles) {
            try {
                Write-Host "Processing $($AppFile.FullName)"
                $App = Get-NAVAppInfo -Path $AppFile.FullName 
                if ($Distinct) {
                    $equalApp = ($AllApps | Where-Object { $App.AppId -eq $_.AppId })
                    if ($null -ne $equalApp) {
                        Write-Host "Found equal app"
                        if ([System.Version]::Parse($App.Version) -gt [System.Version]::Parse($equalApp.Version)) {
                            Write-Host "Removed version $($equalApp.Version) as $($App.Version) is greater."
                            $AllApps.Remove($equalApp)
                        }
                        else {
                            Write-Host "Existing version $($equalApp.version) is greater than or equal to $($App.Version). Skipping this one."
                            continue;
                        }
                    }
                }
                $AllApps.Add([PSCustomObject]@{
                        AppId        = $App.AppId
                        Version      = $App.Version
                        Name         = $App.Name
                        Publisher    = $App.Publisher
                        ProcessOrder = 0                            
                        Dependencies = $App.Dependencies
                        Path         = $AppFile.FullName
                    }) | Out-Null # adding the returned index to PS-Return content
            }
            catch {
                Write-Warning "Got no AppInfo from $AppFile ... $_"
            }
        }
        
        $FinalResult = @()

        $AllApps | ForEach-Object {    
            $FinalResult = AddToDependencyTree -App $_ -DependencyArray $FinalResult -AppCollection $AllApps -Order $AllApps.Count
        }

        $FinalResult = $FinalResult | Sort-Object ProcessOrder

        return $FinalResult
    }
}
Export-ModuleMember -Function Get-AppFilesSortedByDependencies