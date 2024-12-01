function Wait-DownloadArtifactAsync {
    [CmdletBinding()]
    param (
        # Async Parameter
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [powershell]$Runspace,
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [System.IAsyncResult]$Result
    )

    begin {
        if (! (Get-Module 'PPIAsyncUtils')) {
            throw "PPI Async Utils not loaded"
        }
    }
    
    process {
        Wait-Async `
            -Runspace $Runspace `
            -Result $Result `
            -ErrorScriptBlock       { Add-ArtifactsLog -message $_.Exception.Message -severity Error -success fail } `
            -WarningScriptBlock     { Add-ArtifactsLog -message $_ -severity Warn } `
            -DebugScriptBlock       { Add-ArtifactsLog -message $_ -severity Debug } `
            -InformationScriptBlock { Add-ArtifactsLog -message $_ } `
            -OutputScriptBlock      {
                if ($_.GetType() -in @([Microsoft.ApplicationInsights.DataContracts.EventTelemetry], [Microsoft.ApplicationInsights.DataContracts.RequestTelemetry], [Microsoft.ApplicationInsights.DataContracts.ExceptionTelemetry])) {
                    Invoke-Telemetry -operation "Download Artifact" -data $object -telemetryClient $telemetryClient
                }
            } |
        Out-Null
    }
}
Export-ModuleMember -Function Wait-DownloadArtifactAsync