function Import-Fonts {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$false)]
        [string]$Path = "c:/fonts",
        [Parameter(Mandatory=$false)]
        [System.Object]$telemetryClient = $null
    )
    
    begin {
        if (! $telemetryClient) {
            $telemetryClient = Get-TelemetryClient -ErrorAction SilentlyContinue
        }

        $importFiles = $false
    }
    
    process {

        function Import-Font ($path) {
#*******************************************************************
#  Load C# code
#*******************************************************************
$fontCSharpCode = @'
using System;
using System.Collections.Generic;
using System.Text;
using System.IO;
using System.Runtime.InteropServices;
namespace FontResource
{
    public class AddRemoveFonts
    {
        [DllImport("gdi32.dll")]
        static extern int AddFontResource(string lpFilename);
        public static int AddFont(string fontFilePath) {
            try 
            {
                return AddFontResource(fontFilePath);
            }
            catch
            {
                return 0;
            }
        }
    }
}
'@

                    Add-Type $fontCSharpCode
                    
                    # Create hashtable containing valid font file extensions and text to append to Registry entry name.
                    $hashFontFileTypes = @{}
                    $hashFontFileTypes.Add(".fon", "")
                    $hashFontFileTypes.Add(".fnt", "")
                    $hashFontFileTypes.Add(".ttf", " (TrueType)")
                    $hashFontFileTypes.Add(".ttc", " (TrueType)")
                    $hashFontFileTypes.Add(".otf", " (OpenType)")
                    $fontRegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
        
                    $fileDir  = split-path $path
                    $fileName = split-path $path -leaf
                    $fileExt = (Get-Item $path).extension
                    $fileBaseName = $fileName -replace($fileExt ,"")
            
                    $shell = new-object -com shell.application
                    $myFolder = $shell.Namespace($fileDir)
                    $fileobj = $myFolder.Items().Item($fileName)
                    $fontName = $myFolder.GetDetailsOf($fileobj,21)
            
                    if ($fontName -eq "") { $fontName = $fileBaseName }
            
                    $retVal = [FontResource.AddRemoveFonts]::AddFont($path)
            
                    if ($retVal -eq 0) {
                        Write-Host -ForegroundColor Red "Font `'$($path)`'`' installation failed"
                    } else {
                        Write-Host -ForegroundColor Green "Font `'$($path)`' installed successfully"
                        Set-ItemProperty -path "$($fontRegistryPath)" -name "$($fontName)$($hashFontFileTypes.item($fileExt))" -value "$($fileName)" -type STRING
                    }
        }

        # Initialize, if files / folder are/is present
        if (! $importFiles -and (Get-Item -Path $Path -ErrorAction SilentlyContinue)) {
            $importFiles = $true
            Add-ArtifactsLog -message "Import Object Files"
        }

        $fontsFolderPath = "C:\Windows\Fonts"
        $ExistingFonts   = Get-ChildItem -LiteralPath $fontsFolderPath | % { $_.Name }
        
        Get-ChildItem -LiteralPath $Path -Exclude @("*.zip", "*.txt", "*.ini") -ErrorAction Ignore | % {
            if (! $ExistingFonts.Contains($_.Name) -and $_.Extension -ne ".ini") {
                
                $properties = @{"path" = $Path; "Font" = $_.Name; "FontPath" = $_.FullName; }

                try
                {
                    $WindowsFontPath = Join-Path "c:\Windows\Fonts" $_.Name
                    $fullName = $_.FullName
                
                    # Copy font to destination
                    Copy-item -Path $fullName -Destination $WindowsFontPath
    
                    # Import the font
                    Import-Font $WindowsFontPath -ErrorAction SilentlyContinue -ErrorVariable err -WarningVariable warn -InformationVariable info

                    $info | foreach { Add-ArtifactsLog -kind FOB -message "$_" -severity Info  -data $properties }
                    $warn | foreach { Add-ArtifactsLog -kind FOB -message "$_" -severity Warn  -data $properties }
                    $err  | foreach { Add-ArtifactsLog -kind FOB -message "$_" -severity Error -data $properties }
                    $success = ! $err
                    if ($success) { Add-ArtifactsLog -kind FOB -message "Import Font ... successful" -data $properties -success success }
                }
                catch {
                    Add-ArtifactsLog -kind Font -message "Import FONT FAILED:$([System.Environment]::NewLine)  $($_.Exception.Message)" -data $properties -severity Error -success fail
                    Invoke-LogError -exception $_.Exception -telemetryClient $telemetryClient -properties $properties -operation "Import Font Artifact"
                }
                Invoke-LogOperation -name "Import Font" -started $started -properties $properties -telemetryClient $telemetryClient -success $success
                Add-ArtifactsLog -message " "
            }
        }

    }
    
    end {
        if ($importFiles) {
            Add-ArtifactsLog "Import Fonts done."
        }
    }
}
Export-ModuleMember -Function Import-Fonts