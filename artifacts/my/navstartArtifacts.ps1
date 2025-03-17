try {
    if ($global:cosmoRunspacePool) {
        Write-Host "##[group]Download Artifacts (Async) - Start"
    } else {
        Write-Host "##[group]Download Artifacts"
    }

    $cosmoArtifacts = @{
        Download = @{
            Start = Get-Date -Format "o";
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

    $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue

    Get-ArtifactsFromEnvironment -telemetryClient $telemetryClient -ErrorAction SilentlyContinue | 
        Sort-Object { $_.type -eq "nuget" } | # Sort NuGet packages last
        ForEach-Object {
            $cosmoArtifacts.Artifacts.All += $_

            if     ( $_.target -in @( "bak", "saasbak" ) )          { $cosmoArtifacts.Artifacts.Backup   += $_ }
            elseif ( $_.target -in @( "fonts", "font" ) )           { $cosmoArtifacts.Artifacts.Font     += $_ }
            elseif ( $_.target -in @( "add-ins", "dll" ) )          { $cosmoArtifacts.Artifacts.AddIn    += $_ }
            elseif ( $_.target -in @( "demodata" ) )                { $cosmoArtifacts.Artifacts.Demodata += $_ }
            elseif ( $_.name -and $_.name.StartsWith("sortorder") ) { $cosmoArtifacts.Artifacts.Sorted   += $_ }
            else                                                    { $cosmoArtifacts.Artifacts.Unsorted += $_ }
        }

    $telemetryProperties = @{}
    $telemetryProperties["artifacts"] = ( $cosmoArtifacts.Artifacts.All | ConvertTo-Json -Depth 50 -ErrorAction SilentlyContinue )

    $downloadParameters = @{
        ServiceTierFolder = Get-NAVServiceTierFolder
        ApiFeatures       = Get-AzureDevOpsApiFeatures
        AccessToken       = Get-AzureDevOpsAccessToken -Artifacts $cosmoArtifacts.Artifacts.All
    }
    
    if ($global:cosmoRunspacePool) {
        $cosmoArtifacts.Download.Runspaces = @{
            Unsorted = @();
            Sorted   = @();
            Backup   = @();
            Font     = @();
            AddIn    = @();
            Demodata = @();
        }

        # Download Font, Add-In and Demodata Artifacts (Async) - Start
        $cosmoArtifacts.Download.Runspaces.Font += 
            $cosmoArtifacts.Artifacts.Font | 
                Invoke-DownloadArtifactAsync -RunspacePool $global:cosmoRunspacePool @downloadParameters
        $cosmoArtifacts.Download.Runspaces.AddIn += 
            $cosmoArtifacts.Artifacts.AddIn |
                Invoke-DownloadArtifactAsync -RunspacePool $global:cosmoRunspacePool @downloadParameters
        $cosmoArtifacts.Download.Runspaces.Demodata += 
            $cosmoArtifacts.Artifacts.Demodata |
                Invoke-DownloadArtifactAsync -RunspacePool $global:cosmoRunspacePool @downloadParameters

        # Download sorted Artifacts (Async) - Start
        $cosmoArtifacts.Download.Runspaces.Sorted += 
            $cosmoArtifacts.Artifacts.Sorted | 
                Invoke-DownloadArtifactAsync -RunspacePool $global:cosmoRunspacePool -Destination $cosmoArtifacts.Path.Sorted -GroupByDependency @downloadParameters

        # Download unsorted Artifacts (Async) - Start
        $cosmoArtifacts.Download.Runspaces.Unsorted += 
            $cosmoArtifacts.Artifacts.Unsorted | 
                Group-Object -Property dependsOn | 
                ForEach-Object {
                    # Download per dependency for separated indexes
                    $_.Group | Invoke-DownloadArtifactAsync -RunspacePool $global:cosmoRunspacePool -Destination $cosmoArtifacts.Path.Unsorted -GroupByDependency @downloadParameters
                }

        Invoke-LogOperation -name "navstart - Download Artifacts (Async) - Start" -started $cosmoArtifacts.Download.Start -telemetryClient $telemetryClient -properties $telemetryProperties
        Add-ArtifactsLog -message "Download Artifacts (Async) started. (Duration: $(New-TimeSpan -start $cosmoArtifacts.Download.Start -end (Get-Date)))"
    } else {
        # Download Font, Add-In and Demodata Artifacts
        @( $cosmoArtifacts.Artifacts.Font, $cosmoArtifacts.Artifacts.AddIn, $cosmoArtifacts.Artifacts.Demodata ) | 
            Invoke-DownloadArtifact -telemetryClient $telemetryClient -ErrorAction SilentlyContinue @downloadParameters

        # Download sorted Artifacts
        $cosmoArtifacts.Artifacts.Sorted | 
            Invoke-DownloadArtifact -destination $cosmoArtifacts.Path.Sorted -groupByDependency -telemetryClient $telemetryClient -ErrorAction SilentlyContinue @downloadParameters

        # Download unsorted Artifacts
        $cosmoArtifacts.Artifacts.Unsorted | 
            Group-Object -Property dependsOn | 
            ForEach-Object {
                # Download per dependency for separated indexes
                $_.Group | Invoke-DownloadArtifact -destination $cosmoArtifacts.Path.Unsorted -groupByDependency -telemetryClient $telemetryClient -ErrorAction SilentlyContinue @downloadParameters
            }

        $cosmoArtifacts.Download.End = Get-Date

        Invoke-LogOperation -name "navstart - Download Artifacts" -started $cosmoArtifacts.Download.Start -ended $cosmoArtifacts.Download.End -telemetryClient $telemetryClient -properties $telemetryProperties
        Add-ArtifactsLog -message "Download Artifacts done. (Duration: $(New-TimeSpan -start $cosmoArtifacts.Download.Start -end $cosmoArtifacts.Download.End))"
    }
}
catch {
    Add-ArtifactsLog -message "Download Artifacts Error: $($_.Exception.Message)" -severity Error
}
finally {
    # Promoting variable to global scope
    $global:cosmoArtifacts = $cosmoArtifacts

    Write-Host "##[endgroup]"
}