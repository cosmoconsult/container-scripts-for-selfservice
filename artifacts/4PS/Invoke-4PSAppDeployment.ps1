# Script to deterministically update apps in a BC container from FileShare + Artifacts
# - Runs inside COSMO/BC container
# - Uses System Application version to select release folder
# - Uses Software/OpenExtensions for 4PS apps
# - Supports modes: updateExistingApps, syncAllAppsFromFileShare
# - Supports Dev scope (auto-detects containerId)

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ContainerId,

    [Parameter(Mandatory = $true)]
    [string]$Username,

    [Parameter(Mandatory = $true)]
    [string]$Password,

    [Parameter(Mandatory = $true)]
    [ValidateSet('updateExistingApps', 'syncAllAppsFromFileShare')]
    [string]$Mode = "",

    [Parameter(Mandatory = $true)]
    [ValidateSet('master', 'dev', 'release')]
    [string]$Version = "",

    [Parameter(Mandatory = $true)]
    [string]$Localization = "",

    [Parameter(Mandatory = $false)]
    [string]$Organization = "4PSNL",

    [Parameter(Mandatory = $true)]
    [string]$DependsOnApp = "",

    # Debug mode: skip actual deployment, but run all preparation
    [switch]$DebugMode
)

# -----------------------------
# 1. Configuration
# -----------------------------

Write-Host "Business Central App Deployment" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

if ($DebugMode) {
    Write-Host ""
    Write-Host ">>> DEBUG MODE ENABLED <<<" -ForegroundColor Yellow
    Write-Host "Deployment is skipped, but all preparation still runs." -ForegroundColor Yellow
    Write-Host ""
}

$SecurePassword = ConvertTo-SecureString $Password -AsPlainText -Force
$Credential = [PSCredential]::new($Username, $SecurePassword)

# Fixed container settings
$ServerInstance = "BC"
$Tenant = "Default"

# -----------------------------
# 2. Environment checks + modules
# -----------------------------

$containerToolkitPath = "C:\Run\prompt.ps1"
if (-not (Test-Path $containerToolkitPath)) {
    Write-Error "This script must be run inside a COSMO/BC container where '$containerToolkitPath' is available."
    return
}

# BC container tooling
. $containerToolkitPath

# Extended environment (DevOps artifacts, etc.)
$extendedEnvPath = "C:\run\my\ExtendedEnvironment.ps1"
if (Test-Path $extendedEnvPath) {
    . $extendedEnvPath
}

# PPI artifact utilities (provides Get-ArtifactsFromEnvironment, etc.)
$ppiModulePath = "C:/run/PPIArtifactUtils.psd1"
if (Test-Path $ppiModulePath) {
    $ppiModulePath | Import-Module -Force
}
else {
    Write-Warning "PPIArtifactUtils.psd1 not found at '$ppiModulePath'. Artifacts may not be available."
}

# containerId (required for Dev scope)
if ([string]::IsNullOrWhiteSpace($ContainerId)) {
    $ContainerId = $(
        (Get-NAVServerConfiguration -ServerInstance $ServerInstance -KeyName PublicWebBaseUrl) -split "/"
    )[3]
}

# -----------------------------
# 3. Helper functions
# -----------------------------
function Normalize-AppName {
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string]$Publisher
    )

    $normalized = $Name.Trim().ToLowerInvariant()
    if ($Publisher) {
        $normalized = "$($Publisher.Trim().ToLowerInvariant())::$normalized"
    }
    return $normalized
}

function Get-InstalledApps {
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        [string]$Tenant = "default"
    )

    $apps = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant

    # Keep only latest version per Publisher+Name
    $apps |
    Group-Object -Property Publisher, Name |
    ForEach-Object {
        $_.Group | Sort-Object Version -Descending | Select-Object -First 1
    } |
    ForEach-Object {
        $_ | Add-Member -NotePropertyName NormalizedName -NotePropertyValue (Normalize-AppName -Name $_.Name -Publisher $_.Publisher) -Force
        $_ | Add-Member -NotePropertyName IsInstalled -NotePropertyValue $true -Force
        $_
    }
}

function Get-PublishedApps {
    param(
        [Parameter(Mandatory)]
        [string]$ServerInstance
    )

    # Get-NAVAppInfo without -Tenant returns all published apps
    $apps = Get-NAVAppInfo -ServerInstance $ServerInstance

    # Keep only latest version per Publisher+Name
    $apps |
    Group-Object -Property Publisher, Name |
    ForEach-Object {
        $_.Group | Sort-Object Version -Descending | Select-Object -First 1
    } |
    ForEach-Object {
        $_ | Add-Member -NotePropertyName NormalizedName -NotePropertyValue (Normalize-AppName -Name $_.Name -Publisher $_.Publisher) -Force
        $_
    }
}

function Get-AppsFromMicrosoftContainer {
    param(
        [Parameter(Mandatory)]
        [string]$ApplicationsRoot,
            
        [Parameter(Mandatory)]
        [version]$BCVersion
    )

    if (-not (Test-Path $ApplicationsRoot)) {
        return @()
    }

    $allFiles = Get-ChildItem -Path $ApplicationsRoot -Recurse -Filter "*.app" -File
    Write-Host "  Found $($allFiles.Count) .app file(s) in Microsoft container" -ForegroundColor DarkGray

    # Parse metadata from filename pattern: Publisher_Name.app
    # All container apps use the BC version (no version in filename)
    $allFiles | ForEach-Object {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
            
        # Find first underscore to split Publisher from Name
        $firstUnderscoreIndex = $fileName.IndexOf('_')
            
        if ($firstUnderscoreIndex -gt 0) {
            $publisher = $fileName.Substring(0, $firstUnderscoreIndex)
            $name = $fileName.Substring($firstUnderscoreIndex + 1)
                
            # Handle double underscore (e.g., Microsoft__Exclude_Bank Deposits -> _Exclude_Bank Deposits)
            # The name starts with underscore in this case
                
            [PSCustomObject]@{
                Name           = $name
                Publisher      = $publisher
                Version        = $BCVersion
                NormalizedName = Normalize-AppName -Name $name -Publisher $publisher
                SourceType     = "MicrosoftContainer"
                SourcePath     = $_.FullName
                Scope          = "Dev"
                Dependencies   = $null  # Lazy load - will be populated when needed
            }
        }
        else {
            Write-Warning "Could not parse filename '$fileName' - no underscore found"
        }
    }
}

function Get-AppsFromUnstructuredFolder {
    param(
        [Parameter(Mandatory)]
        [string]$FolderPath,
            
        [Parameter(Mandatory)]
        [version]$BCVersion,
            
        [string]$SourceLabel = "UnstructuredFolder",
            
        # Regex pattern for filenames to exclude (e.g., "^Microsoft_" to skip Microsoft apps)
        [string]$ExcludeFileNamePattern = "^Microsoft_",
            
        # Maximum folder depth to scan (default 3 to avoid deep recursion on network shares)
        [int]$MaxDepth = 3,
            
        # Skip BC version compatibility check (for partner apps with their own versioning)
        [switch]$SkipBCVersionCheck
    )

    if (-not (Test-Path $FolderPath)) {
        Write-Host "  Folder '$FolderPath' does not exist, skipping." -ForegroundColor DarkGray
        return @()
    }

    # Use -Depth to limit recursion on network shares (much faster)
    $allAppFiles = Get-ChildItem -Path $FolderPath -Depth $MaxDepth -Filter "*.app" -File -ErrorAction SilentlyContinue
        
    if (-not $allAppFiles -or $allAppFiles.Count -eq 0) {
        Write-Host "  No .app files found in '$FolderPath'" -ForegroundColor DarkGray
        return @()
    }

    Write-Host "  Found $($allAppFiles.Count) .app file(s) in '$FolderPath'" -ForegroundColor DarkGray

    # Use List for O(1) add instead of O(n) array concatenation
    $apps = New-Object System.Collections.Generic.List[object]
    $excludedByPattern = 0
    $noVersionCount = 0

    foreach ($appFile in $allAppFiles) {
        $fileName = $appFile.Name
            
        # Quick exclusion by pattern (before parsing)
        if ($ExcludeFileNamePattern -and $fileName -match $ExcludeFileNamePattern) {
            $excludedByPattern++
            continue
        }
            
        $fileNameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
            
        # Find first underscore to split Publisher from rest
        $firstUnderscoreIndex = $fileNameWithoutExt.IndexOf('_')
        if ($firstUnderscoreIndex -le 0) {
            # No underscore - can't parse
            continue
        }
            
        $publisher = $fileNameWithoutExt.Substring(0, $firstUnderscoreIndex)
        $rest = $fileNameWithoutExt.Substring($firstUnderscoreIndex + 1)
            
        # Try to extract version from the last underscore-separated part
        $version = $null
        $name = $rest
            
        $lastUnderscoreIndex = $rest.LastIndexOf('_')
        if ($lastUnderscoreIndex -gt 0) {
            $potentialVersion = $rest.Substring($lastUnderscoreIndex + 1)
            try {
                $version = [version]$potentialVersion
                # Version parsed successfully - name is everything before it
                $name = $rest.Substring(0, $lastUnderscoreIndex) -replace '_', ' '
            }
            catch {
                # Not a valid version - treat entire rest as name
                $name = $rest -replace '_', ' '
            }
        }
        else {
            # No underscore in rest - entire rest is the name
            $name = $rest -replace '_', ' '
        }
            
        # If we have a version and BC version check is enabled, check compatibility
        if ($version -and -not $SkipBCVersionCheck) {
            if ($version.Major -ne $BCVersion.Major -or $version.Minor -ne $BCVersion.Minor) {
                # Incompatible BC version - skip
                continue
            }
        }
        elseif (-not $version) {
            $noVersionCount++
        }
            
        $apps.Add([PSCustomObject]@{
                Name           = $name
                Publisher      = $publisher
                Version        = $version  # May be $null - loaded lazily when needed
                NormalizedName = Normalize-AppName -Name $name -Publisher $publisher
                SourceType     = "FileShare"
                SourcePath     = $appFile.FullName
                Scope          = "Dev"
                Dependencies   = $null
                SourceLabel    = $SourceLabel
            })
    }

    if ($excludedByPattern -gt 0) {
        Write-Host "    Excluded by pattern: $excludedByPattern" -ForegroundColor DarkGray
    }
    if ($noVersionCount -gt 0) {
        Write-Host "    Apps without version in filename: $noVersionCount (will load lazily)" -ForegroundColor DarkGray
    }
    Write-Host "    Total apps found: $($apps.Count)" -ForegroundColor DarkGray

    return $apps.ToArray()
}

