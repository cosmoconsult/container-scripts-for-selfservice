function Get-AppFilesSortedByDependencies {
    [CmdletBinding()]
    param(
        [string] $Path,
        [string] $Filter = "*.app",
        [string[]] $ExcludeExpr = $env:AppExcludeExpr,        
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

        $excludeExprValues = @($ExcludeExpr | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $hasExcludeExpr = $excludeExprValues.Count -gt 0
        $excludePattern = if ($hasExcludeExpr) { $excludeExprValues -join "|" } else { $null }

        Write-Host ("##[debug] AppExcludeExpr(raw env): '{0}'" -f $env:AppExcludeExpr)
        Write-Host ("##[debug] AppExcludeExpr(effective): '{0}'" -f ($excludeExprValues -join ","))

        if($hasExcludeExpr) {
            Write-Host ("Searching for apps excluding: {0}" -f ($excludeExprValues -join ", "))
            Write-Debug ("Exclude regex pattern: {0}" -f $excludePattern)
        }
        else {
            Write-Host "Searching for apps"
        }

        $candidateAppFiles = @(Get-ChildItem -LiteralPath "$Path" -Filter $Filter -Recurse @optionalParameters)
        Write-Host ("##[debug] Candidate app count before exclusion: {0}" -f $candidateAppFiles.Count)

        if ($hasExcludeExpr) {
            $AllAppFiles = @($candidateAppFiles | Where-Object { $_.Name -notmatch $excludePattern })
            $excludedAppFiles = @($candidateAppFiles | Where-Object { $_.Name -match $excludePattern })
            Write-Host ("##[debug] Excluded app count: {0}" -f $excludedAppFiles.Count)
            Write-Host ("##[debug] Remaining app count: {0}" -f $AllAppFiles.Count)
            if ($excludedAppFiles.Count -gt 0) {
                $excludedPreview = $excludedAppFiles | Select-Object -First 20 -ExpandProperty Name
                Write-Debug ("Excluded app names (first {0}): {1}" -f $excludedPreview.Count, ($excludedPreview -join ", "))
            }
        }
        else {
            $AllAppFiles = $candidateAppFiles
        }

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