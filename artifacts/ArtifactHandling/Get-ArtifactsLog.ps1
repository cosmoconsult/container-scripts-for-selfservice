function Get-ArtifactsLog {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [System.Object]$artifactsLogFile = "C:/inetpub/wwwroot/http/artifacts.log.json"
    )
    
    process {
        if (Test-Path "$artifactsLogFile") {
            $artifactsLog = (Get-Content $artifactsLogFile -ErrorAction SilentlyContinue | ConvertFrom-Json -ErrorAction SilentlyContinue)
        }
        if (! $artifactsLog) {
            $artifactsLog = ("{}" | ConvertFrom-Json)
        }

        foreach ($member in @("Log")) {
            if ($null -eq $artifactsLog."$member") {
                $artifactsLog | Add-Member -MemberType NoteProperty -Name "$member" -Value ([System.Collections.ArrayList]@())
            }
        }
        return $artifactsLog
    }    
}
Export-ModuleMember -Function Get-ArtifactsLog