if ([string]::IsNullOrEmpty($env:useCustomScriptsFromRepo) -or $($env:useCustomScriptsFromRepo).ToLower() -ne "true") {
    return;
}

Write-Host "Downloading custom run scripts from directory .container-my of repo ..."

if ([string]::IsNullOrEmpty($env:CcOrgName) -or [string]::IsNullOrEmpty($env:CcProjectId) -or [string]::IsNullOrEmpty($env:CcRepoId) -or [string]::IsNullOrEmpty($env:AZURE_DEVOPS_EXT_PAT)) {
    Write-Warning "CcOrgName=$($env:CcOrgName), CcProjectId=$($env:CcProjectId), CcRepoId=$($env:CcRepoId) or AZURE_DEVOPS_EXT_PAT=$($env:AZURE_DEVOPS_EXT_PAT) is empty, can't download custom scripts"
    return;
}

$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("dummy:$($env:AZURE_DEVOPS_EXT_PAT)"))
$Headers = @{
    Authorization = "Basic $encodedCreds"
}

$url = "https://dev.azure.com/$($env:CcOrgName)/$($env:CcProjectId)/_apis/git/repositories/$($env:CcRepoId)/items?path=%2F.container-my&download=true&resolveLfs=true&%24format=zip&api-version=5.0"

if (-not [string]::IsNullOrEmpty($env:CcBranch)) {
    $url += "&versionDescriptor%5Bversion%5D=$($env:CcBranch)"
    Write-Host "- Using branch $($env:CcBranch)"
} else if (([string]::IsNullOrEmpty($env:CcBranch)) -and (-not [string]::IsNullOrEmpty($env:AZP_CONFIG_REPO_PATH))) {
    $url += "&versionDescriptor%5Bversion%5D=master"
    Write-Host "- Using branch master for demo containers"
}

$ProgressPreference = "SilentlyContinue"

try {
    $downloadTarget = "C:\myscripts.zip"
    $extractionTarget = "C:\myscripts"
    $destination = "C:\Run\my"
    Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Headers -OutFile $downloadTarget
    Expand-Archive $downloadTarget -DestinationPath $extractionTarget
    Get-ChildItem -Path "$extractionTarget\.container-my\*" -Recurse | Move-Item -Destination $destination -Force
}
catch {
    Write-Warning "Couldn't download custom scripts from $url, error: $($_)"
    return;
}
