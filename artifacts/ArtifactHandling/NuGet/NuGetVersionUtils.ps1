function Get-NuGetFeedSelectMode {
    [CmdletBinding()]
    param()

    if ($env:nuGetFeedSelectMode) {
        return $env:nuGetFeedSelectMode
    }
    return 'LatestMatching'
}

function Get-NuGetPackageNameInfo {
    [CmdletBinding()]
    param(
        [string]$Package,
        [switch]$AllowBareGuid
    )

    if (! $Package) {
        return $null
    }

    $guidPattern = '^[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12}$'
    if ($AllowBareGuid -and ($Package -match $guidPattern)) {
        return [PSCustomObject]@{
            Publisher = $null
            Name      = $null
            Id        = $Package
        }
    }

    $packagePattern = '^(?<publisher>[^\.]+)\.(?<name>[^\.]+)(?:\.(?<country>[^\.][^\.]))?(?:\.(?<symbols>symbols))?(?:\.(?<id>[0-9A-Fa-f]{8}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{4}\-[0-9A-Fa-f]{12}))?$' # <publisher>.<name>[.<country>][.<symbols>][.<id>]
    if ($Package -notmatch $packagePattern) {
        return $null
    }

    return [PSCustomObject]@{
        Publisher = $matches.publisher
        Name      = $matches.name
        Id        = $matches.id
    }
}

function Test-NuGetVersionMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$VersionMatches,
        [string]$ErrorMessage = "Invalid NuGet version '$($VersionMatches.0)'"
    )

    if ($VersionMatches.metadata) {
        throw "$($ErrorMessage): Metadata is not supported"
    }
}

function Test-NuGetVersionRangeMatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$VersionRangeMatches,
        [string]$ErrorMessage = "Invalid NuGet version range '$($VersionRangeMatches.0)'"
    )

    if ($VersionRangeMatches.prereleaseUpper -or $VersionRangeMatches.prereleaseLower) {
        throw "$($ErrorMessage): Prerelease versions are not supported"
    }

    $lowerBoundVersion = $null
    $upperBoundVersion = $null
    if ($VersionRangeMatches.versionLower) {
        $lowerBoundVersion = [System.Version]("$($VersionRangeMatches.versionLower).0.0.0".Split('.')[0..3] -join '.')
    }
    if ($VersionRangeMatches.versionUpper) {
        $upperBoundVersion = [System.Version]("$($VersionRangeMatches.versionUpper).0.0.0".Split('.')[0..3] -join '.')
    }
    if ($lowerBoundVersion -and $upperBoundVersion -and $upperBoundVersion -le $lowerBoundVersion) {
        throw "$($ErrorMessage): Upper bound version must be greater than lower bound version"
    }
}

function Get-NuGetVersionSpecification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Version,
        [switch]$AllowRange,
        [string]$ErrorContext = 'NuGet package'
    )

    $versionStablePattern = '\d+(?:\.\d+){0,3}'     # <major>[.<minor>[.<patch>[.<revision>]]]
    $versionPrereleasePattern = '(?:-[0-9A-Za-z.-]+)?'  # [-<prerelease>]
    $versionMetadataPattern = '(?:\+[0-9A-Za-z.-]+)?' # [+<metadata>]
    $versionPattern = '^\s*(?<version>{0})(?<prerelease>{1})(?<metadata>{2})\s*$' -f $versionStablePattern, $versionPrereleasePattern, $versionMetadataPattern # <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>][+<metadata>]

    $versionRangeLowerVersionPattern = '(?<versionLower>{0})(?<prereleaseLower>{1})' -f $versionStablePattern, $versionPrereleasePattern # <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>][,]
    $versionRangeUpperVersionPattern = '(?<versionUpper>{0})(?<prereleaseUpper>{1})' -f $versionStablePattern, $versionPrereleasePattern # [,]<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>]
    $versionRangePatterns = @(
        '(?<rangeStart>\[)\s*{0}\s*(?<rangeEnd>\])' -f $versionRangeUpperVersionPattern # Exact -> <[> <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] <]>
        '(?<rangeStart>\()\s*,{0}\s*(?<rangeEnd>\)|\])' -f $versionRangeUpperVersionPattern # Range (upper bound) -> <(> ,<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] <)]>
        '(?<rangeStart>\[|\()\s*{0},\s*(?<rangeEnd>\))' -f $versionRangeLowerVersionPattern # Range (lower bound) -> <[(> <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>, <)>
        '(?<rangeStart>\[|\()\s*{0},{1}\s*(?<rangeEnd>\)|\])' -f $versionRangeLowerVersionPattern, $versionRangeUpperVersionPattern # Range (both bounds) -> <[(> <major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>,<major>[.<minor>[.<patch>[.<revision>]]][-<prerelease>] <)]>
    )
    $versionRangePattern = '^\s*(?:{0})\s*$' -f ($versionRangePatterns -join '|')

    if ($Version -match $versionPattern) {
        $versionMatches = $matches
        Test-NuGetVersionMatches -VersionMatches $versionMatches -ErrorMessage "Invalid NuGet version '$Version' for $ErrorContext"
        return [PSCustomObject]@{
            Kind       = 'Version'
            Version    = $versionMatches.version
            Prerelease = $versionMatches.prerelease
        }
    }

    if ($AllowRange -and ($Version -match $versionRangePattern)) {
        $versionRangeMatches = $matches
        Test-NuGetVersionRangeMatches -VersionRangeMatches $versionRangeMatches -ErrorMessage "Invalid NuGet version range '$Version' for $ErrorContext"
        return [PSCustomObject]@{
            Kind         = 'Range'
            VersionLower = $versionRangeMatches.versionLower
            VersionUpper = $versionRangeMatches.versionUpper
            RangeEnd     = $versionRangeMatches.rangeEnd
        }
    }

    $expectedValue = if ($AllowRange) { 'version or NuGet version range' } else { 'version' }
    throw "Invalid NuGet $expectedValue '$Version' for $ErrorContext"
}

