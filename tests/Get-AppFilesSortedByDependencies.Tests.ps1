BeforeAll {
    $repositoryRoot = Split-Path $PSScriptRoot -Parent
    $script:testModule = New-Module -Name ArtifactDependencyTests -ArgumentList $repositoryRoot -ScriptBlock {
        param($RepositoryRoot)

        function Get-NAVAppInfo {
            [CmdletBinding()]
            param([string]$Path)

            if ([System.IO.Path]::GetFileName($Path) -eq 'invalid.app') {
                Write-Error 'Invalid app metadata'
                return
            }
            [PSCustomObject]@{
                AppId = [guid]'ac6bb1ca-8c11-4fc7-a290-20b650539d69'
                Name = 'Valid app'
                Publisher = 'Test publisher'
                Version = '1.0.0.0'
                Dependencies = @()
            }
        }

        . (Join-Path $RepositoryRoot 'artifacts/ArtifactHandling/Get-AppFilesSortedByDependencies.ps1')
        . (Join-Path $RepositoryRoot 'artifacts/ArtifactHandling/Import-Artifacts.ps1')
    }
    Import-Module $script:testModule

    foreach ($folder in @('empty', 'valid', 'invalid', 'mixed')) {
        New-Item -Path (Join-Path $TestDrive $folder) -ItemType Directory | Out-Null
    }
    foreach ($file in @('valid/valid.app', 'invalid/invalid.app', 'mixed/valid.app', 'mixed/invalid.app')) {
        New-Item -Path (Join-Path $TestDrive $file) -ItemType File | Out-Null
    }
}

AfterAll {
    Remove-Module $script:testModule
}

Describe 'App metadata error handling' {
    It 'allows an empty folder for non-app artifacts in strict mode' {
        $apps = @(Get-AppFilesSortedByDependencies -Path (Join-Path $TestDrive 'empty') -ErrorAction Stop -WarningAction SilentlyContinue)
        $apps.Count | Should -Be 0
    }

    It 'returns readable apps in strict mode' {
        $apps = @(Get-AppFilesSortedByDependencies -Path (Join-Path $TestDrive 'valid') -ErrorAction Stop -WarningAction SilentlyContinue)
        $apps.Count | Should -Be 1
        $apps[0].Name | Should -Be 'Valid app'
    }

    It 'rejects unreadable metadata in a <Folder> folder in strict mode' -ForEach @(
        @{ Folder = 'invalid' }
        @{ Folder = 'mixed' }
    ) {
        { Get-AppFilesSortedByDependencies -Path (Join-Path $TestDrive $Folder) -ErrorAction Stop -WarningAction SilentlyContinue } |
            Should -Throw '*Invalid app metadata*'
    }

    It 'honors an inherited Stop preference' {
        {
            & $script:testModule {
                param($Path)
                $ErrorActionPreference = 'Stop'
                Get-AppFilesSortedByDependencies -Path $Path -WarningAction SilentlyContinue
            } (Join-Path $TestDrive 'invalid')
        } | Should -Throw '*Invalid app metadata*'
    }

    It 'preserves warnings and readable apps for <Action> callers' -ForEach @(
        @{ Action = 'Continue' }
        @{ Action = 'SilentlyContinue' }
    ) {
        $apps = @(Get-AppFilesSortedByDependencies -Path (Join-Path $TestDrive 'mixed') -ErrorAction $Action -WarningAction SilentlyContinue -WarningVariable warnings)
        $apps.Count | Should -Be 1
        $apps[0].Name | Should -Be 'Valid app'
        @($warnings | Where-Object { "$_" -like '*Invalid app metadata*' }).Count | Should -Be 1
    }

    It 'propagates metadata errors through strict artifact import before any import starts' {
        {
            Import-Artifacts -Path (Join-Path $TestDrive 'mixed') -NavServiceName 'Test service' `
                -telemetryClient ([PSCustomObject]@{ Test = $true }) -ErrorAction Stop -WarningAction SilentlyContinue
        } | Should -Throw '*Invalid app metadata*'
    }
}