function Get-AppsFromFileShare {
    param(
        [Parameter(Mandatory)]
        [string]$ReleaseFolderPath
    )

    if (-not (Test-Path $ReleaseFolderPath)) {
        Write-Warning "FileShare release folder '$ReleaseFolderPath' does not exist."
        return @()
    }

    # Fast path: parse metadata from filename pattern (Publisher_Name_Version.app)
    # Only call Get-NAVAppInfo when we actually need dependencies later
    Get-ChildItem -Path $ReleaseFolderPath -Recurse -Filter "*.app" -File |
    ForEach-Object {
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        $parts = $fileName.Split('_')
                
        $publisher = $null
        $name = $null
        $version = $null
                
        if ($parts.Count -ge 3) {
            # Pattern: Publisher_Name_Version.app (name may contain underscores)
            $publisher = $parts[0]
            $versionPart = $parts[$parts.Count - 1]
            $nameParts = $parts[1..($parts.Count - 2)]
            $name = $nameParts -join ' '
                    
            try {
                $version = [version]$versionPart
            }
            catch {
                # Version parse failed, fall back to Get-NAVAppInfo
                $version = $null
            }
        }
                
        # If filename parsing failed, use Get-NAVAppInfo (slower)
        if (-not $name -or -not $version) {
            try {
                $info = Get-NAVAppInfo -Path $_.FullName -ErrorAction Stop
                $publisher = $info.Publisher
                $name = $info.Name
                $version = $info.Version
            }
            catch {
                Write-Warning "Failed to read app metadata from '$($_.FullName)': $($_.Exception.Message)"
                return
            }
        }

        [PSCustomObject]@{
            Name           = $name
            Publisher      = $publisher
            Version        = $version
            NormalizedName = Normalize-AppName -Name $name -Publisher $publisher
            SourceType     = "FileShare"
            SourcePath     = $_.FullName
            Scope          = "Dev"
            Dependencies   = $null  # Lazy load - will be populated when needed
        }
    }
}

function Get-AppMetadata {
    <#
        .SYNOPSIS
            Lazy-loads app metadata (Version and Dependencies) from .app file.
        .DESCRIPTION
            Only calls Get-NAVAppInfo if Version or Dependencies are missing.
            Updates the App object in-place and returns it.
        #>
    param(
        [Parameter(Mandatory)]
        $App
    )
        
    # Only call Get-NAVAppInfo if we're missing Version or Dependencies
    if ($null -eq $App.Version -or $null -eq $App.Dependencies) {
        try {
            $info = Get-NAVAppInfo -Path $App.SourcePath -ErrorAction Stop
            if ($null -eq $App.Version) {
                $App.Version = $info.Version
            }
            if ($null -eq $App.Dependencies) {
                $App.Dependencies = $info.Dependencies
            }
        }
        catch {
            Write-Warning "Failed to read app metadata from '$($App.SourcePath)': $($_.Exception.Message)"
            if ($null -eq $App.Dependencies) {
                $App.Dependencies = @()
            }
        }
    }
    return $App
}

function Get-AppDependencies {
    # Helper to lazy-load dependencies for an app
    param(
        [Parameter(Mandatory)]
        $App
    )
        
    if ($null -eq $App.Dependencies) {
        Get-AppMetadata -App $App | Out-Null
    }
    return $App.Dependencies
}

function Get-AppVersion {
    # Helper to lazy-load version for an app
    param(
        [Parameter(Mandatory)]
        $App
    )
        
    if ($null -eq $App.Version) {
        Get-AppMetadata -App $App | Out-Null
    }
    return $App.Version
}

function Test-AppBCCompatibility {
    <#
        .SYNOPSIS
            Checks if an app is compatible with the current BC version.
        .DESCRIPTION
            Lazy-loads the app's dependencies and checks if it has a dependency
            on "Application" from "Microsoft". If so, validates that the dependency's
            MinVersion.Major matches the target BC version.
            
            Partner apps typically depend on Microsoft's Application with a version
            like 24.0.0.0 or 27.0.0.0, which indicates the BC version they're built for.
        #>
    param(
        [Parameter(Mandatory)]
        $App,
            
        [Parameter(Mandatory)]
        [version]$BCVersion
    )
        
    # Lazy-load dependencies if needed
    $deps = Get-AppDependencies -App $App
    if (-not $deps -or $deps.Count -eq 0) {
        # No dependencies - can't verify BC compatibility, assume compatible
        return $true
    }
        
    # Look for dependency on "Application" from "Microsoft"
    $appDep = $deps | Where-Object {
        $_.Publisher -eq "Microsoft" -and $_.Name -eq "Application"
    } | Select-Object -First 1
        
    if (-not $appDep) {
        # No Microsoft Application dependency - can't verify, assume compatible
        return $true
    }
        
    # Check if the dependency's MinVersion.Major matches our BC version
    $depMinVersion = $appDep.MinVersion
    if (-not $depMinVersion) {
        return $true
    }
        
    # BC compatibility: Major version must match
    return $depMinVersion.Major -eq $BCVersion.Major
}

function Select-LatestVersionApp {
    # Select the app with the highest version from a collection
    # Lazy-loads version if needed before comparing
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $Apps
    )
        
    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }
    process {
        if ($null -ne $Apps) {
            if ($Apps -is [System.Array]) {
                foreach ($app in $Apps) {
                    if ($null -ne $app) { $collected.Add($app) }
                }
            }
            else {
                $collected.Add($Apps)
            }
        }
    }
    end {
        if ($collected.Count -eq 0) { return $null }
        if ($collected.Count -eq 1) { return $collected[0] }
            
        # Lazy-load versions for all candidates
        foreach ($app in $collected) {
            if ($null -eq $app.Version) {
                Get-AppVersion -App $app | Out-Null
            }
        }
            
        # Sort by version descending and return first
        $collected | Sort-Object Version -Descending | Select-Object -First 1
    }
}

function Warn-AppNotFoundInSources {
    param(
        [Parameter(Mandatory)]
        $App
    )

    Write-Warning ("Application '{0}' (Publisher '{1}') was not found in any source directory." -f $App.Name, $App.Publisher)
}

function Convert-ArtifactToExpectedAppSkeleton {
    param(
        [Parameter(Mandatory)]
        $Artifact
    )

    if ($Artifact.target -ne 'app') {
        return $null
    }

    $publisher = $null
    $name = $null
    $version = $null
    $dependencies = @()

    # Primary: Read metadata directly from .app file at artifact.url
    if ($Artifact.url -and $Artifact.url -like '*.app' -and (Test-Path $Artifact.url)) {
        try {
            $info = Get-NAVAppInfo -Path $Artifact.url -ErrorAction Stop
            $publisher = $info.Publisher
            $name = $info.Name
            $version = $info.Version
            $dependencies = $info.Dependencies
        }
        catch {
            Write-Warning "Failed to read app metadata from artifact url '$($Artifact.url)': $($_.Exception.Message)"
            return $null
        }
    }
    else {
        # Fallback: Try to parse filename from url (e.g., "Publisher_Name_Version.app")
        if ($Artifact.url -and $Artifact.url -like '*.app') {
            $fileName = [System.IO.Path]::GetFileName($Artifact.url)
            $parts = $fileName.Split('_')
            if ($parts.Count -ge 3) {
                # Pattern: Publisher_Name_Version.app
                $publisher = $parts[0]
                $nameParts = $parts[1..($parts.Length - 2)]
                $name = $nameParts -join '_'
                # Extract version from last part (remove .app extension)
                $versionPart = $parts[$parts.Length - 1] -replace '\.app$', ''
                try {
                    $version = [version]$versionPart
                }
                catch {
                    Write-Warning "Could not parse version '$versionPart' from filename '$fileName'"
                    $version = $null
                }
            }
            elseif ($parts.Count -eq 2) {
                # Pattern: Publisher_Name.app
                $publisher = $parts[0]
                $name = $parts[1] -replace '\.app$', ''
            }
            else {
                Write-Warning "Artifact url '$($Artifact.url)' does not exist and filename pattern is unrecognized."
                return $null
            }
        }
        else {
            Write-Warning "Artifact has no valid .app url: $($Artifact | ConvertTo-Json -Compress)"
            return $null
        }
    }

    if (-not $name) {
        return $null
    }

    # Use scope from artifact if available, otherwise default to Dev
    $scope = if ($Artifact.appImportScope) { $Artifact.appImportScope } else { "Dev" }

    [PSCustomObject]@{
        Name           = $name
        Publisher      = $publisher
        NormalizedName = Normalize-AppName -Name $name -Publisher $publisher
        Version        = $version
        SourceType     = "Artifact"
        SourcePath     = $Artifact.url
        Scope          = $scope
        Dependencies   = $dependencies
    }
}

