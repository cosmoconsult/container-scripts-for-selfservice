$script:nugetImported = $false

function Import-NugetTools {
    if (! $script:nugetImported) {
        Write-Host "Import BCContainerHelper"
        Write-Host "Install Nuget Provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
        Write-Host "Import bccontainerhelper"
        Install-Module -Name "bccontainerhelper" -Scope CurrentUser -Force
        Import-Module -Name "bccontainerhelper" -DisableNameChecking -Scope Global

        Write-Host "Add Microsoft feeds as trusted feeds"
        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ "Url" = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSApps/nuget/v3/index.json"; "Token" = ""; "Patterns" = @('*'); "Fingerprints" = @() })
        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ "Url" = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json"; "Token" = ""; "Patterns" = @('*'); "Fingerprints" = @() })
        $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ "Url" = "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"; "Token" = ""; "Patterns" = @('*'); "Fingerprints" = @() })


        $JsonPaths = @("C:\Run\my\trusted-nuget-feeds\trustedFeeds.json", 
            "C:\Run\my\trusted-nuget-feeds\customTrustedFeeds.json")
        if ($global:extendedEnv.CustomNugetFeeds) {
            Write-Host "Check Custom nuget feeds..."
            $customFeeds = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($global:extendedEnv.CustomNugetFeeds)) | ConvertFrom-Json
            
            Write-Host "Add feeds from custom feeds"
            $customFeeds | ForEach-Object {
                $feedUrl= $_.feedUrl
                Write-Host "Processing feed: $feedUrl"

                # Check if the feed URL already exists in the TrustedNuGetFeeds array
                $existingFeed = $bcContainerHelperConfig.TrustedNuGetFeeds | Where-Object { $_.Url -eq $feedUrl }

                if ($existingFeed) {
                    Write-Host "Feed already exists: $feedUrl - Skipping"
                } else {
                    Write-Host "Adding feed: $feedUrl"
                    $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ 
                        "Url" = $feedUrl
                        "Token" = $_.pat
                        "Patterns" = @('*')
                        "Fingerprints" = @()
                    })
                }
            }
        }
        foreach ($jsonPath in $JsonPaths) {
            if (Test-Path $jsonPath) {
                Write-Host "Add feeds from $jsonPath"
                $fileContent = Get-Content $jsonPath
                if ($fileContent -ne "") {
                    $trustedFeeds = $fileContent | ConvertFrom-Json
                    $trustedFeeds.Feeds | ForEach-Object {

                        $feedUrl= $_.url
                        Write-Host "Processing feed: $feedUrl"
                        # Check if the feed URL already exists in the TrustedNuGetFeeds array
                        $existingFeed = $bcContainerHelperConfig.TrustedNuGetFeeds | Where-Object { $_.Url -eq $feedUrl }

                        if ($existingFeed) {
                            Write-Host "Feed already exists: $feedUrl - Skipping"
                        } else {
                            Write-Host "Adding feed: $feedUrl"
                            $bcContainerHelperConfig.TrustedNuGetFeeds += @([PSCustomObject]@{ 
                                "Url" = $feedUrl
                                "Token" = $_.pat
                                "Patterns" = @('*')
                                "Fingerprints" = @()
                            })
                        }
                    }
                }
            }
        }
    }

    $script:nugetImported = $true
}

Export-ModuleMember -Function Import-NugetTools