function Get-AppFilesSortedByDependencies {
    [CmdletBinding()]
    param(            
        [string] $Path,
        [string] $Filter  = "*.app",
        [string[]] $Exclude = @("*Test_*","*Tests_*"),        
        [bool] $Distinct = $true,
        [Parameter(Mandatory=$false)]
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
        $AllAppFiles = Get-ChildItem -LiteralPath "$Path" -Filter $Filter -Exclude $Exclude -Recurse $optionalParameters

        $AllApps = [System.Collections.ArrayList]@()
        foreach ($AppFile in $AllAppFiles) {
            try {
                $App = Get-NAVAppInfo -Path $AppFile.FullName 
                if ($Distinct) {
                    $olderApps = ($AllApps | where { $App.AppId -eq $_.AppId -and [System.Version]::Parse($App.Version) -ge [System.Version]::Parse($_.Version) })
                    foreach ($olderApp in $olderApps) { $AllApps.Remove($olderApp) }                    
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
            } catch {
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