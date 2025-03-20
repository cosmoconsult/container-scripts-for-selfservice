function Get-NuGetFeeds {
    begin {
        $feeds = @()
    }

    process {
        Write-Host "Add Microsoft NuGet feeds"
        @( 
            "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json",
            "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json",
            "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
        ) | 
            ForEach-Object {
                $feeds += [PSCustomObject]@{ 
                    Url          = $_
                    Token        = ""
                    Patterns     = @('*')
                    Fingerprints = @() 
                }
            }

        if ($global:extendedEnv.CustomNugetFeeds) {            
            Write-Host "Add custom nuget feeds"
            $customFeeds = @( [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($global:extendedEnv.CustomNugetFeeds)) | ConvertFrom-Json )
            $customFeeds |
                ForEach-Object {
                    $url = $_.feedUrl
                    if ($url -in @( $feeds.Url )) {
                        Write-Host "NuGet feed already exists: $url - Skipping"
                    } else {
                        Write-Host "Adding NuGet feed: $url"
                        $feeds += [PSCustomObject]@{ 
                            Url          = $url
                            Token        = $_.pat
                            Patterns     = @('*')
                            Fingerprints = @()
                        }
                    }
                }
        }

        @(
            "C:\Run\my\trusted-nuget-feeds\trustedFeeds.json", 
            "C:\Run\my\trusted-nuget-feeds\customTrustedFeeds.json"
        ) |
            Where-Object { Test-Path $_ -PathType Leaf } |
            ForEach-Object {
                Write-Host "Add NuGet feeds from $_"
                Get-Content $_ | ConvertFrom-Json | Select-Object -ExpandProperty Feeds
            } |
            ForEach-Object {
                $url = $_.url
                if ($url -in @( $feeds.Url )) {
                    Write-Host "NuGet feed already exists: $url - Skipping"
                } else {
                    Write-Host "Adding NuGet feed: $url"
                    $feeds += [PSCustomObject]@{ 
                        Url          = $url
                        Token        = $_.pat
                        Patterns     = @('*')
                        Fingerprints = @()
                    }
                }
            }
    }

    end {
        return $feeds
    }
}
Export-ModuleMember -Function Get-NuGetFeeds