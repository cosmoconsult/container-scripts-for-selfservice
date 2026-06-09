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

        function Get-DependencySortedApps() {
            param(
                [PSObject[]] $Apps
            )
            begin {
                function Invoke-VisitApp() {
                    param([PSObject] $App)
                    # visitState values: 0: not visited, 1: visiting (in call stack), 2: visited

                    $appIdKey = [string]$App.AppId
                    if ($visitState[$appIdKey] -eq 2) {
                        return
                    }
                    if ($visitState[$appIdKey] -eq 1) {
                        Write-Warning "Cyclic dependency detected for AppId $appIdKey"
                        return
                    }

                    $visitState[$appIdKey] = 1
                    foreach ($dependency in @($App.Dependencies)) {
                        $dependencyKey = [string]$dependency.AppId
                        if ($appsById.ContainsKey($dependencyKey)) {
                            Invoke-VisitApp -App $appsById[$dependencyKey]
                        }
                        else {
                            Write-Verbose "Ignoring dependency $dependencyKey of AppId $appIdKey because it is not part of the app list"
                        }
                    }

                    $visitState[$appIdKey] = 2
                    $sorted.Add($App) | Out-Null
                }
            }
            process {
                $appsById = @{}
                $sorted = [System.Collections.ArrayList]@()
                $visitState = @{}

                foreach ($app in $Apps) {
                    $appIdKey = [string]$app.AppId
                    $appsById[$appIdKey] = $app
                }


                foreach ($app in ($Apps | Sort-Object Name, Publisher, Version, Path)) {
                    Invoke-VisitApp -App $app
                }

                for ($i = 0; $i -lt $sorted.Count; $i++) {
                    $sorted[$i].ProcessOrder = $i + 1
                }

                return @($sorted)
            }
        }
    }

    process {
        if ($Path -eq "") {
            $Path = "C:\ProgramData\NavContainerHelper\DependencyApps"
        }
        $optionalParameters = @{}
        if ($Depth) {
            $optionalParameters["Depth"] = $Depth
        }
        if ($ExcludeExpr) {
            Write-Host ("Searching for apps excluding: {0}" -f $ExcludeExpr)
        }
        else {
            Write-Host "Searching for apps"
        }
        $AllAppFiles = Get-ChildItem -LiteralPath "$Path" -Filter $Filter -Recurse @optionalParameters | Where-Object { [string]::IsNullOrEmpty($ExcludeExpr) -or ($_.Name -notmatch $ExcludeExpr) }

        $AllApps = [System.Collections.ArrayList]@()
        $ApplicationAppId = ""
        foreach ($AppFile in $AllAppFiles) {
            Write-Verbose "Processing $($AppFile.Name)"
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
                        Dependencies = @() + $App.Dependencies | ForEach-Object { [PSCustomObject]@{
                                AppId     = $_.AppId
                                Publisher = $_.Publisher
                                Name      = $_.Name
                                Version   = $_.Version
                            }
                        }
                        Path         = $AppFile.FullName
                    }) | Out-Null # adding the returned index to PS-Return content
            }
            catch {
                Write-Warning "Got no AppInfo from $AppFile ... $_"
            }
        }
        Write-Verbose "Analyzed Apps: $($AllApps | ConvertTo-Json -Depth 5 -Compress)"

        $FinalResult = Get-DependencySortedApps -Apps $AllApps
        $FinalResult = $FinalResult | Sort-Object ProcessOrder, Name
        $FinalResult | Where-Object { $_.Name -eq "Application" } | ForEach-Object { $_.AppId = $ApplicationAppId }
        Write-Verbose "Final sorted list: $($FinalResult | ConvertTo-Json -Depth 5 -Compress)"
        return $FinalResult
    }
}
Export-ModuleMember -Function Get-AppFilesSortedByDependencies