function Resolve-AppSource {
    param(
        [Parameter(Mandatory)]
        $ExpectedApp,
        [Parameter(Mandatory)]
        $AvailableApps
    )

    if ($ExpectedApp.SourceType -and $ExpectedApp.SourcePath) {
        return $ExpectedApp
    }

    $match = $AvailableApps | Where-Object {
        $_.NormalizedName -eq $ExpectedApp.NormalizedName
    } | Select-LatestVersionApp

    if (-not $match) {
        throw "No source found for app '$($ExpectedApp.Name)' (Publisher: $($ExpectedApp.Publisher))."
    }

    # Lazy-load dependencies for the matched app
    Get-AppDependencies -App $match | Out-Null
        
    $ExpectedApp.SourceType = $match.SourceType
    $ExpectedApp.SourcePath = $match.SourcePath
    $ExpectedApp.Version = $match.Version
    $ExpectedApp.Dependencies = $match.Dependencies
    return $ExpectedApp
}

function Resolve-AppScope {
    param(
        [Parameter(Mandatory)]
        $ExpectedApp,
        [Parameter(Mandatory)]
        $InstalledApps,
        $PublishedApps = @()
    )

    # Rule 1: 4PS apps ALWAYS deploy as Dev (for VSCode editing), regardless of existing scope.
    if ($ExpectedApp.Publisher -like "4PS*") {
        $ExpectedApp.Scope = "Dev"
        return $ExpectedApp
    }

    # Rule 2: Microsoft apps always Global.
    if ($ExpectedApp.Publisher -eq "Microsoft") {
        $ExpectedApp.Scope = "Global"
        return $ExpectedApp
    }

    # Rule 3: If app already exists (installed or published), inherit existing scope.
    # This must win over any default/pre-filled scope (e.g. Source loaders setting Dev).
    $existing = $InstalledApps | Where-Object {
        $_.NormalizedName -eq $ExpectedApp.NormalizedName
    } | Select-Object -First 1
        
    if (-not $existing) {
        $existing = $PublishedApps | Where-Object {
            $_.NormalizedName -eq $ExpectedApp.NormalizedName
        } | Select-Object -First 1
    }

    if ($existing -and $existing.Scope) {
        $ExpectedApp.Scope = $existing.Scope
        return $ExpectedApp
    }

    # Rule 4: Respect explicit non-Dev scope already present (e.g. artifact-provided Tenant/Global/PTE).
    if ($ExpectedApp.Scope -and $ExpectedApp.Scope -ne "Dev") {
        return $ExpectedApp
    }

    # Rule 5: All other new apps default to PTE
    $ExpectedApp.Scope = "PTE"
    return $ExpectedApp
}

function Prepare-DeploymentApp {
    param(
        [Parameter(Mandatory)]
        $ExpectedApp,
        [Parameter(Mandatory)]
        $InstalledApps,
        $PublishedApps = @()
    )

    $installed = $InstalledApps | Where-Object {
        $_.NormalizedName -eq $ExpectedApp.NormalizedName
    } | Select-Object -First 1

    $published = $PublishedApps | Where-Object {
        $_.NormalizedName -eq $ExpectedApp.NormalizedName
    } | Select-Object -First 1

    $isInstalled = [bool]$installed
    $isPublished = [bool]$published
    $isUpdate = $false
    $needsInstall = $false

    if ($installed) {
        # Lazy-load version if needed for comparison
        $expectedVersion = Get-AppVersion -App $ExpectedApp
        if ($expectedVersion -gt $installed.Version) {
            $isUpdate = $true
        }
        elseif ($expectedVersion -eq $installed.Version) {
            # Already at same version; we still include but can mark as no-op
            $isUpdate = $false
        }
    }
    elseif ($published) {
        # App is published but not installed - needs to be installed
        $expectedVersion = Get-AppVersion -App $ExpectedApp
        if ($expectedVersion -gt $published.Version) {
            # Newer version - will be published and then installed
            $isUpdate = $true
            $needsInstall = $true
        }
        elseif ($expectedVersion -eq $published.Version) {
            # Same version but not installed - just needs install
            $needsInstall = $true
        }
    }

    [PSCustomObject]@{
        Name           = $ExpectedApp.Name
        Publisher      = $ExpectedApp.Publisher
        NormalizedName = $ExpectedApp.NormalizedName
        Version        = $ExpectedApp.Version
        SourceType     = $ExpectedApp.SourceType
        SourcePath     = $ExpectedApp.SourcePath
        Scope          = $ExpectedApp.Scope
        Dependencies   = $ExpectedApp.Dependencies
        IsInstalled    = $isInstalled
        IsPublished    = $isPublished
        IsUpdate       = $isUpdate
        NeedsInstall   = $needsInstall
    }
}

function Resolve-DeploymentOrder {
    param(
        [Parameter(Mandatory)]
        $DeploymentApps,
        [Parameter(Mandatory = $false)]
        $AllAvailableApps = @(),
        [Parameter(Mandatory = $false)]
        $InstalledApps = @()
    )

    # Build lookup for deployment apps
    $deploymentLookup = @{}
    foreach ($app in $DeploymentApps) {
        $deploymentLookup[$app.NormalizedName] = $app
    }
        
    # Build lookup for all available apps (for transitive dependency resolution)
    $allAppsLookup = @{}
    foreach ($app in $AllAvailableApps) {
        $norm = if ($app.NormalizedName) { $app.NormalizedName } else { Normalize-AppName -Name $app.Name -Publisher $app.Publisher }
        if (-not $allAppsLookup.ContainsKey($norm)) {
            $allAppsLookup[$norm] = $app
        }
    }
    # Also add installed apps to the lookup
    foreach ($app in $InstalledApps) {
        $norm = if ($app.NormalizedName) { $app.NormalizedName } else { Normalize-AppName -Name $app.Name -Publisher $app.Publisher }
        if (-not $allAppsLookup.ContainsKey($norm)) {
            $allAppsLookup[$norm] = $app
        }
    }
    # Add deployment apps (they may have more up-to-date info)
    foreach ($app in $DeploymentApps) {
        $allAppsLookup[$app.NormalizedName] = $app
    }
        
    # Check if we have 4PS Application substituting Microsoft Application
    $hasFourPsApplication = $deploymentLookup.ContainsKey("4ps b.v.::application") -or $allAppsLookup.ContainsKey("4ps b.v.::application")

    $visited = @{}
    $result = New-Object System.Collections.Generic.List[object]

    function Visit-App {
        param($appNorm, $isDeploymentApp)

        if ($visited.ContainsKey($appNorm)) {
            return
        }
        $visited[$appNorm] = $true
            
        # Get the app from deployment lookup first, then fall back to all apps
        $app = $null
        $inDeploymentList = $deploymentLookup.ContainsKey($appNorm)
        if ($inDeploymentList) {
            $app = $deploymentLookup[$appNorm]
        }
        elseif ($allAppsLookup.ContainsKey($appNorm)) {
            $app = $allAppsLookup[$appNorm]
        }
            
        if ($null -eq $app) {
            return
        }

        # Get dependencies (should already be loaded, but ensure they exist)
        $deps = $app.Dependencies
        if ($null -eq $deps -or $deps.Count -eq 0) {
            # Try lazy-loading if we have SourcePath
            if ($app.SourcePath -and (Test-Path $app.SourcePath -ErrorAction SilentlyContinue)) {
                $deps = Get-AppDependencies -App $app
            }
        }
            
        if ($deps) {
            foreach ($dep in $deps) {
                $depNorm = Normalize-AppName -Name $dep.Name -Publisher $dep.Publisher
                    
                # Handle Microsoft::Application -> 4PS B.V.::Application substitution
                if ($depNorm -eq "microsoft::application" -and $hasFourPsApplication) {
                    $depNorm = "4ps b.v.::application"
                }
                    
                # Always follow the dependency tree, even for non-deployment apps
                # This ensures transitive dependencies are properly ordered
                if ($deploymentLookup.ContainsKey($depNorm) -or $allAppsLookup.ContainsKey($depNorm)) {
                    Visit-App -appNorm $depNorm -isDeploymentApp $deploymentLookup.ContainsKey($depNorm)
                }
            }
        }

        # Only add to result if this is a deployment app
        if ($inDeploymentList) {
            $result.Add($app)
        }
    }

    foreach ($app in $DeploymentApps) {
        Visit-App -appNorm $app.NormalizedName -isDeploymentApp $true
    }

    # Debug: Show all apps in deployment order
    Write-Host ""
    Write-Host "Deployment order (all $($result.Count) apps):" -ForegroundColor DarkGray
    for ($i = 0; $i -lt $result.Count; $i++) {
        $a = $result[$i]
        $depCount = if ($a.Dependencies) { $a.Dependencies.Count } else { 0 }
        Write-Host ("  {0}. {1} - {2} (deps: {3})" -f ($i + 1), $a.Publisher, $a.Name, $depCount) -ForegroundColor DarkGray
    }

    # Return in dependency order (Microsoft apps naturally end up first if they have no deps)
    return $result.ToArray()
}

