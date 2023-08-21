[CmdletBinding()]
param (
    [string[]]$AppsToDeploy,
    [string]$Username,  # ignored
    [string]$Password,  # ignored
    [string]$BearerToken = "",
    [string]$PathInZip = "",
    [Parameter(Mandatory=$false)]
    [ValidateSet('Global','Tenant','Dev')]
    [string] $Scope = "Tenant"
)

c:\run\prompt.ps1
$ppiau = Get-Module -Name PPIArtifactUtils
if (-not $ppiau) {
    if (Test-Path "c:\run\PPIArtifactUtils.psd1") {
        Write-Host "Import PPI Setup Utils from c:\run\PPIArtifactUtils.psd1"
        Import-Module "c:\run\PPIArtifactUtils.psd1" -DisableNameChecking -Force
    }
}
$parentFolder = [System.IO.Path]::GetTempPath()
[string] $tempName = [System.Guid]::NewGuid()
$tempFullPath = (Join-Path $parentFolder $tempname)

try {
    $started = Get-Date -Format "o"

    if ($Scope -eq 'Dev') {
        Write-Host "Deployment to the dev endpoint is not yet supported"
        return
    }
    
    # copy all apps into a folder so that we can order them later
    New-Item -ItemType Directory -Path $tempFullPath
    $AppsToDeploy | % {
        $AppToDeploy = $_
        if ($AppToDeploy.StartsWith("http")) {
            # given a URL, so need to download
            $basePath = "c:\downloadedBuildArtifacts"
            $headers = @{}
            $headers.Add("authorization", "Bearer $BearerToken")
            if (-not (Test-Path $basePath)) {
                New-Item "$basePath" -ItemType Directory
            }
            $subfolder = $([convert]::tostring((get-random 65535),16).padleft(8,'0'))
            $folder = Join-Path $basePath $subfolder
            New-Item "$folder" -ItemType Directory
            $filename = "downloadedapp.app"
            if ($AppToDeploy.EndsWith("zip")) {
                $filename = "downloadedapp.zip"
            }
            $fullPath = Join-Path $folder $filename
            Invoke-WebRequest -Uri $AppToDeploy -Method GET -Headers $headers -OutFile $fullPath
            if (-not (Test-Path $fullPath)) {
                Write-Host "Failed to download the file from $AppToDeploy"
                exit
            }

            if ($AppToDeploy.EndsWith("zip")) {
                Expand-Archive $fullPath -DestinationPath $folder
                $AppToDeploy = Join-Path $folder $PathInZip
                if (-not (Test-Path $AppToDeploy)) {
                    Write-Host "Couldn't find $PathInZip in $AppToDeploy"
                    exit
                }
            } else {
                $AppToDeploy = $fullPath
            }
        }
        Copy-Item $AppToDeploy $tempFullPath
    }

    # all apps should be in the folder, now order
    $orderedApps = Get-AppFilesSortedByDependencies -Path $tempFullPath

    # now deploy them
    $orderedApps | % {
        #Write-Host $_
        c:\\run\\Invoke-AppDeployment.ps1 -AppToDeploy $_.Path -Scope $Scope 2>&1
    }
}
catch {
    Write-Host "$_"
}
finally {
    if (Test-Path $tempFullPath) {
        Remove-Item -Recurse -Force $tempFullPath
    }
}