function Initialize-NuGetFeeds {
    [cmdletbinding()]
    Param(
        [switch]$PassThru
    )

    begin {
        $feeds = @()
    }

    process {
        Write-Host "Collecting Microsoft NuGet feeds"
        @( 
            "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json",
            "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSSymbols/nuget/v3/index.json",
            "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/AppSourceSymbols/nuget/v3/index.json"
        ) | 
            ForEach-Object {
                Write-Host "Adding NuGet feed: $_"
                $feeds += [PSCustomObject]@{ 
                    Url          = $_
                    Token        = ""
                    Patterns     = @('*')
                    Fingerprints = @() 
                }
            }

        if ($global:extendedEnv.CustomNugetFeeds) {            
            Write-Host "Collecting custom nuget feeds"
            [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($global:extendedEnv.CustomNugetFeeds)) | 
                ConvertFrom-Json |
                Where-Object { $_ } |
                ForEach-Object {
                    $url = $_.feedUrl
                    if ($url -in @( $feeds.Url )) {
                        Write-Host "NuGet feed already added: $url - Skipping"
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
                Write-Host "Collecting NuGet feeds from $_"
                Get-Content $_ | ConvertFrom-Json | Select-Object -ExpandProperty Feeds
            } |
            Where-Object { $_ } |
            ForEach-Object {
                $url = $_.url
                if ($url -in @( $feeds.Url )) {
                    Write-Host "NuGet feed already added: $url - Skipping"
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
        Set-BcContainerHelperConfig -Key "TrustedNuGetFeeds" -Value $feeds
        
        if ($PassThru) {
            return $feeds
        }
    }
}
Export-ModuleMember -Function Initialize-NuGetFeeds