function Deploy-App {
    param(
        [Parameter(Mandatory)]
        $DeploymentApp,
        [Parameter(Mandatory)]
        [string]$ServerInstance,
        [Parameter(Mandatory)]
        [string]$Tenant,
        [Parameter(Mandatory)]
        [pscredential]$Credential,
        [Parameter(Mandatory)]
        [string]$ContainerId
    )

    Write-Host ""
    Write-Host ("Deploying: {0} - {1} (v{2}) Scope: {3}" -f $DeploymentApp.Publisher, $DeploymentApp.Name, $DeploymentApp.Version, $DeploymentApp.Scope) -ForegroundColor Cyan
    Write-Host ("Source: {0}" -f $DeploymentApp.SourcePath) -ForegroundColor DarkGray

    $arguments = @{
        "AppToDeploy" = $DeploymentApp.SourcePath
        "Scope"       = $DeploymentApp.Scope
    }

    if ($DeploymentApp.Scope -eq "Dev") {
        $plainPassword = $Credential.GetNetworkCredential().Password
        $arguments += @{
            "username"    = $Credential.UserName
            "password"    = $plainPassword
            "containerid" = $ContainerId
        }
    }

    $argumentsForLog = @{}
    foreach ($key in $arguments.Keys) {
        if ($key -eq "password") {
            $argumentsForLog[$key] = "***"
        }
        else {
            $argumentsForLog[$key] = $arguments[$key]
        }
    }
    try {
            
        # Capture ALL output streams (*>&1) to detect failures (Invoke-AppDeployment.ps1 doesn't throw on error)
        # Stream 1=Output, 2=Error, 3=Warning, 4=Verbose, 5=Debug, 6=Information (Write-Host)
        $deployOutput = . "C:/run/Invoke-AppDeployment.ps1" @arguments *>&1
        $outputText = ($deployOutput | Out-String)
            
        # Check for failure indicators in output
        $failurePatterns = @(
            "Status Code 4\d{2}",
            "compilation failed",
            "Extension compilation failed",
            "FAILED:",
            "Import App .+ failed",
            "No published extensions match",
            "could not be deployed",
            "could not be reinstalled",
            "Exception calling",
            "cannot access the file",
            "being used by another process",
            "The process cannot access",
            "error AL\d+"
        )
            
        $deploymentFailed = $false
        $failureReason = ""
        foreach ($pattern in $failurePatterns) {
            if ($outputText -match $pattern) {
                $deploymentFailed = $true
                $failureReason = $Matches[0]
                break
            }
        }
            
        # Determine action based on app state
        $action = if ($DeploymentApp.IsInstalled) {
            if ($DeploymentApp.IsUpdate) { "Updated" } else { "Reinstalled" }
        }
        elseif ($DeploymentApp.NeedsInstall) {
            "Installed (was published)"
        }
        else {
            "Installed"
        }
            
        if ($deploymentFailed) {
            Write-Host "- Deployment failed: $failureReason" -ForegroundColor Red
            return [PSCustomObject]@{
                Publisher = $DeploymentApp.Publisher
                Name      = $DeploymentApp.Name
                Version   = $DeploymentApp.Version
                Scope     = $DeploymentApp.Scope
                Status    = "Failed"
                Action    = if ($DeploymentApp.IsInstalled -or $DeploymentApp.NeedsInstall) { "UpdateFailed" } else { "InstallFailed" }
                Reason    = $failureReason
            }
        }
            
        return [PSCustomObject]@{
            Publisher = $DeploymentApp.Publisher
            Name      = $DeploymentApp.Name
            Version   = $DeploymentApp.Version
            Scope     = $DeploymentApp.Scope
            Status    = "Success"
            Action    = $action
        }
    }
    catch {
        Write-Host "- Deployment failed: $($_.Exception.Message)" -ForegroundColor Red
        return [PSCustomObject]@{
            Publisher = $DeploymentApp.Publisher
            Name      = $DeploymentApp.Name
            Version   = $DeploymentApp.Version
            Scope     = $DeploymentApp.Scope
            Status    = "Failed"
            Action    = if ($DeploymentApp.IsInstalled -or $DeploymentApp.NeedsInstall) { "UpdateFailed" } else { "InstallFailed" }
            Reason    = $_.Exception.Message
        }
    }
}

function Write-DeploymentSummary {
    param(
        [Parameter(Mandatory)]
        $Results
    )

    Write-Host ""
    Write-Host "=== DEPLOYMENT SUMMARY ===" -ForegroundColor Cyan
    Write-Host ""

    $results |
    Select-Object Publisher, Name, Version, Scope, Status, Action |
    Format-Table -AutoSize

    $total = $results.Count
    $success = ($results | Where-Object { $_.Status -eq "Success" }).Count
    $failed = ($results | Where-Object { $_.Status -eq "Failed" }).Count
    $installed = ($results | Where-Object { $_.Action -eq "Installed" -and $_.Status -eq "Success" }).Count
    $updated = ($results | Where-Object { $_.Action -eq "Updated" -and $_.Status -eq "Success" }).Count

    Write-Host ""
    Write-Host "=== DEPLOYMENT STATISTICS ===" -ForegroundColor Cyan
    Write-Host ("Total apps processed:     {0}" -f $total)
    Write-Host ("Successful deployments:   {0}" -f $success) -ForegroundColor Green
    Write-Host ("Failed deployments:       {0}" -f $failed)  -ForegroundColor ($(if ($failed -gt 0) { "Red" } else { "Green" }))
    Write-Host ("New installs (success):   {0}" -f $installed)
    Write-Host ("Updates (success):        {0}" -f $updated)
        
    # Show failed apps with reasons
    $failedApps = $results | Where-Object { $_.Status -eq "Failed" }
    if ($failedApps) {
        Write-Host ""
        Write-Host "=== FAILED DEPLOYMENTS ===" -ForegroundColor Red
        foreach ($app in $failedApps) {
            Write-Host ("  {0} - {1} v{2}" -f $app.Publisher, $app.Name, $app.Version) -ForegroundColor Red
            if ($app.Reason) {
                Write-Host ("    Reason: {0}" -f $app.Reason) -ForegroundColor DarkRed
            }
        }
    }
    Write-Host ""
}

