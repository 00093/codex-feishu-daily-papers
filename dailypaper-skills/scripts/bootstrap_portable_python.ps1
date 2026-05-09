param(
    [string]$Version = "3.12.10",
    [string]$TargetDir = ".tools\python"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TargetPath = Join-Path $RepoRoot $TargetDir
$ZipPath = Join-Path $RepoRoot ".tools\python-$Version-embed-amd64.zip"
$Url = "https://www.python.org/ftp/python/$Version/python-$Version-embed-amd64.zip"
$ExpectedMd5 = if ($Version -eq "3.12.10") { "fe8ef205f2e9c3ba44d0cf9954e1abd3" } else { "" }

New-Item -ItemType Directory -Force -Path (Split-Path $ZipPath) | Out-Null
New-Item -ItemType Directory -Force -Path $TargetPath | Out-Null

Write-Host "Downloading portable Python $Version..."
Write-Host $Url
curl.exe -L $Url -o $ZipPath

if ($ExpectedMd5) {
    $actual = (Get-FileHash -Algorithm MD5 $ZipPath).Hash.ToLowerInvariant()
    if ($actual -ne $ExpectedMd5) {
        throw "MD5 mismatch for $ZipPath. Expected $ExpectedMd5, got $actual."
    }
    Write-Host "Checksum OK."
}

Write-Host "Extracting to $TargetPath..."
Expand-Archive -Force -Path $ZipPath -DestinationPath $TargetPath

$python = Join-Path $TargetPath "python.exe"
if (-not (Test-Path $python)) {
    throw "python.exe was not found after extraction."
}

& $python -c "import sys; print(sys.version)"
Write-Host "Portable Python is ready: $python"
