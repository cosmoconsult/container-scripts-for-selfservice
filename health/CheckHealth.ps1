try {
    . (Join-Path $PSScriptRoot "ServiceSettings.ps1")
    exit 0
}
catch {
}
exit 1