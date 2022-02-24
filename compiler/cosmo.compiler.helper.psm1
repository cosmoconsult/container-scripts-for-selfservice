function Setup-Compiler{
    $vsixFile = "c:\inetpub\wwwroot\http\ALLanguage.vsix"
    $vsixZipFile = "c:\inetpub\wwwroot\http\ALLanguage.zip"
    $extractFolder = "c:\ALLanguage"
    $compilerFolder = "c:\alc"

    Copy-Item $vsixFile $vsixZipFile
    $durationExtract = Measure-Command {Expand-Archive $vsixZipFile $extractFolder}
    Move-Item (Join-Path -Path $extractFolder -ChildPath "/extension/bin") $compilerFolder
    Remove-Item -Path $extractFolder -Recurse
    Remove-Item $vsixZipFile
    Write-Host ("Extracting compiler to 'c:\alc\alc.exe'" )
    Write-Host ("Extraction took {0}" -f $durationExtract.TotalSeconds)
}
Export-ModuleMember -Function Setup-Compiler