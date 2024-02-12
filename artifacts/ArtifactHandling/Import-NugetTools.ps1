function Import-NugetTools {
    if ($env:nugetImported -eq $false) {
        Write-Host "Import BCContainerHelper"
        Write-Host "Install Nuget Provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Write-Host "Import bccontainerhelper"
        Install-Module -Name "bccontainerhelper" -Scope CurrentUser -Force
        Import-Module -Name "bccontainerhelper" -Scope Global

        Write-Host "Add Microsoft feeds as trusted feeds"
        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ "Url" = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSApps/nuget/v3/index.json"; "Token" = ""; "Patterns" = @('*'); "Fingerprints" = @() })
        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ "Url" = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"; "Token" = ""; "Patterns" = @('*'); "Fingerprints" = @() })
        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ "Url" = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"; "Token" = ""; "Patterns" = @('*'); "Fingerprints" = @() })


        $JsonPaths = @("C:\Run\my\trusted-nuget-feeds\trustedFeeds.json", 
            "C:\Run\my\trusted-nuget-feeds\customTrustedFeeds.json")
        foreach ($jsonPath in $JsonPaths) {
            if (Test-Path $jsonPath) {
                Write-Host "Add feeds from $jsonPath"
                $fileContent = Get-Content $jsonPath
                if ($fileContent -ne "") {
                    $trustedFeeds = $fileContent | ConvertFrom-Json
                    $trustedFeeds.Feeds | ForEach-Object {
                        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ "Url" = $_.url; "Token" = $_.pat; "Patterns" = @('*'); "Fingerprints" = @() })
                    }
                }
            }
        }
    }
    $env:nugetImported = $true
}

Export-ModuleMember -Function Import-NugetTools