BeforeAll {
    $script:deploymentPath = Join-Path $PSScriptRoot '../artifacts/Invoke-ArtifactDeployment.ps1'
    $script:deploymentScript = Get-Content -LiteralPath $script:deploymentPath -Raw
    $script:deploymentScript = $script:deploymentScript.
        Replace('C:\run\prompt.ps1 -silent', 'Test-ArtifactDeploymentPrompt -Silent').
        Replace("Import-Module 'C:\run\PPIArtifactUtils.psd1' -Force -ErrorAction Stop", 'Test-ArtifactDeploymentModuleImport').
        Replace(". 'C:\run\my\ExtendedEnvironment.ps1' # NuGet feeds are configured in the extended environment", 'Test-ArtifactDeploymentExtendedEnvironment').
        Replace('Install-NuGetTools', 'Test-ArtifactDeploymentInstallNuGetTools').
        Replace('Initialize-NuGetFeeds', 'Test-ArtifactDeploymentInitializeNuGetFeeds').
        Replace('Resolve-NuGetArtifactsFromLocalAppFiles', 'Test-ArtifactDeploymentResolveNuGetArtifacts').
        Replace('Invoke-DownloadArtifact', 'Test-ArtifactDeploymentDownload').
        Replace('Import-Artifacts', 'Test-ArtifactDeploymentImport')

    function global:Test-ArtifactDeploymentPrompt {
        param([switch]$Silent)
    }

    function global:Test-ArtifactDeploymentModuleImport {
    }

    function global:Test-ArtifactDeploymentExtendedEnvironment {
        $global:artifactDeploymentEnvironmentCalls++
    }

    function global:Test-ArtifactDeploymentInstallNuGetTools {}
    function global:Test-ArtifactDeploymentInitializeNuGetFeeds {}

    function global:Test-ArtifactDeploymentResolveNuGetArtifacts {
        param($Artifacts, $ServiceTierFolder)
        $global:artifactDeploymentResolvedNames = @($Artifacts | ForEach-Object name)
        return $Artifacts
    }

    function global:Get-NAVServiceTierFolder {
        'C:\service'
    }

    function global:Test-ArtifactDeploymentDownload {
        [CmdletBinding()]
        param (
            [Parameter(ValueFromPipeline)]
            [object]$InputObject,
            [object[]]$AllArtifacts,
            [string]$Destination,
            [switch]$GroupByDependency,
            [string]$ServiceTierFolder,
            [switch]$SkipServiceRestartCheck,
            [switch]$ThrowOnError,
            [switch]$ValidateArtifact
        )
        begin {
            $global:artifactDeploymentDownloadCalls++
            $global:artifactDeploymentDownloadItems = @()
            $global:artifactDeploymentDownloadOptions = @{
                AllArtifacts = $AllArtifacts
                Destination = $Destination
                GroupByDependency = $GroupByDependency
            }
        }
        process {
            $global:artifactDeploymentDownloadItems += $InputObject
        }
    }

    function global:Test-ArtifactDeploymentImport {
        [CmdletBinding()]
        param (
            [string]$Path,
            [string]$NavServiceName,
            [string]$ServerInstance,
            [string]$Scope,
            [string]$SyncMode,
            [bool]$ExcludeApps,
            [bool]$ThrowErrors,
            [switch]$SkipSharedFontImport,
            [switch]$SkipServiceRestartCheck,
            [string]$DevEndpointUrl,
            [string]$DevEndpointUser,
            [string]$DevEndpointPassword
        )
        $global:artifactDeploymentImportCalls++
        $global:artifactDeploymentThrowErrors = $ThrowErrors
        $global:artifactDeploymentErrorAction = $ErrorActionPreference
        if ($global:artifactDeploymentImportError) {
            Write-Error $global:artifactDeploymentImportError
        }
    }

    function Invoke-TestArtifactDeployment {
        param([hashtable]$Manifest)

        $deploymentRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $deploymentRoot | Out-Null
        $Manifest | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $deploymentRoot 'manifest.json')
        $ErrorActionPreference = 'Continue'
        & ([scriptblock]::Create($script:deploymentScript)) -DeploymentPath $deploymentRoot
    }
}

Describe 'Invoke-ArtifactDeployment' {
    BeforeEach {
        $global:artifactDeploymentEnvironmentCalls = 0
        $global:artifactDeploymentDownloadCalls = 0
        $global:artifactDeploymentImportCalls = 0
        $global:artifactDeploymentThrowErrors = $false
        $global:artifactDeploymentErrorAction = $null
        $global:artifactDeploymentImportError = $null
        $global:artifactDeploymentDownloadItems = @()
        $global:artifactDeploymentDownloadOptions = $null
        $global:artifactDeploymentResolvedNames = @()
    }

    It 'downloads the manifest artifacts in one pipeline with NuGet last and the shared general-folder layout' {
        $manifest = @{
            artifacts = @(
                @{ name = 'first-app'; type = 'url'; target = 'app'; url = 'https://example.test/first.app' }
                @{ name = 'first-nuget'; type = 'nuget'; target = 'app' }
                @{ name = 'font'; type = 'url'; target = 'fonts'; url = 'https://example.test/font.zip' }
                @{ name = 'second-nuget'; type = 'nuget'; target = 'app' }
            )
            devopsArtifacts = @(
                @{ name = 'devops-addin'; type = 'upack'; target = 'dll' }
            )
        }

        Invoke-TestArtifactDeployment -Manifest $manifest | Out-Null

        $global:artifactDeploymentDownloadCalls | Should -Be 1
        @($global:artifactDeploymentDownloadItems | ForEach-Object name) | Should -Be @(
            'first-app', 'font', 'devops-addin', 'first-nuget', 'second-nuget'
        )
        @($global:artifactDeploymentDownloadOptions.AllArtifacts | ForEach-Object name) | Should -Be @(
            'first-app', 'font', 'devops-addin', 'first-nuget', 'second-nuget'
        )
        $global:artifactDeploymentDownloadOptions.GroupByDependency | Should -BeTrue
        $global:artifactDeploymentResolvedNames | Should -Be @(
            'first-app', 'font', 'devops-addin', 'first-nuget', 'second-nuget'
        )
        $global:artifactDeploymentImportCalls | Should -Be 1
    }

    It 'uses ErrorAction Stop alone to fail deployment on import errors' {
        $global:artifactDeploymentImportError = 'App import failed'
        $manifest = @{
            artifacts = @(
                @{ name = 'first-app'; type = 'url'; target = 'app'; url = 'https://example.test/first.app' }
            )
            devopsArtifacts = @()
        }

        { Invoke-TestArtifactDeployment -Manifest $manifest } | Should -Throw '*App import failed*'
        $global:artifactDeploymentImportCalls | Should -Be 1
        $global:artifactDeploymentThrowErrors | Should -BeFalse
        $global:artifactDeploymentErrorAction | Should -Be ([System.Management.Automation.ActionPreference]::Stop)
    }
}
