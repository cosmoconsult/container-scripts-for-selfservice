$ProgressPreference = "SilentlyContinue"

# Prepare
$assemblyArchive = "C:\inetpub\wwwroot\http\AllAssemblies.zip"
$assemblyArchiveTmp = "C:\inetpub\wwwroot\http\AllAssemblies.tmp.zip"
if (Test-Path $assemblyArchive) {
  $assemblyInfo = Get-Item $assemblyArchive
  Write-Host "Assembly package $($assemblyInfo.Name) with size $($assemblyInfo.Length) already exists"
  return;
}

$serviceFolderTarget = "C:\temp\Service\"
$rtcFolderTarget = "C:\temp\RoleTailored Client\"
$netFolderTarget = "C:\temp\.NET\"
$sharedFolderTarget = "C:\temp\shared\"

# Identify version
$sysAppPath = 'C:\Applications\system application\source\Microsoft_System Application.app'
$twentyTwoOrLater = $true
if (Test-Path $sysAppPath) {
  c:\run\prompt.ps1
  $sysAppInfoFS = Get-NAVAppInfo -Path $sysAppPath
  $sysAppVersionFS = $sysAppInfoFS.Version
  if ($sysAppVersionFS.Major -lt 22) {
    $twentyTwoOrLater = $false
  }
}

# Cleanup in the beginning (just in case)
Write-Host "Cleanup"
Remove-Item -Path $serviceFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path $rtcFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path $netFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path $sharedFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path $assemblyArchive -Force -ErrorAction SilentlyContinue
Remove-Item -Path $assemblyArchiveTmp -Force -ErrorAction SilentlyContinue

# Create new directories
Write-Host "Creating temporary directories"
New-Item -Path $serviceFolderTarget -Type Directory | Out-Null
New-Item -Path $rtcFolderTarget -Type Directory | Out-Null
New-Item -Path $netFolderTarget -Type Directory | Out-Null
New-Item -Path $sharedFolderTarget -Type Directory | Out-Null

# Copy all DLLs from folders to new directory (because some were in use and couldn't be zipped right away)
Write-Host "Copying DLLs to temp directories"
Copy-Item -Path "C:\Program Files\Microsoft Dynamics*\*\Service\*" -Destination $serviceFolderTarget -Recurse
if ($twentyTwoOrLater) {
  get-childitem -Directory 'C:\Program Files\dotnet\shared\' | % { Get-ChildItem -Directory $_.FullName | Sort-Object Name -Descending | Select-Object -First 1 } | % { New-Item -Force -ItemType Directory (Join-Path $sharedFolderTarget $_.FullName.SubString(31)); Copy-Item -Recurse $_.FullName (Join-Path $sharedFolderTarget $_.FullName.SubString(31)) }
}
else {
  Copy-Item -Path "C:\Program Files (x86)\Microsoft Dynamics*\*\RoleTailored Client\*" -Destination $rtcFolderTarget -Recurse
  Copy-Item -Path "C:\Windows\Microsoft.NET\Framework64\v4.0.*\*" -Destination $netFolderTarget -Recurse
  Copy-Item -Path ([PSObject].Assembly.Location) -Destination $netFolderTarget            # required for obsolete ExchangePowerShellRunner.Codeunit.al
}

# Create one archive
Write-Host "Creating archive"
if ($twentyTwoOrLater) {
  Compress-Archive -Path ($serviceFolderTarget, $sharedFolderTarget) -DestinationPath $assemblyArchiveTmp -CompressionLevel "Fastest"
}
else {
  Compress-Archive -Path ($serviceFolderTarget, $rtcFolderTarget, $netFolderTarget) -DestinationPath $assemblyArchiveTmp -CompressionLevel "Fastest"
}
Move-Item -Path $assemblyArchiveTmp -Destination $assemblyArchive

# Cleanup in the end
Write-Host "Cleaning up"
Remove-Item -Path $serviceFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path $rtcFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path $netFolderTarget -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path $sharedFolderTarget -Force -Recurse -ErrorAction SilentlyContinue

$assemblyInfo = Get-Item $assemblyArchive
Write-Host "Created $($assemblyInfo.Name) with size $($assemblyInfo.Length)"