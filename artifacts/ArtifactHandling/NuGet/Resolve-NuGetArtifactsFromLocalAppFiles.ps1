function Resolve-NuGetArtifactsFromLocalAppFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Artifacts,
        [Parameter(Mandatory)]
        [string]$ServiceTierFolder
    )

    $nuGetArtifacts = @($Artifacts | Where-Object { $_.type -eq 'nuget' })
    if (! $nuGetArtifacts) {
        return $Artifacts
    }

    $nuGetArtifactsAppIds = @($nuGetArtifacts |
        ForEach-Object { Get-NuGetPackageNameInfo -Package $_.name -AllowBareGuid } |
        Where-Object { $_.Id } |
        Select-Object -ExpandProperty Id -Unique)
    if (! $nuGetArtifactsAppIds) {
        return $Artifacts
    }

    Import-NAVModules -ServiceTierFolder $ServiceTierFolder -ExcludeRoleTailoredClient
    Import-NuGetTools
    $nuGetToolsModule = Get-Module -Name 'BcContainerHelper'
    $normalizeVersion = $nuGetToolsModule.NewBoundScriptBlock(
        [ScriptBlock]::Create('param($Version) [NuGetFeed]::NormalizeVersionStr($Version)'))
    $isVersionIncludedInRange = $nuGetToolsModule.NewBoundScriptBlock(
        [ScriptBlock]::Create('param($Version, $VersionRange) [NuGetFeed]::IsVersionIncludedInRange($Version, $VersionRange)'))

    $localAppInfos = @(Get-NuGetAppInfos -AppFilesPath 'C:\Extensions' -ServiceTierFolder $ServiceTierFolder -AppIds $nuGetArtifactsAppIds | Where-Object { $_.Publisher -eq 'Microsoft' })
    $select = Get-NuGetFeedSelectMode

    foreach ($artifact in $nuGetArtifacts) {
        $packageNameInfo = Get-NuGetPackageNameInfo -Package $artifact.name -AllowBareGuid
        if (! $packageNameInfo.Id) {
            continue
        }

        $versionConstraint = ConvertTo-NuGetVersionConstraint -Version $artifact.version -Select $select -ErrorContext "package '$($artifact.name)'"
        $localApp = @($localAppInfos | Where-Object {
            if ($_.Id -ne $packageNameInfo.Id) {
                return $false
            }
            if ($select -eq 'Exact') {
                return (& $normalizeVersion $_.Version) -eq (& $normalizeVersion $versionConstraint)
            }
            return (! $versionConstraint) -or (& $isVersionIncludedInRange $_.Version $versionConstraint)
        } | Sort-Object { [Version]$_.Version } -Descending | Select-Object -First 1)
        if (! $localApp) {
            continue
        }
        $localApp = $localApp[0]

        $constraintText = if ($artifact.version) { $artifact.version } else { '<any>' }
        Write-Host "Use local app file '$($localApp.Path)' for Microsoft app '$($localApp.Name)' ($($localApp.Id)) version '$($localApp.Version)' instead of downloading NuGet package '$($artifact.name)' with version constraint '$constraintText'"
        $artifact | Add-Member -MemberType NoteProperty -Name url -Value $localApp.Path -Force
        $artifact.type = 'url'
    }

    return $Artifacts
}
Export-ModuleMember -Function Resolve-NuGetArtifactsFromLocalAppFiles