function Invoke-4PSPostStartupHandling {
    [cmdletbinding()]
    PARAM
    ()
    PROCESS
    {
        if ($env:mode -eq "4ps") {
            Write-Host "4PS mode found, start post startup handling"

            # Prepare
            $serviceFolderTarget = "C:\temp\Service\"
            $rtcFolderTarget = "C:\temp\RoleTailored Client\"
            $netFolderTarget = "C:\temp\.NET\"
            $assemblyArchive = "C:\inetpub\wwwroot\http\AllAssemblies.zip"

            # Cleanup in the beginning (just in case)
            Remove-Item -Path $serviceFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path $rtcFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path $netFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path $assemblyArchive -Force -ErrorAction SilentlyContinue

            # Create new directories
            New-Item -Path $serviceFolderTarget -Type Directory | Out-Null
            New-Item -Path $rtcFolderTarget -Type Directory | Out-Null
            New-Item -Path $netFolderTarget -Type Directory | Out-Null

            # Copy all DLLs from folders to new directory (because some were in use and couldn't be zipped right away)
            Copy-Item -Path "C:\Program Files\Microsoft Dynamics*\*\Service\*" -Destination $serviceFolderTarget -Recurse
            Copy-Item -Path "C:\Program Files (x86)\Microsoft Dynamics*\*\RoleTailored Client\*" -Destination $rtcFolderTarget -Recurse
            Copy-Item -Path "C:\Windows\Microsoft.NET\Framework64\v4.0.*\*" -Destination $netFolderTarget -Recurse
            Copy-Item -Path ([PSObject].Assembly.Location) -Destination $netFolderTarget            # required for obsolete ExchangePowerShellRunner.Codeunit.al

            # Create one archive
            Compress-Archive -Path ($serviceFolderTarget, $rtcFolderTarget, $netFolderTarget) -DestinationPath $assemblyArchive -CompressionLevel "Fastest"

            # Cleanup in the end
            Remove-Item -Path $serviceFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path $rtcFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
            Remove-Item -Path $netFolderTarget -Force -Recurse -ErrorAction SilentlyContinue

            $assemblyInfo = Get-Item $assemblyArchive       
            Write-Host "Created $($assemblyInfo.Name) with size $($assemblyInfo.Length)"
            Write-Host "Finished 4PS post startup handling"
        }
    }
}

Export-ModuleMember -Function Invoke-4PSPostStartupHandling
