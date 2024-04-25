$global:extendedEnv = [PSCustomObject]@{}

if ($env:AZURE_DEVOPS_ARTIFACTS) {
    Write-Host "Use legacy parameter AZURE_DEVOPS_ARTIFACTS as AzureDevOpsArtifacts for compatibility"
    $global:extendedEnv | Add-Member -MemberType NoteProperty -Name 'AzureDevOpsArtifacts' -Value $env:AZURE_DEVOPS_ARTIFACTS
}

$extendeEnvPath = "C:\customConfigs\ExtendedEnv.json"
if (Test-Path $extendeEnvPath) {
    $extendeEnvJson = ConvertFrom-Json (Get-Content $extendeEnvPath -Raw)
    foreach ($token in $extendeEnvJson.PSObject.Properties) {
        Write-host "Add "$token.Name" to extended environment"
        $global:extendedEnv | Add-Member -MemberType NoteProperty -Name $token.Name -Value $token.Value
    }
}
