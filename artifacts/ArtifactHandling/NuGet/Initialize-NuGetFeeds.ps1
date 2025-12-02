function Initialize-NuGetFeeds {
    [cmdletbinding()]
    Param(
        [switch]$PassThru
    )

    begin {
        $feeds = @()
    }

    process {
        if ($global:extendedEnv.PSObject.Properties.Name -contains "TrustedNugetFeeds") {
            Write-Host "Collecting trusted nuget feeds"
            if ($global:extendedEnv.TrustedNugetFeeds) {
                $trustedNugetFeedsBase64 = $global:extendedEnv.TrustedNugetFeeds
                $trustedNugetFeedsJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($trustedNugetFeedsBase64))
                ($trustedNugetFeedsJson | ConvertFrom-Json) |
                    Where-Object { $_ } |
                    ForEach-Object {
                        $url = $_.feedUrl
                        Write-Host "- Adding NuGet feed: $url"
                        $feeds += Initialize-NuGetFeed -Url $url -Token $_.pat
                    }
            }
        } else {
            Write-Host "Collecting Microsoft NuGet feeds"
            @( 
                "https://dynamicssmb2.pkgs.visualstudio.com/DynamicsBCPublicFeeds/_packaging/MSApps/nuget/v3/index.json"
            ) | 
                ForEach-Object {
                    Write-Host "- Adding NuGet feed: $_"
                    $feeds += Initialize-NuGetFeed -Url $_
                }

            if ($global:extendedEnv.CustomNugetFeeds) {            
                Write-Host "Collecting custom nuget feeds"
                $customNugetFeedsBase64 = $global:extendedEnv.CustomNugetFeeds
                $customNugetFeedsJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($customNugetFeedsBase64))
                ($customNugetFeedsJson | ConvertFrom-Json) |
                    Where-Object { $_ } |
                    ForEach-Object {
                        $url = $_.feedUrl
                        if ($url -in @( $feeds.Url )) {
                            Write-Host "- NuGet feed already added: $url - Skipping"
                        } else {
                            Write-Host "- Adding NuGet feed: $url"
                            $feeds += Initialize-NuGetFeed -Url $url -Token $_.pat
                        }
                    }
            }
        }

        @(
            "C:\Run\my\trusted-nuget-feeds\trustedFeeds.json"
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
                    Write-Host "- NuGet feed already added: $url - Skipping"
                } else {
                    Write-Host "- Adding NuGet feed: $url"
                    $feeds += Initialize-NuGetFeed -Url $url -Token $_.pat
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

function Initialize-NuGetFeed {
    [cmdletbinding()]
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Url,
        [Parameter(Mandatory = $false)]
        [string]$Token = "",
        [Parameter(Mandatory = $false)]
        [string[]]$Patterns = @('*'),
        [Parameter(Mandatory = $false)]
        [string[]]$Fingerprints = @()
    )

    $feed = @{
        Url          = $Url
        Token        = $Token
        Patterns     = $Patterns
        Fingerprints = $Fingerprints
    }

    return [PSCustomObject]$feed
}