function ConvertTo-NuGetVersionConstraint {
    [CmdletBinding()]
    param(
        [string]$Version,
        [Parameter(Mandatory)]
        [ValidateSet('Earliest', 'EarliestMatching', 'Latest', 'LatestMatching', 'Exact', 'Any')]
        [string]$Select,
        [string]$ErrorContext = 'NuGet package'
    )

    if ((! $Version) -and ($Select -eq 'Exact')) {
        throw "Invalid NuGet version '$Version' for $ErrorContext"
    }
    if (! $Version) {
        return $null
    }

    $specification = Get-NuGetVersionSpecification -Version $Version -AllowRange:($Select -ne 'Exact') -ErrorContext $ErrorContext
    if ($Select -eq 'Exact') {
        return Normalize-NuGetVersionConstraint -VersionConstraint $Version
    }
    if ($specification.Kind -eq 'Range') {
        return Normalize-NuGetVersionConstraint -VersionConstraint $Version
    } 

    # Convert NuGet version to a range (from version, to excl. version + 1)
    # Increment the last version part to create upper bound
    $versionParts = $specification.Version.Split('.')
    $toVersionParts = $versionParts.Clone()
    $toVersionParts[-1] = [string]([int]$toVersionParts[-1] + 1)
    
    # Normalize both from and to versions to ensure at least major.minor format for System.Version compatibility
    $fromVersionNormalized = if ($versionParts.Count -eq 1) { "{0}.0" -f $versionParts[0] } else { $specification.Version }
    $toVersionNormalized = if ($toVersionParts.Count -eq 1) { "{0}.0" -f $toVersionParts[0] } else { $toVersionParts -join '.' }

    $fromVersion = '{0}{1}' -f $fromVersionNormalized, $specification.Prerelease
    $toVersion = '{0}{1}' -f $toVersionNormalized, $specification.Prerelease
    $versionRange = '[{0},{1})' -f $fromVersion, $toVersion
    return Normalize-NuGetVersionConstraint -VersionConstraint $versionRange
}

function ConvertTo-NuGetMaximumVersion {
    [CmdletBinding()]
    param(
        [string]$Version,
        [string]$ErrorContext = 'NuGet package'
    )

    $versionParts = @([int32]::MaxValue, [int32]::MaxValue, [int32]::MaxValue, ([int32]::MaxValue - 1))
    if (! $Version) {
        # If no version is specified, assume the highest possible version (e.g. <max>.<max>.<max>.<max - 1>
        return $versionParts[0..3] -join '.'
    }

    $specification = Get-NuGetVersionSpecification -Version $Version -AllowRange -ErrorContext $ErrorContext
    # If a specific version is specified, use the upper limit of this version (e.g. 1.2-beta -> 1.2.<max>.<max>-beta)
    if ($specification.Kind -eq 'Version') {
        $versionParts = $specification.Version.Split('.') + $versionParts
        return '{0}{1}' -f ($versionParts[0..3] -join '.'), $specification.Prerelease
    }

    # If a version range is specified, use the upper limit of this range
    # If the upper limit is exclusive, get the highest possible previous version (e.g. 1.2 -> 1.1.<max>.<max>, 2.0 -> 1.<max>.<max>.<max>)
    # If the upper limit is inclusive, use the upper limit version as-is (e.g. 1.2 -> 1.2.0.0)
    # If no upper limit is specified, use the highest possible version (e.g. <max>.<max>.<max>.<max - 1>)
    if ($specification.VersionUpper) {
        $versionUpperParts = @($specification.VersionUpper -replace '(\.0+)+$', '' -split '\.')
        if ($specification.RangeEnd -eq ')') {
            # Exclusive upper limit
            $versionUpperParts[-1] = [int]$versionUpperParts[-1] - 1
            $versionParts = $versionUpperParts + $versionParts
        }
        else {
            # Inclusive upper limit
            $versionParts = $versionUpperParts + @(0, 0, 0)
        }
    }
    return $versionParts[0..3] -join '.'
}

function Normalize-NuGetVersionConstraint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$VersionConstraint
    )

    # NuGet allows major-only versions, but BcContainerHelper parses constraints with System.Version and requires major.minor
    # 28 → 28.0
    # 28-beta → 28.0-beta
    # [1,2) → [1.0,2.0)
    # (,2] → (,2.0]
    $majorOnlyVersionPattern = '(?<prefix>^|[\[\(,])(?<version>\d+)(?=$|[-+,\)\]])'
    $addMissingMinorVersion = '${prefix}${version}.0'
    return [regex]::Replace(($VersionConstraint -replace '\s+'), $majorOnlyVersionPattern, $addMissingMinorVersion)
}