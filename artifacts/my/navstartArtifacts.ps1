try {
    if ($global:cosmoRunspacePool) {
        Write-Host "##[group]Download Artifacts (Async) - Start"
    } else {
        Write-Host "##[group]Download Artifacts"
    }

    # Initialize Cosmo Artifacts object
    $cosmoArtifacts = @{
        Download = @{
            Start      = Get-Date -Format "o";
            NuGet      = $false
            NuGetFeeds = @();
        };
        Path = @{
            Unsorted = "C:\run\my\apps";
            Sorted   = "C:\run\my\manuallysorted-apps";
        };
        Artifacts = @{
            All      = @();
            Unsorted = @();
            Sorted   = @();
            Backup   = @();
            Font     = @();
            AddIn    = @();
            Demodata = @();
        };
    }

    # Get Telemetry Client
    $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue

    # Get Artifacts from Environment
    Get-ArtifactsFromEnvironment -telemetryClient $telemetryClient -ErrorAction SilentlyContinue | 
        Sort-Object { $_.type -eq "nuget" } | # Sort NuGet packages last
        ForEach-Object {
            $cosmoArtifacts.Artifacts.All += $_

            # Sort Artifacts
            if     ( $_.target -in @( "bak", "saasbak" ) )          { $cosmoArtifacts.Artifacts.Backup   += $_ }
            elseif ( $_.target -in @( "fonts", "font" ) )           { $cosmoArtifacts.Artifacts.Font     += $_ }
            elseif ( $_.target -in @( "add-ins", "dll" ) )          { $cosmoArtifacts.Artifacts.AddIn    += $_ }
            elseif ( $_.target -in @( "demodata" ) )                { $cosmoArtifacts.Artifacts.Demodata += $_ }
            elseif ( $_.name -and $_.name.StartsWith("sortorder") ) { $cosmoArtifacts.Artifacts.Sorted   += $_ }
            else                                                    { $cosmoArtifacts.Artifacts.Unsorted += $_ }

            if ($_.type -eq "nuget") {
                $cosmoArtifacts.Download.NuGet = $true
            }
        }

    # Set Telemetry Properties
    $telemetryProperties = @{}
    $telemetryProperties["artifacts"] = ( $cosmoArtifacts.Artifacts.All | ConvertTo-Json -Depth 50 -ErrorAction SilentlyContinue )

    if ($cosmoArtifacts.Download.NuGet) {
        # Install NuGet Tools
        Install-NuGetTools
        
        # Get NuGet Feeds
        $cosmoArtifacts.Download.NuGetFeeds = Get-NuGetFeeds
    }

    # Get Download Parameters
    $downloadParameters = @{
        ServiceTierFolder = Get-NAVServiceTierFolder
        ApiFeatures       = Get-AzureDevOpsApiFeatures
        AccessToken       = Get-AzureDevOpsAccessToken -Artifacts $cosmoArtifacts.Artifacts.All
        NuGetFeeds        = $cosmoArtifacts.Download.NuGetFeeds
    }
    
    if ($global:cosmoRunspacePool) {
        # Download Artifacts (Async)

        $downloadParameters += @{
            RunspacePool = $global:cosmoRunspacePool
        }

        # Add Runspaces to Cosmo Artifacts object
        $cosmoArtifacts.Download.Runspaces = @{
            Unsorted = @();
            Sorted   = @();
            Backup   = @();
            Font     = @();
            AddIn    = @();
            Demodata = @();
        }

        # Download Add-In, Font and Demodata Artifacts (Async) - Start
        $cosmoArtifacts.Download.Runspaces.AddIn += 
            $cosmoArtifacts.Artifacts.AddIn |
                Invoke-DownloadArtifactAsync @downloadParameters
        $cosmoArtifacts.Download.Runspaces.Font += 
            $cosmoArtifacts.Artifacts.Font | 
                Invoke-DownloadArtifactAsync -OneRunspace @downloadParameters
        $cosmoArtifacts.Download.Runspaces.Demodata += 
            $cosmoArtifacts.Artifacts.Demodata |
                Invoke-DownloadArtifactAsync -OneRunspace @downloadParameters

        # Download sorted Artifacts (Async) - Start
        $cosmoArtifacts.Download.Runspaces.Sorted += 
            $cosmoArtifacts.Artifacts.Sorted | 
                Invoke-DownloadArtifactAsync -Destination $cosmoArtifacts.Path.Sorted -GroupByDependency @downloadParameters

        # Download unsorted Artifacts (Async) - Start
        $cosmoArtifacts.Download.Runspaces.Unsorted += 
            $cosmoArtifacts.Artifacts.Unsorted | 
                Group-Object -Property dependsOn | 
                ForEach-Object {
                    # Download per dependency for separated indexes
                    $_.Group | Invoke-DownloadArtifactAsync -Destination $cosmoArtifacts.Path.Unsorted -GroupByDependency @downloadParameters
                }

        # Log
        Invoke-LogOperation -name "navstart - Download Artifacts (Async) - Start" -started $cosmoArtifacts.Download.Start -telemetryClient $telemetryClient -properties $telemetryProperties
        Add-ArtifactsLog -message "Download Artifacts (Async) started. (Duration: $(New-TimeSpan -start $cosmoArtifacts.Download.Start -end (Get-Date)))"
    } else {
        # Download Artifacts (Sync)

        $downloadParameters += @{
            TelemetryClient = $telemetryClient
            ErrorAction     = "SilentlyContinue"
        }

        # Download Add-In, Font and Demodata Artifacts
        $( $cosmoArtifacts.Artifacts.AddIn; $cosmoArtifacts.Artifacts.Font; $cosmoArtifacts.Artifacts.Demodata ) | 
            Invoke-DownloadArtifact @downloadParameters

        # Download sorted Artifacts
        $cosmoArtifacts.Artifacts.Sorted | 
            Invoke-DownloadArtifact -destination $cosmoArtifacts.Path.Sorted -groupByDependency @downloadParameters

        # Download unsorted Artifacts
        $cosmoArtifacts.Artifacts.Unsorted | 
            Group-Object -Property dependsOn | 
            ForEach-Object {
                # Download per dependency for separated indexes
                $_.Group | Invoke-DownloadArtifact -destination $cosmoArtifacts.Path.Unsorted -groupByDependency @downloadParameters
            }

        $cosmoArtifacts.Download.End = Get-Date

        # Log
        Invoke-LogOperation -name "navstart - Download Artifacts" -started $cosmoArtifacts.Download.Start -ended $cosmoArtifacts.Download.End -telemetryClient $telemetryClient -properties $telemetryProperties
        Add-ArtifactsLog -message "Download Artifacts done. (Duration: $(New-TimeSpan -start $cosmoArtifacts.Download.Start -end $cosmoArtifacts.Download.End))"
    }
}
catch {
    Add-ArtifactsLog -message "Download Artifacts Error: $($_.Exception.Message)" -severity Error
}
finally {
    # Promoting Cosmo Artifacts object to global scope
    $global:cosmoArtifacts = $cosmoArtifacts

    Write-Host "##[endgroup]"
}