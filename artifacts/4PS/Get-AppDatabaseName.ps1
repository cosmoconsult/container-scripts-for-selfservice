function Get-AppDatabaseName {
    [cmdletbinding()]
    PARAM
    (
    )
    PROCESS
    {
        $bakfile = "$env:bakfile"
        # from https://github.com/microsoft/nav-docker/blob/af44448eea2852a49c57cc6cef4368226f5d18e6/generic/Run/SetupVariables.ps1#L84-L97
        if ("$env:multitenant" -ne "") {
            $multitenant = ("$env:multitenant" -eq "Y")
        }
        else {
            try {
                $serviceTierFolder = (Get-Item "C:\Program Files\Microsoft Dynamics NAV\*\Service").FullName
                $CustomConfigFile =  Join-Path $ServiceTierFolder "CustomSettings.config"
                $CustomConfig = [xml](Get-Content $CustomConfigFile)
                $multitenant = ($customConfig.SelectSingleNode("//appSettings/add[@key='Multitenant']").Value -eq "true")
            }
            catch {
                $multitenant = $false
            }
        }
        # end copy

        if ($bakfile -ne "") {
            $appDatabaseName = "mydatabase"
        } elseif ($multitenant) {
            $appDatabaseName = "default"
        } else {
            $appDatabaseName = "CRONUS"
        }

        return $appDatabaseName
    }

}

Export-ModuleMember -Function Get-AppDatabaseName