function Resolve-AppDependencies {
    <#
        .SYNOPSIS
            Recursively resolves and adds missing dependencies for all apps.
        .DESCRIPTION
            For each app in the list, checks its dependencies. If a dependency is not
            already in the list and not already installed, it finds the dependency in
            the available apps (FileShare or Microsoft container) and adds it.
            This process is recursive to handle transitive dependencies.
        #>
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]]$Apps,
        [Parameter(Mandatory)]
        $AvailableApps,
        [Parameter(Mandatory)]
        $InstalledApps,
        [Parameter(Mandatory)]
        [version]$BCVersion,
        [string[]]$FileShareBasePaths
    )

    $fileShareBasePathsNormalized = @($FileShareBasePaths | ForEach-Object { $_.Replace('/', '\').TrimEnd('\').ToLowerInvariant() })
    $processedNames = @{}
    $appsToProcess = New-Object System.Collections.Generic.Queue[object]

    # Initialize: mark all current apps as processed and queue them
    foreach ($app in $Apps) {
        if (-not $processedNames.ContainsKey($app.NormalizedName)) {
            $processedNames[$app.NormalizedName] = $true
            $appsToProcess.Enqueue($app)
        }
    }

    # Build lookup for available apps
    $availableLookup = @{}
    foreach ($avail in $AvailableApps) {
        if (-not $availableLookup.ContainsKey($avail.NormalizedName)) {
            $availableLookup[$avail.NormalizedName] = New-Object System.Collections.Generic.List[object]
        }
        $availableLookup[$avail.NormalizedName].Add($avail)
    }

    $addedCount = 0

    # Core Microsoft apps that should be skipped IF they're only found in MicrosoftContainer
    # (they're always present or replaced by custom base apps like 4PS Construct)
    # But if a version exists on FileShare, use that instead (e.g., 4PS's own Application)
    $skipIfOnlyMicrosoftContainer = @(
        "microsoft::base application",
        "microsoft::system application",
        "microsoft::system"
    )

    while ($appsToProcess.Count -gt 0) {
        $currentApp = $appsToProcess.Dequeue()

        # Lazy load dependencies if not already loaded
        $currentDeps = Get-AppDependencies -App $currentApp
        if (-not $currentDeps -or $currentDeps.Count -eq 0) {
            continue
        }

        foreach ($dep in $currentDeps) {
            $depNormalized = Normalize-AppName -Name $dep.Name -Publisher $dep.Publisher

            # Skip if already in our list (processed or queued)
            if ($processedNames.ContainsKey($depNormalized)) {
                continue
            }

            # Special case: If any app depends on "microsoft::application",
            # substitute with 4PS's own Application from FileShare (if available)
            # This ensures we use 4PS Application instead of Microsoft Application
            if ($depNormalized -eq "microsoft::application") {
                $fourPsAppNormalized = "4ps b.v.::application"
                $fourPsAppCandidate = $availableLookup[$fourPsAppNormalized] | Where-Object { $_.SourceType -eq "FileShare" } | Select-Object -First 1
                if ($fourPsAppCandidate) {
                    Write-Host ("  ~ Substituting 'microsoft::application' with '4ps b.v.::application' for app '{0}'" -f $currentApp.Name) -ForegroundColor DarkYellow
                    $depNormalized = $fourPsAppNormalized
                        
                    # Check again if already processed with the substituted name
                    if ($processedNames.ContainsKey($depNormalized)) {
                        continue
                    }
                }
            }

            # Find the dependency in available apps
            $depCandidates = $availableLookup[$depNormalized]
            if (-not $depCandidates -or $depCandidates.Count -eq 0) {
                # Not found - check if it's a core app we can skip
                if ($depNormalized -in $skipIfOnlyMicrosoftContainer) {
                    Write-Host ("  - Skipping core app: {0}::{1} (not found, assumed present)" -f $dep.Publisher, $dep.Name) -ForegroundColor DarkGray
                    continue
                }
                Write-Warning ("Dependency '{0}' (Publisher: {1}) for app '{2}' not found in any source." -f $dep.Name, $dep.Publisher, $currentApp.Name)
                continue
            }

            # Prioritize FileShare over MicrosoftContainer
            # Also filter by MinVersion requirement if specified
            $minVersion = $dep.MinVersion
                
            $fileShareCandidates = $depCandidates | Where-Object { $_.SourceType -eq "FileShare" }
            if ($fileShareCandidates -and @($fileShareCandidates).Count -gt 0) {
                # First, filter by BC compatibility (check Microsoft Application dependency)
                $bcCompatibleCandidates = $fileShareCandidates | Where-Object {
                    Test-AppBCCompatibility -App $_ -BCVersion $BCVersion
                }
                    
                if (-not $bcCompatibleCandidates -or @($bcCompatibleCandidates).Count -eq 0) {
                    Write-Warning ("No BC {0}.x compatible version of '{1}' (Publisher: {2}) found on FileShare." -f $BCVersion.Major, $dep.Name, $dep.Publisher)
                    $bcCompatibleCandidates = $fileShareCandidates  # Fall back to all candidates
                }
                    
                # Then filter candidates that meet the MinVersion requirement
                if ($minVersion) {
                    $validCandidates = $bcCompatibleCandidates | Where-Object {
                        $v = Get-AppVersion -App $_
                        $v -and $v -ge $minVersion
                    }
                    if ($validCandidates -and @($validCandidates).Count -gt 0) {
                        $bestMatch = $validCandidates | Select-LatestVersionApp
                    }
                    else {
                        # No valid candidate meets MinVersion - warn and try to use latest anyway
                        Write-Warning ("No version of '{0}' (Publisher: {1}) meets MinVersion {2}. Using latest available." -f $dep.Name, $dep.Publisher, $minVersion)
                        $bestMatch = $bcCompatibleCandidates | Select-LatestVersionApp
                    }
                }
                else {
                    $bestMatch = $bcCompatibleCandidates | Select-LatestVersionApp
                }
            }
            else {
                # Only MicrosoftContainer available - check if we should skip core apps
                if ($depNormalized -in $skipIfOnlyMicrosoftContainer) {
                    Write-Host ("  - Skipping core app: {0}::{1} (only in container, assumed present/replaced)" -f $dep.Publisher, $dep.Name) -ForegroundColor DarkGray
                    continue
                }
                $bestMatch = $depCandidates | Select-LatestVersionApp
            }

            # Lazy-load metadata for the best match (version already loaded by Select-LatestVersionApp)
            Get-AppDependencies -App $bestMatch | Out-Null
                
            # Create the expected app object for this dependency
            $depApp = [PSCustomObject]@{
                Name           = $bestMatch.Name
                Publisher      = $bestMatch.Publisher
                NormalizedName = $bestMatch.NormalizedName
                Version        = $bestMatch.Version
                SourceType     = $bestMatch.SourceType
                SourcePath     = $bestMatch.SourcePath
                Scope          = "Dev"
                Dependencies   = $bestMatch.Dependencies
            }

            # If it's from FileShare, resolve to latest version path
            $sourcePathNormalized = $depApp.SourcePath.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
            $isFileShare = $fileShareBasePathsNormalized | Where-Object { $sourcePathNormalized.StartsWith($_) }
            if ($isFileShare) {
                $depApp.SourceType = "FileShare"
            }
            elseif ($sourcePathNormalized.StartsWith('c:\applications')) {
                $depApp.SourceType = "MicrosoftContainer"
            }

            Write-Host ("  + Adding dependency: {0} - {1} (v{2}) from {3}" -f $depApp.Publisher, $depApp.Name, $depApp.Version, $depApp.SourceType) -ForegroundColor DarkCyan

            $Apps.Add($depApp)
            $processedNames[$depNormalized] = $true
            $appsToProcess.Enqueue($depApp)
            $addedCount++
        }
    }

    return $addedCount
}
# ----------------------------
# 4. Determine BC version + FileShare path
# -----------------------------

Write-Host ""
Write-Host "Determining BC version from System Application..." -ForegroundColor Green

$systemApp = Get-NAVAppInfo -ServerInstance $ServerInstance -Tenant $Tenant | Where-Object { $_.Name -eq "System Application" } | Sort-Object Version -Descending | Select-Object -First 1
if (-not $systemApp) {
    throw "System Application not found on server instance '$ServerInstance'."
}

$systemAppVersion = $systemApp.Version
$versionSelector = if ($version -in @("master", "dev")) { 0 } else { 1 }
$bcVersionFull = [version]"$($systemAppVersion.Major).$($systemAppVersion.Minor).0.$versionSelector"

Write-Host ("System Application version: {0}" -f $systemAppVersion) -ForegroundColor DarkGray
Write-Host ("Selected BC release version: {0}" -f $bcVersionFull) -ForegroundColor DarkGray

$releaseName = if ($version -eq "master") { "Master 00" } else { "Bc $(([version]$bcVersionFull).Major)" }
$releaseFolderName = "$bcVersionFull $organization $releaseName (Auto-Generated)"
$fileShareBasePath = "C:/azurefileshare/azdevops-publish/releases"
$releaseFolderPath = "$fileShareBasePath/$localization/$releaseFolderName/Software/OpenExtensions"
    
# Additional unstructured FileShare paths (apps for multiple BC versions)
$partnersPath = "C:/azurefileshare/partners"
$bcDataExtPath = "C:/azurefileshare/bc-data/extension"
    
# All FileShare base paths for path detection
$fileShareBasePaths = @(
    $fileShareBasePath,
    $partnersPath,
    $bcDataExtPath
)
    
# Unstructured folder scan settings
# - ExcludeFileNamePattern: Regex pattern to exclude files by name (e.g., "^Microsoft_" skips Microsoft_*.app)
$unstructuredFolderExcludePattern = "^Microsoft_"

Write-Host ""
Write-Host ("FileShare release folder: {0}" -f $releaseFolderPath) -ForegroundColor Green
Write-Host ("FileShare partners folder: {0}" -f $partnersPath) -ForegroundColor Green
Write-Host ("FileShare bc-data/extension folder: {0}" -f $bcDataExtPath) -ForegroundColor Green

# -----------------------------
# 5. Load sources
# -----------------------------

Write-Host ""
Write-Host "Loading installed apps..." -ForegroundColor Green
$installedApps = Get-InstalledApps -ServerInstance $ServerInstance
Write-Host ("  Loaded {0} installed app(s)" -f @($installedApps).Count) -ForegroundColor DarkGray

Write-Host "Loading published apps..." -ForegroundColor Green
$publishedApps = Get-PublishedApps -ServerInstance $ServerInstance
Write-Host ("  Loaded {0} published app(s)" -f @($publishedApps).Count) -ForegroundColor DarkGray
    
# Find apps that are published but not installed (need to be installed after publish)
$publishedOnlyApps = @($publishedApps | Where-Object {
        $norm = $_.NormalizedName
        -not ($installedApps | Where-Object { $_.NormalizedName -eq $norm })
    })
if ($publishedOnlyApps.Count -gt 0) {
    Write-Host ("  Note: {0} app(s) are published but not installed" -f $publishedOnlyApps.Count) -ForegroundColor DarkYellow
}

Write-Host "Loading apps from Microsoft container (C:\Applications)..." -ForegroundColor Green
$microsoftContainerApps = Get-AppsFromMicrosoftContainer -ApplicationsRoot "C:\Applications" -BCVersion $bcVersionFull
Write-Host ("  Loaded {0} Microsoft container app(s)" -f $microsoftContainerApps.Count) -ForegroundColor DarkGray

Write-Host "Loading apps from FileShare (OpenExtensions)..." -ForegroundColor Green
# Release folder apps - these are the main apps to deploy in syncAllAppsFromFileShare mode
$releaseApps = @(Get-AppsFromFileShare -ReleaseFolderPath $releaseFolderPath)
Write-Host ("  Loaded {0} release app(s)" -f $releaseApps.Count) -ForegroundColor DarkGray
    
Write-Host "Loading apps from FileShare (Partners)..." -ForegroundColor Green
# Partner apps - only used for dependency resolution, not added in syncAllAppsFromFileShare mode
# Partner apps often have their own versioning (not BC version), so skip BC version check
$partnersApps = @(Get-AppsFromUnstructuredFolder -FolderPath $partnersPath -BCVersion $bcVersionFull -SourceLabel "Partners" `
        -ExcludeFileNamePattern $unstructuredFolderExcludePattern -SkipBCVersionCheck)
if ($partnersApps.Count -gt 0) {
    # Debug: Show partner apps grouped by publisher with version info
    if ($DebugMode) {
        Write-Host ""
        Write-Host "  >>> Partner apps by publisher:" -ForegroundColor Yellow
        $partnersApps | Group-Object Publisher | Sort-Object Name | ForEach-Object {
            Write-Host "    $($_.Name):" -ForegroundColor Cyan
            $_.Group | Group-Object NormalizedName | ForEach-Object {
                $versions = $_.Group | ForEach-Object { 
                    $v = Get-AppVersion -App $_
                    if ($v) { $v.ToString() } else { "(no version)" }
                }
                $latestApp = $_.Group | Select-LatestVersionApp
                $latestVersion = if ($latestApp.Version) { $latestApp.Version.ToString() } else { "(lazy)" }
                Write-Host ("      {0}: versions=[{1}] -> selected={2}" -f $_.Group[0].Name, ($versions -join ", "), $latestVersion) -ForegroundColor DarkGray
            }
        }
        Write-Host ""
    }
}
    
Write-Host "Loading apps from FileShare (bc-data/extension)..." -ForegroundColor Green
# bc-data apps - only used for dependency resolution, not added in syncAllAppsFromFileShare mode
$bcDataApps = @(Get-AppsFromUnstructuredFolder -FolderPath $bcDataExtPath -BCVersion $bcVersionFull -SourceLabel "BcDataExtension")
    
# Combine all FileShare apps for lookups and dependency resolution
$fileShareApps = @($releaseApps) + @($partnersApps) + @($bcDataApps)
    
# Auxiliary apps are only used for dependency resolution, not added in syncAllAppsFromFileShare
$auxiliaryApps = @($partnersApps) + @($bcDataApps)
    
Write-Host ("  Total FileShare apps: {0} (Release: {1}, Partners: {2}, BcData: {3})" -f $fileShareApps.Count, $releaseApps.Count, $partnersApps.Count, $bcDataApps.Count) -ForegroundColor DarkGray
Write-Host ("  Note: Only release apps are added in syncAllAppsFromFileShare mode. Partners/BcData apps are used for dependency resolution only." ) -ForegroundColor DarkGray

# Available apps = FileShare apps + Microsoft container apps (for dependency resolution)
$availableApps = @($fileShareApps) + @($microsoftContainerApps)

# -----------------------------
# 6. Build expected apps from artifacts
# -----------------------------

Write-Host ""
Write-Host "Loading artifacts from environment..." -ForegroundColor Green
$artifactsResult = Get-ArtifactsFromEnvironment
$artifacts = @($artifactsResult | Where-Object { $_.target -eq "app" }  | Sort-Object Url -Unique)

Write-Host ("{0} artifact(s) found." -f $artifacts.Count) -ForegroundColor DarkGray

$expectedApps = New-Object System.Collections.Generic.List[object]

foreach ($artifact in $artifacts) {
    $expected = Convert-ArtifactToExpectedAppSkeleton -Artifact $artifact
    if ($expected) {
        $expectedApps.Add($expected)
    }
    else {
        # Non-app or failed to parse; ignore
        continue
    }
}

# Deduplicate: keep only the latest version per NormalizedName
Write-Host "Deduplicating apps (keeping latest version per app name)..." -ForegroundColor Green
$deduplicatedApps = $expectedApps |
Group-Object -Property NormalizedName |
ForEach-Object {
    $_.Group | Select-LatestVersionApp
}
    
$expectedApps = New-Object System.Collections.Generic.List[object]
foreach ($app in $deduplicatedApps) {
    $expectedApps.Add($app)
}

Write-Host ("{0} unique app(s) after deduplication." -f $expectedApps.Count) -ForegroundColor DarkGray

# -----------------------------
# 6b. Enrich expected apps with dependency info from available apps
# -----------------------------
# The artifacts may not have dependency info, so we enrich from the available apps
# which have been properly scanned with Get-NAVAppInfo

Write-Host ""
Write-Host "Enriching expected apps with dependency information..." -ForegroundColor Green

# Build lookup for available apps
$availableAppsLookup = @{}
foreach ($avail in $availableApps) {
    if (-not $availableAppsLookup.ContainsKey($avail.NormalizedName)) {
        $availableAppsLookup[$avail.NormalizedName] = New-Object System.Collections.Generic.List[object]
    }
    $availableAppsLookup[$avail.NormalizedName].Add($avail)
}

for ($i = 0; $i -lt $expectedApps.Count; $i++) {
    $app = $expectedApps[$i]
        
    # If dependencies are empty or missing, try to get them from available apps
    if (-not $app.Dependencies -or $app.Dependencies.Count -eq 0) {
        $candidates = $availableAppsLookup[$app.NormalizedName]
        if ($candidates -and $candidates.Count -gt 0) {
            # Get the version that matches or the latest
            $matchingVersion = $null
            if ($app.Version) {
                # Try to find an exact version match (lazy-load candidate versions)
                foreach ($candidate in $candidates) {
                    $candidateVersion = Get-AppVersion -App $candidate
                    if ($candidateVersion -eq $app.Version) {
                        $matchingVersion = $candidate
                        break
                    }
                }
            }
            if (-not $matchingVersion) {
                $matchingVersion = $candidates | Select-LatestVersionApp
            }
                
            if ($matchingVersion) {
                # Lazy load dependencies if needed
                $deps = Get-AppDependencies -App $matchingVersion
                if ($deps -and $deps.Count -gt 0) {
                    Write-Host ("  Enriching '{0}' with {1} dependencies from {2}" -f $app.Name, $deps.Count, $matchingVersion.SourceType) -ForegroundColor DarkGray
                    $app.Dependencies = $deps
                    $expectedApps[$i] = $app
                }
            }
        }
    }
}

# -----------------------------
# 6c. Resolve dependencies (before FileShare path resolution)
# -----------------------------

# Filter by DependsOnApp BEFORE resolving dependencies (so only filtered apps' dependencies are resolved)
if (-not [string]::IsNullOrWhiteSpace($DependsOnApp)) {
    Write-Host ""
    Write-Host ("Filtering apps depending on: '{0}' (before dependency resolution)..." -f $DependsOnApp) -ForegroundColor Green
        
    $beforeFilterCount = $expectedApps.Count
    $filteredApps = New-Object System.Collections.Generic.List[object]
        
    foreach ($app in $expectedApps) {
        $deps = Get-AppDependencies -App $app
        if ($deps -and $deps.Count -gt 0) {
            $hasDependency = $deps | Where-Object { $_.Name -eq $DependsOnApp }
            if ($hasDependency) {
                $filteredApps.Add($app)
            }
        }
    }
        
    $expectedApps = $filteredApps
    $removedCount = $beforeFilterCount - $expectedApps.Count
        
    Write-Host ("{0} app(s) match the dependency filter, {1} app(s) filtered out." -f $expectedApps.Count, $removedCount) -ForegroundColor DarkGray
        
    if ($DebugMode) {
        foreach ($fApp in $expectedApps) {
            Write-Host ("  ✓ {0} - {1}" -f $fApp.Publisher, $fApp.Name) -ForegroundColor Cyan
        }
    }
        
    if ($expectedApps.Count -eq 0) {
        Write-Warning "No apps found with dependency on '$DependsOnApp'. Deployment will be empty."
    }
}

# Resolve dependencies (AFTER filtering, so only filtered apps' dependencies are added)
Write-Host ""
Write-Host "Resolving dependencies for all apps..." -ForegroundColor Green
$dependenciesAdded = Resolve-AppDependencies `
    -Apps $expectedApps `
    -AvailableApps $availableApps `
    -InstalledApps $installedApps `
    -BCVersion $bcVersionFull `
    -FileShareBasePaths $fileShareBasePaths

Write-Host ("{0} dependency app(s) added." -f $dependenciesAdded) -ForegroundColor DarkGray
Write-Host ("{0} total app(s) after dependency resolution." -f $expectedApps.Count) -ForegroundColor DarkGray

# -----------------------------
# 6d. Resolve FileShare app paths to latest available versions
# -----------------------------

# For FileShare apps, resolve to the latest available version on the FileShare
Write-Host ""
Write-Host "Resolving FileShare app paths to latest available versions..." -ForegroundColor Green
$fileShareBasePathsNormalized = @($fileShareBasePaths | ForEach-Object { $_.Replace('/', '\').TrimEnd('\').ToLowerInvariant() })
    
for ($i = 0; $i -lt $expectedApps.Count; $i++) {
    $app = $expectedApps[$i]
        
    # Normalize the source path for comparison
    $sourcePathNormalized = $app.SourcePath.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
        
    # Check if this app should be resolved from FileShare (4PS apps, not Microsoft container apps)
    $isFileShare = $fileShareBasePathsNormalized | Where-Object { $sourcePathNormalized.StartsWith($_) }
    if ($isFileShare) {
        # Find the latest version of this app in the available FileShare apps
        $latestFromFileShare = $fileShareApps | 
        Where-Object { $_.NormalizedName -eq $app.NormalizedName } |
        Select-LatestVersionApp
            
        if ($latestFromFileShare) {
            # Ensure dependencies are loaded for the selected app
            Get-AppDependencies -App $latestFromFileShare | Out-Null
                
            Write-Host ("  Updating '{0}' -> v{1} at {2}" -f $app.Name, $latestFromFileShare.Version, $latestFromFileShare.SourcePath) -ForegroundColor DarkGray
            $app.Version = $latestFromFileShare.Version
            $app.SourcePath = $latestFromFileShare.SourcePath
            $app.SourceType = "FileShare"  # Update source type since we're now using FileShare path
            $app.Dependencies = $latestFromFileShare.Dependencies
            $expectedApps[$i] = $app
        }
        else {
            Write-Warning ("App '{0}' (Publisher: {1}) not found on FileShare at '{2}'" -f $app.Name, $app.Publisher, $releaseFolderPath)
        }
    }
}

if ($expectedApps.Count -eq 0) {
    Write-Warning "No ExpectedApps built from artifacts. Nothing to deploy based on initial Container configuration."
}

# Debug: Show state of all collections
if ($DebugMode) {
    Write-Host ""
    Write-Host ">>> DEBUG: Collection States <<<" -ForegroundColor Yellow
    Write-Host "=" * 80 -ForegroundColor Yellow
        
    Write-Host ""
    Write-Host "Installed Apps ($($installedApps.Count)):" -ForegroundColor Cyan
    foreach ($app in $installedApps | Sort-Object Publisher, Name) {
        Write-Host ("  [{0}] {1} - {2} v{3}" -f $app.Scope, $app.Publisher, $app.Name, $app.Version) -ForegroundColor DarkGray
    }
        
    Write-Host ""
    Write-Host "FileShare Apps ($($fileShareApps.Count)):" -ForegroundColor Cyan
    foreach ($app in $fileShareApps | Sort-Object Publisher, Name) {
        Write-Host ("  {0} - {1} v{2}" -f $app.Publisher, $app.Name, $app.Version) -ForegroundColor DarkGray
    }
        
    Write-Host ""
    Write-Host "Expected Apps after processing ($($expectedApps.Count)):" -ForegroundColor Cyan
    foreach ($app in $expectedApps | Sort-Object Publisher, Name) {
        Write-Host ("  {0} - {1} v{2} [{3}]" -f $app.Publisher, $app.Name, $app.Version, $app.SourcePath) -ForegroundColor DarkGray
    }
        
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Yellow
}

# -----------------------------
# 7. Resolve source + scope
# -----------------------------

Write-Host ""
Write-Host "Resolving source and scope for expected apps..." -ForegroundColor Green

for ($i = 0; $i -lt $expectedApps.Count; $i++) {
    $app = $expectedApps[$i]

    $app = Resolve-AppSource -ExpectedApp $app -AvailableApps $availableApps
    $app = Resolve-AppScope  -ExpectedApp $app -InstalledApps $installedApps -PublishedApps $publishedApps

    $expectedApps[$i] = $app
}

# -----------------------------
# 8. Build deployment apps
# -----------------------------

Write-Host ""
Write-Host "Preparing deployment apps..." -ForegroundColor Green

$deploymentApps = foreach ($app in $expectedApps) {
    Prepare-DeploymentApp -ExpectedApp $app -InstalledApps $installedApps -PublishedApps $publishedApps
}

Write-Host ""
Write-Host ("Applying deployment mode: {0}" -f $Mode) -ForegroundColor Green

switch ($Mode) {
    'updateExistingApps' {
        foreach ($installed in $installedApps) {
            $match = $availableApps | Where-Object {
                $_.Publisher -eq $installed.Publisher -and
                $_.NormalizedName -eq $installed.NormalizedName
            }
            if (-not $match) {
                Warn-AppNotFoundInSources -App $installed
            }
        }

        $updatesFromFileShare = New-Object System.Collections.Generic.List[object]
            
        foreach ($installed in $installedApps) {
            # Skip if already in deploymentApps (from artifacts)
            $alreadyInDeployment = $deploymentApps | Where-Object {
                $_.NormalizedName -eq $installed.NormalizedName
            }
            if ($alreadyInDeployment) {
                continue
            }
                
            # Find latest BC-compatible version in FileShare (release apps only)
            $fsVersions = $releaseApps | Where-Object {
                $_.NormalizedName -eq $installed.NormalizedName
            }
                
            if ($fsVersions) {
                # Filter by BC compatibility and select latest
                $bcCompatible = $fsVersions | Where-Object {
                    Test-AppBCCompatibility -App $_ -BCVersion $bcVersionFull
                }
                    
                if ($bcCompatible -and @($bcCompatible).Count -gt 0) {
                    $latestFs = $bcCompatible | Select-LatestVersionApp
                    $latestFsVersion = Get-AppVersion -App $latestFs
                        
                    if ($latestFsVersion -gt $installed.Version) {
                        Write-Host ("  + Adding update for installed app: {0} - {1} (v{2} -> v{3})" -f $installed.Publisher, $installed.Name, $installed.Version, $latestFsVersion) -ForegroundColor Cyan
                            
                        # Create expected app entry for this update
                        $updateApp = [PSCustomObject]@{
                            Name           = $latestFs.Name
                            Publisher      = $latestFs.Publisher
                            NormalizedName = $latestFs.NormalizedName
                            Version        = $latestFsVersion
                            SourceType     = "FileShare"
                            SourcePath     = $latestFs.SourcePath
                            Scope          = $installed.Scope
                            Dependencies   = $null
                        }
                            
                        # Resolve dependencies
                        $updateApp = Resolve-AppSource -ExpectedApp $updateApp -AvailableApps $availableApps
                        $updateApp = Resolve-AppScope -ExpectedApp $updateApp -InstalledApps $installedApps -PublishedApps $publishedApps
                            
                        $updatesFromFileShare.Add($updateApp)
                    }
                }
            }
        }
            
        if ($updatesFromFileShare.Count -gt 0) {
            Write-Host ("  Found {0} installed app(s) with newer versions in FileShare" -f $updatesFromFileShare.Count) -ForegroundColor Cyan
                
            # Add updates to deploymentApps
            foreach ($updateApp in $updatesFromFileShare) {
                $deployApp = Prepare-DeploymentApp -ExpectedApp $updateApp -InstalledApps $installedApps -PublishedApps $publishedApps
                $deploymentApps += $deployApp
            }
        }
        else {
            Write-Host "  No additional updates found for installed apps" -ForegroundColor DarkGray
        }
    }

    'syncAllAppsFromFileShare' {
        # Warn for installed apps that cannot be resolved in any source
        foreach ($installed in $installedApps) {
            $match = $availableApps | Where-Object {
                $_.Publisher -eq $installed.Publisher -and
                $_.NormalizedName -eq $installed.NormalizedName
            }

            if (-not $match) {
                Warn-AppNotFoundInSources -App $installed
            }
        }

        # syncAllAppsFromFileShare mode:
        # - everything from updateExistingApps
        # - plus all apps from FileShare release folder (OpenExtensions) that are not already in ExpectedApps
        #   but only if they are BC-compatible (check Microsoft::Application dependency)
        # - Partner/bc-data apps are NOT added here - they are only used for dependency resolution
            
        # Group release folder apps by NormalizedName and select latest BC-compatible version per app
        # Also track which apps are skipped for logging
        $skippedApps = New-Object System.Collections.Generic.List[object]
            
        # Only use $releaseApps here, not $fileShareApps (which includes partners/bc-data)
        $latestReleaseApps = $releaseApps | 
        Group-Object -Property NormalizedName | 
        ForEach-Object {
            # Filter by BC compatibility first, then select latest
            $bcCompatible = $_.Group | Where-Object {
                Test-AppBCCompatibility -App $_ -BCVersion $bcVersionFull
            }
            if ($bcCompatible -and @($bcCompatible).Count -gt 0) {
                $bcCompatible | Select-LatestVersionApp
            }
            else {
                # No BC-compatible version - track for logging
                $latest = $_.Group | Select-LatestVersionApp
                if ($latest) {
                    $skippedApps.Add($latest)
                }
                $null
            }
        } | Where-Object { $_ -ne $null }
            
        if ($skippedApps.Count -gt 0) {
            Write-Host ("  Skipped {0} app(s) not compatible with BC {1}.x:" -f $skippedApps.Count, $bcVersionFull.Major) -ForegroundColor DarkYellow
            foreach ($skipped in $skippedApps | Sort-Object Publisher, Name) {
                # Get the BC dependency to show why it's incompatible
                $deps = Get-AppDependencies -App $skipped
                $bcDep = $deps | Where-Object { $_.Publisher -eq "Microsoft" -and $_.Name -eq "Application" } | Select-Object -First 1
                $bcReq = if ($bcDep -and $bcDep.MinVersion) { "BC {0}.x" -f $bcDep.MinVersion.Major } else { "unknown" }
                Write-Host ("    - {0} - {1} v{2} (requires {3})" -f $skipped.Publisher, $skipped.Name, $skipped.Version, $bcReq) -ForegroundColor DarkGray
            }
        }
            
        if ($auxiliaryApps.Count -gt 0) {
            Write-Host ("  Note: {0} partner/bc-data app(s) available for dependency resolution only" -f $auxiliaryApps.Count) -ForegroundColor DarkGray
        }

        foreach ($fsApp in $latestReleaseApps) {
            $exists = $deploymentApps | Where-Object {
                $_.Publisher -eq $fsApp.Publisher -and
                $_.NormalizedName -eq $fsApp.NormalizedName
            }

            if (-not $exists) {
                # Lazy-load metadata for this FileShare app (version already loaded by Select-LatestVersionApp)
                Get-AppDependencies -App $fsApp | Out-Null
                    
                $extraExpected = [PSCustomObject]@{
                    Name           = $fsApp.Name
                    Publisher      = $fsApp.Publisher
                    NormalizedName = $fsApp.NormalizedName
                    Version        = $fsApp.Version
                    SourceType     = $fsApp.SourceType
                    SourcePath     = $fsApp.SourcePath
                    Scope          = $fsApp.Scope
                    Dependencies   = $fsApp.Dependencies
                }

                $extraExpected = Resolve-AppScope -ExpectedApp $extraExpected -InstalledApps $installedApps -PublishedApps $publishedApps
                $deploymentApps += Prepare-DeploymentApp -ExpectedApp $extraExpected -InstalledApps $installedApps -PublishedApps $publishedApps
            }
        }
            
        # Resolve dependencies for newly added apps (including partner apps like Continia)
        # Convert deploymentApps to list for Resolve-AppDependencies
        Write-Host ""
        Write-Host "Resolving dependencies for syncAllAppsFromFileShare apps (including partner apps)..." -ForegroundColor Green
            
        $syncAllExpectedApps = New-Object System.Collections.Generic.List[object]
        foreach ($app in $deploymentApps) {
            $syncAllExpectedApps.Add($app)
        }
            
        $syncAllDepsAdded = Resolve-AppDependencies `
            -Apps $syncAllExpectedApps `
            -AvailableApps $availableApps `
            -InstalledApps $installedApps `
            -BCVersion $bcVersionFull `
            -FileShareBasePaths $fileShareBasePaths
            
        if ($syncAllDepsAdded -gt 0) {
            Write-Host ("{0} additional dependency app(s) added (e.g., partner apps like Continia)." -f $syncAllDepsAdded) -ForegroundColor DarkGray
        }

        for ($i = 0; $i -lt $syncAllExpectedApps.Count; $i++) {
            $app = $syncAllExpectedApps[$i]
            $syncAllExpectedApps[$i] = Resolve-AppScope -ExpectedApp $app -InstalledApps $installedApps -PublishedApps $publishedApps
        }
            
        # Convert back to array for deployment
        $deploymentApps = $syncAllExpectedApps.ToArray()
    }

    default {
        throw "Unknown deployment mode: '$Mode'. Valid: updateExistingApps | syncAllAppsFromFileShare"
    }
}

# -----------------------------
# 9b. Filter out apps already at same version
# -----------------------------
# Don't deploy apps that are already installed at the exact same version
# BUT: Apps that are published but not installed (NeedsInstall) should still be deployed

$beforeFilterCount = $deploymentApps.Count
$deploymentApps = @($deploymentApps | Where-Object {
        # Keep if: needs update, needs install (published but not installed), or not present at all
        $_.IsUpdate -or $_.NeedsInstall -or (-not $_.IsInstalled -and -not $_.IsPublished)
    })
$skippedCount = $beforeFilterCount - $deploymentApps.Count

if ($skippedCount -gt 0) {
    Write-Host ""
    Write-Host ("Skipped {0} app(s) already installed at same version." -f $skippedCount) -ForegroundColor DarkGray
}

# -----------------------------
# 10. Determine deployment order
# -----------------------------

Write-Host ""
Write-Host "Determining deployment order..." -ForegroundColor Green
$deploymentApps = Resolve-DeploymentOrder -DeploymentApps $deploymentApps -AllAvailableApps $fileShareApps -InstalledApps $installedApps

# -----------------------------
# 10b. Copy FileShare apps to local folder
# -----------------------------
# Copy apps from FileShare to local folder to prevent file locking/moving issues
# Only copy new/changed files and remove files no longer needed

$localAppFolder = "C:\temp\appsToDeploy"
    
Write-Host ""
Write-Host "Syncing FileShare apps to local folder..." -ForegroundColor Green

# Create folder if it doesn't exist
if (-not (Test-Path $localAppFolder)) {
    New-Item -Path $localAppFolder -ItemType Directory -Force | Out-Null
}

$fileShareBasePathsNormalized = @($fileShareBasePaths | ForEach-Object { $_.Replace('/', '\').TrimEnd('\').ToLowerInvariant() })

# Build list of expected local filenames
$expectedLocalFiles = @{}
$filesToCopy = New-Object System.Collections.Generic.List[object]
    
for ($i = 0; $i -lt $deploymentApps.Count; $i++) {
    $app = $deploymentApps[$i]
        
    if ($app.SourceType -eq "FileShare") {
        $sourcePathNormalized = $app.SourcePath.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
            
        $isFileShare = $fileShareBasePathsNormalized | Where-Object { $sourcePathNormalized.StartsWith($_) }
        if ($isFileShare) {
            # Use unique name to avoid collisions: Publisher_Name_Version.app
            $uniqueFileName = "{0}_{1}_{2}.app" -f ($app.Publisher -replace '[^\w]', ''), ($app.Name -replace '[^\w]', ''), $app.Version
            $localPath = Join-Path $localAppFolder $uniqueFileName
                
            $expectedLocalFiles[$uniqueFileName] = $true
            $filesToCopy.Add([PSCustomObject]@{
                    Index      = $i
                    App        = $app
                    SourcePath = $app.SourcePath
                    LocalPath  = $localPath
                    FileName   = $uniqueFileName
                })
        }
    }
}
    
# Get existing files in local folder
$existingFiles = @{}
Get-ChildItem -Path $localAppFolder -Filter "*.app" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $existingFiles[$_.Name] = $_
}
    
# Remove files that are no longer needed
$removedCount = 0
foreach ($existingFile in $existingFiles.Keys) {
    if (-not $expectedLocalFiles.ContainsKey($existingFile)) {
        $filePath = Join-Path $localAppFolder $existingFile
        try {
            Remove-Item -Path $filePath -Force -ErrorAction Stop
            $removedCount++
            Write-Host ("  Removed: {0}" -f $existingFile) -ForegroundColor DarkGray
        }
        catch {
            Write-Warning ("Failed to remove '{0}': {1}" -f $existingFile, $_.Exception.Message)
        }
    }
}
    
if ($removedCount -gt 0) {
    Write-Host ("  Removed {0} obsolete app(s)" -f $removedCount) -ForegroundColor DarkGray
}
    
# Copy only files that don't exist or have different size
$copiedCount = 0
$skippedCount = 0
    
foreach ($item in $filesToCopy) {
    $needsCopy = $true
        
    # Check if file already exists with same size
    if ($existingFiles.ContainsKey($item.FileName)) {
        $existingFile = $existingFiles[$item.FileName]
        $sourceFile = Get-Item -Path $item.SourcePath -ErrorAction SilentlyContinue
            
        if ($sourceFile -and $existingFile.Length -eq $sourceFile.Length) {
            # Same size - assume same file, skip copy
            $needsCopy = $false
            $skippedCount++
        }
    }
        
    if ($needsCopy) {
        try {
            Copy-Item -Path $item.SourcePath -Destination $item.LocalPath -Force
            $copiedCount++
            Write-Host ("  Copied: {0} -> {1}" -f $item.App.Name, $item.FileName) -ForegroundColor DarkGray
        }
        catch {
            Write-Warning ("Failed to copy '{0}' to local folder: {1}" -f $item.App.Name, $_.Exception.Message)
        }
    }
        
    # Update the app's source path to the local copy
    $deploymentApps[$item.Index].SourcePath = $item.LocalPath
}

Write-Host ("  Copied: {0}, Skipped (already exists): {1}, Removed: {2}" -f $copiedCount, $skippedCount, $removedCount) -ForegroundColor DarkGray

[System.GC]::Collect()
[System.GC]::WaitForPendingFinalizers()
Start-Sleep -Milliseconds 500

Write-Host ""
Write-Host "Starting deployment..." -ForegroundColor Green

if ($DebugMode) {
    Write-Host ""
    Write-Host ">>> DEBUG: Apps to Deploy <<<" -ForegroundColor Yellow
        
    $i = 0
    foreach ($app in $deploymentApps) {
        $i++
        Write-Host "[$i] $($app.Publisher) - $($app.Name) v$($app.Version) [$($app.SourceType)]" -ForegroundColor Cyan
    }
    Write-Host ""
        
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Yellow
    Write-Host ">>> DEBUG: Skipping actual deployment <<<" -ForegroundColor Yellow
        
    # Create mock results for summary - determine action based on state
    $results = @(foreach ($app in $deploymentApps) {
            $action = if ($app.IsInstalled) {
                if ($app.IsUpdate) { "Updated" } else { "Reinstalled" }
            }
            elseif ($app.NeedsInstall) {
                "Installed (was published)"
            }
            else {
                "Installed"
            }
            [PSCustomObject]@{
                Name      = $app.Name
                Publisher = $app.Publisher
                Version   = $app.Version
                Action    = $action
                Status    = "Skipped (Debug Mode)"
                Message   = "Would deploy from: $($app.SourcePath)"
            }
        })
}
else {
    $appIndex = 0
    $totalApps = $deploymentApps.Count
    $results = @(foreach ($app in $deploymentApps) {
            $appIndex++
            $result = Deploy-App -DeploymentApp $app `
                -ServerInstance $ServerInstance `
                -Tenant $Tenant `
                -Credential $Credential `
                -ContainerId $containerId
            $result
        })
}

if ($results.Count -eq 0) {
    Write-Host ""
    Write-Host "No apps to deploy - everything is up to date!" -ForegroundColor Green
}
else {
    Write-DeploymentSummary -Results $results
}

Write-Host ""
Write-Host "App deployment completed." -ForegroundColor Green
