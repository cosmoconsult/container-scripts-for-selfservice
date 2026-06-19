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
        if($ExcludeExpr) {
            Write-Host ("Searching for apps excluding: {0}" -f $ExcludeExpr)
        } else {
            Write-Host "Searching for apps"
        }
        $AllAppFiles = Get-ChildItem -LiteralPath "$Path" -Filter $Filter -Recurse @optionalParameters | Where-Object { [string]::IsNullOrEmpty($ExcludeExpr) -or ($_.Name -NotMatch $ExcludeExpr) }

        $AllApps = [System.Collections.ArrayList]@()
        $ApplicationAppId = ""
        foreach ($AppFile in $AllAppFiles) {
            try {
                $App = Get-NAVAppInfo -Path $AppFile.FullName
                $AppId = $App.AppId
                if ($App.Name -eq "Application") {
                    $ApplicationAppId = $App.AppId
                    $AppId = "00000000-0000-0000-0000-000000000000"
                }
                if ($Distinct) {
                    $equalApp = ($AllApps | Where-Object { $AppId -eq $_.AppId })
                    if ($null -ne $equalApp) {
                        if ([System.Version]::Parse($App.Version) -gt [System.Version]::Parse($equalApp.Version)) {
                            $AllApps.Remove($equalApp)
                        }
                        else {
                            continue;
                        }
                    }
                }
                $AllApps.Add([PSCustomObject]@{
                        AppId        = $AppId
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
        $FinalResult | Where-Object { $_.Name -eq "Application" } | Foreach-Object { $_.AppId = $ApplicationAppId }
        return $FinalResult
    }
}
Export-ModuleMember -Function Get-AppFilesSortedByDependencies