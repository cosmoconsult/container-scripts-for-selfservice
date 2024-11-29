function Wait-DownloadArtifactAsync {
    [CmdletBinding()]
    param (
        # Async Parameters
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$Runspace
    )
    
    process {
        $Runspace | 
            Wait-AsyncScript `
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
    
    end {
    }
}
Export-ModuleMember -Function Wait-DownloadArtifactAsync