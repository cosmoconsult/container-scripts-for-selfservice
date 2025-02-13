function Get-BcMajorVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [string]$sysAppPath = 'C:\Applications\system application\source\Microsoft_System Application.app'
    )
    
    process {
        if (Test-Path $sysAppPath) {
            if (-not Get-Command Get-NAVAppInfo -ErrorAction SilentlyContinue) {
                c:\run\prompt.ps1
            }
            
            $sysAppInfoFS = Get-NAVAppInfo -Path $sysAppPath
            $sysAppVersionFS = $sysAppInfoFS.Version

            return $sysAppVersionFS.Major
        }
        
        return -1
    }    
}
Export-ModuleMember -Function Get-BcMajorVersion