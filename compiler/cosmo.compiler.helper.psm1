function Setup-Compiler{
    $vsixFile = "c:\inetpub\wwwroot\http\ALLanguage.vsix"
    $vsixZipFile = "c:\inetpub\wwwroot\http\ALLanguage.zip"
    $extractFolder = "c:\ALLanguage"
    $compilerFolder = "c:\alc"

    Copy-Item $vsixFile $vsixZipFile
    Expand-Archive $vsixZipFile $extractFolder
    Move-Item (Join-Path -Path $extractFolder -ChildPath "/extension/bin") $compilerFolder
    Remove-Item -Path $extractFolder -Recurse
    Remove-Item $vsixZipFile
}