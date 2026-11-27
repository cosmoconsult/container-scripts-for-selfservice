BeforeAll {
    $script:importArtifactsPath = Join-Path $PSScriptRoot '../artifacts/ArtifactHandling/Import-Artifacts.ps1'
    $script:importArtifactsScript = Get-Content -LiteralPath $script:importArtifactsPath -Raw
    $script:importArtifactsScript = $script:importArtifactsScript -replace '(?m)^Export-ModuleMember -Function Import-Artifacts\s*$', ''
    . ([scriptblock]::Create($script:importArtifactsScript))

    function global:Get-TelemetryClient { $null }
    function global:Add-ArtifactsLog {}
    function global:Get-ArtifactJson { $null }
    function global:Invoke-LogOperation {}

    function global:Get-AppFilesSortedByDependencies {
        [CmdletBinding()]
        param([string]$Path, [int]$Depth, [string]$Filter, [string]$ExcludeExpr)
        $global:importArtifactsApps
    }

    function global:Import-AppArtifact {
        [CmdletBinding()]
        param(
            [Parameter(ValueFromPipeline)][object]$App,
            [string]$ServerInstance,
            [string]$Tenant,
            [string]$DatabaseServer,
            [string]$Scope,
            [string]$SyncMode,
            [object]$telemetryClient,
            [bool]$IsModifiedBaseApp,
            [string]$DevEndpointUrl,
            [string]$DevEndpointUser,
            [string]$DevEndpointPassword,
            [switch]$SkipServiceRestartCheck
        )
        process {
            if ($global:importArtifactsAppFailure) {
                Write-Error $global:importArtifactsAppFailure
            }
        }
    }

    function global:Import-Fonts {
        [CmdletBinding()]
        param(
            [string[]]$Path,
            [string]$NavServiceName,
            [string]$ServerInstance,
            [string]$Tenant,
            [object]$telemetryClient
        )
        $global:importArtifactsFontImportCalls++
    }

    function New-ImportArtifactsFixture {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path $path | Out-Null
        $appPath = Join-Path $path 'app.app'
        Set-Content -LiteralPath $appPath -Value 'app'
        Set-Content -LiteralPath (Join-Path $path 'font.ttf') -Value 'font'
        $global:importArtifactsApps = @(
            [PSCustomObject]@{
                AppId = [guid]::NewGuid()
                Version = [version]'1.0.0.0'
                Name = 'Test App'
                Publisher = 'Test Publisher'
                ProcessOrder = 0
                Dependencies = @()
                Path = $appPath
            }
        )
        $path
    }
}

Describe 'Import-Artifacts error contract' {
    BeforeEach {
        $global:importArtifactsAppFailure = 'App import failed'
        $global:importArtifactsFontImportCalls = 0
    }

    It 'throws a nested non-terminating import error when ThrowErrors is enabled' {
        $path = New-ImportArtifactsFixture

        {
            Import-Artifacts -Path $path -NavServiceName 'BC' -ThrowErrors $true
        } | Should -Throw '*App import failed*'

        $global:importArtifactsFontImportCalls | Should -Be 0
    }

    It 'makes a nested non-terminating import error terminating with ErrorAction Stop' {
        $path = New-ImportArtifactsFixture

        {
            Import-Artifacts -Path $path -NavServiceName 'BC' -ErrorAction Stop
        } | Should -Throw '*App import failed*'

        $global:importArtifactsFontImportCalls | Should -Be 0
    }

    It 'preserves startup continuation with SilentlyContinue' {
        $path = New-ImportArtifactsFixture

        Import-Artifacts -Path $path -NavServiceName 'BC' -ErrorAction SilentlyContinue

        $global:importArtifactsFontImportCalls | Should -Be 1
    }
}
