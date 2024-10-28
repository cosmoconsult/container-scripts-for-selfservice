$publicPath = Join-Path $PSScriptRoot "public"
. (Join-Path $publicPath "ConvertTo-DynamicParameters.ps1")
. (Join-Path $publicPath "Expand-Archive.ps1")
. (Join-Path $publicPath "Invoke-WebRequest.ps1")
. (Join-Path $publicPath "NavAppManagement.ps1")