#
# Modulmanifest fuer das Modul "PSGet_PPIArtifactUtils"
#
# Generiert von: Michael Megel
#
# Generiert am: 09.09.2019
#

@{

# Die diesem Manifest zugeordnete Skript- oder Binuermoduldatei.
RootModule = 'PPIArtifactUtils.psm1'

# Die Versionsnummer dieses Moduls
ModuleVersion = '0.1.0'

# Unterstuetzte PSEditions
# CompatiblePSEditions = @()

# ID zur eindeutigen Kennzeichnung dieses Moduls
GUID = 'ade14601-8b4f-4b5a-add4-3bd0d646fc25'

# Autor dieses Moduls
Author = 'Michael Megel, Tobias Fenster'

# Unternehmen oder Hersteller dieses Moduls
CompanyName = 'COSMO CONSULT SSC'

# Urheberrechtserklaerung fuer dieses Modul
Copyright = '© 2020 COSMO CONSULT SSC. All rights reserved.'

# Beschreibung der von diesem Modul bereitgestellten Funktionen
Description = 'PPI Azure DevOps Artifact Utils Library'

# Die fuer dieses Modul mindestens erforderliche Version des Windows PowerShell-Moduls
# PowerShellVersion = ''

# Der Name des fuer dieses Modul erforderlichen Windows PowerShell-Hosts
# PowerShellHostName = ''

# Die fuer dieses Modul mindestens erforderliche Version des Windows PowerShell-Hosts
# PowerShellHostVersion = ''

# Die fuer dieses Modul mindestens erforderliche Microsoft .NET Framework-Version. Diese erforderliche Komponente ist nur fuer die PowerShell Desktop-Edition gueltig.
# DotNetFrameworkVersion = ''

# Die fuer dieses Modul mindestens erforderliche Version der CLR (Common Language Runtime). Diese erforderliche Komponente ist nur fuer die PowerShell Desktop-Edition gueltig.
# CLRVersion = ''

# Die fuer dieses Modul erforderliche Prozessorarchitektur ("Keine", "X86", "Amd64").
# ProcessorArchitecture = ''

# Die Module, die vor dem Importieren dieses Moduls in die globale Umgebung geladen werden muessen
# RequiredModules = @()

# Die Assemblys, die vor dem Importieren dieses Moduls geladen werden muessen
# RequiredAssemblies = @()

# Die Skriptdateien (PS1-Dateien), die vor dem Importieren dieses Moduls in der Umgebung des Aufrufers ausgefuehrt werden.
# ScriptsToProcess = @()

# Die Typdateien (.ps1xml), die beim Importieren dieses Moduls geladen werden sollen
# TypesToProcess = @()

# Die Formatdateien (.ps1xml), die beim Importieren dieses Moduls geladen werden sollen
# FormatsToProcess = @()

# Die Module, die als geschachtelte Module des in "RootModule/ModuleToProcess" angegebenen Moduls importiert werden sollen.
# NestedModules = @()

# Aus diesem Modul zu exportierende Funktionen. Um optimale Leistung zu erzielen, verwenden Sie keine Platzhalter und lueschen den Eintrag nicht. Verwenden Sie ein leeres Array, wenn keine zu exportierenden Funktionen vorhanden sind.
FunctionsToExport = 'Get-TelemetryClient', 'Invoke-LogEvent', 'Invoke-LogOperation', 'Invoke-LogError',
               'Get-PackageVersion', 'Invoke-DownloadArtifact', 'Get-AppFilesSortedByDependencies', 'Get-ArtifactsFromEnvironment',
               'Import-FOBArtifact', 'Import-AppArtifact', 'Import-RIMArtifact', 'Import-Artifacts', 
               'Get-ArtifactsLog', 'Add-ArtifactsLog', 'Import-Fonts', 'Get-ArtifactJson',
               'Invoke-4PSArtifactHandling', 'Check-DataUpgradeExecuted', 'Wait-DataUpgradeToFinish', 'Get-AppDatabaseName', 'Unpublish-AllNavAppsInServerInstance', 'Get-DemoDataFiles',
               'Import-NugetTools'

# Aus diesem Modul zu exportierende Cmdlets. Um optimale Leistung zu erzielen, verwenden Sie keine Platzhalter und lueschen den Eintrag nicht. Verwenden Sie ein leeres Array, wenn keine zu exportierenden Cmdlets vorhanden sind.
CmdletsToExport = @()

# Die aus diesem Modul zu exportierenden Variablen
# VariablesToExport = @()

# Aus diesem Modul zu exportierende Aliase. Um optimale Leistung zu erzielen, verwenden Sie keine Platzhalter und lueschen den Eintrag nicht. Verwenden Sie ein leeres Array, wenn keine zu exportierenden Aliase vorhanden sind.
AliasesToExport = 'Invoke-LogException', 'Invoke-LogRequest'

# Aus diesem Modul zu exportierende DSC-Ressourcen
# DscResourcesToExport = @()

# Liste aller Module in diesem Modulpaket
# ModuleList = @()

# Liste aller Dateien in diesem Modulpaket
# FileList = @()

# Die privaten Daten, die an das in "RootModule/ModuleToProcess" angegebene Modul uebergeben werden sollen. Diese kuennen auch eine PSData-Hashtabelle mit zusuetzlichen von PowerShell verwendeten Modulmetadaten enthalten.
PrivateData = @{

    PSData = @{

        # Tags applied to this module. These help with module discovery in online galleries.
        # Tags = @()

        # A URL to the license for this module.
        # LicenseUri = 'https://github.com/megel/Azure-DevOps-Utils/blob/master/LICENSE'

        # A URL to the main website for this project.
        ProjectUri = 'https://dev.azure.com/cc-ppi/'

        # A URL to an icon representing this module.
        # IconUri = ''

        # ReleaseNotes of this module
        ReleaseNotes = '0.1.0

0.1.0
Initial releases 
use help on the individual functions to get info.'

        # External dependent modules of this module
        # ExternalModuleDependencies = ''

    } # End of PSData hashtable
    
 } # End of PrivateData hashtable

# HelpInfo-URI dieses Moduls
# HelpInfoURI = ''

# Standardpruefix fuer Befehle, die aus diesem Modul exportiert werden. Das Standardpruefix kann mit "Import-Module -Prefix" ueberschrieben werden.
# DefaultCommandPrefix = ''

}
