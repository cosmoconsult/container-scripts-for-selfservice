[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [long]$Length
)

if ($Length -le 0) {
    throw "Input length must be greater than zero"
}

$directory = Split-Path -Path $Path -Parent
New-Item -Path $directory -ItemType Directory -Force | Out-Null

$inputStream = [Console]::OpenStandardInput()
try {
    $outputStream = [System.IO.File]::Open($Path, [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $buffer = [byte[]]::new(81920)
        [long]$remaining = $Length
        while ($remaining -gt 0) {
            $bytesToRead = [int][Math]::Min($buffer.Length, $remaining)
            $bytesRead = $inputStream.Read($buffer, 0, $bytesToRead)
            if ($bytesRead -le 0) {
                throw "Stream ended with $remaining bytes remaining"
            }

            $outputStream.Write($buffer, 0, $bytesRead)
            $remaining -= $bytesRead
        }
    }
    finally {
        $outputStream.Dispose()
    }
}
catch {
    Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    throw
}
