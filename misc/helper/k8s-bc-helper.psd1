#-------------------------------------------------------------------------
#---     Copyright (c) Cosmo Consult.  All rights reserved.            ---
#-------------------------------------------------------------------------

@{

    # Script module or binary module file associated with this manifest.
    # RootModule = ''
    
    # Version number of this module.
    ModuleVersion = '1.0'
    
    # ID used to uniquely identify this module
    # GUID = ''
    
    # Author of this module
    Author = 'Cosmo Consult SSC'
    
    # Company or vendor of this module
    CompanyName = 'Cosmo Consult SSC'
    
    # Copyright statement for this module
    Copyright = '� 2022 Cosmo Consult SSC. All rights reserved.'
    
    # Description of the functionality provided by this module
    Description = 'Cosmo Consult k8s BC helper library'

    NestedModules = @('Backup-Databases.psm1',
                      'Copy-EventLog.psm1',
                      'Install-OpenSSH.psm1',
                      'Get-ExtendedErrorMessage.psm1')

    # Functions to export from this module
    FunctionsToExport = '*'

    # Cmdlets to export from this module
    CmdletsToExport = '*'

    # Variables to export from this module
    VariablesToExport = '*'

    # Aliases to export from this module
    AliasesToExport = '*'
}
