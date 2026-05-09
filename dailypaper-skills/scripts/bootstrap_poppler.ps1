param(
    [string]$Version = "25.12.0-0"
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ToolsDir = Join-Path $RepoRoot ".tools"
$TargetDir = Join-Path $ToolsDir "poppler"
$ZipPath = Join-Path $ToolsDir "poppler-$Version.zip"
$ExtractDir = Join-Path $ToolsDir "poppler-extract"
$Url = "https://github.com/oschwartz10612/poppler-windows/releases/download/v$Version/Release-$Version.zip"

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null

if (-not (Test-Path (Join-Path $TargetDir "Library\bin\pdftotext.exe"))) {
    Write-Host "Downloading Poppler for Windows $Version..."
    Write-Host $Url
    curl.exe -L $Url -o $ZipPath
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ZipPath) -or (Get-Item $ZipPath).Length -lt 1024) {
        throw "Poppler download failed. Re-run this script later or install Poppler manually and add pdftotext/pdfimages to PATH."
    }

    if (Test-Path $ExtractDir) {
        Remove-Item -Recurse -Force $ExtractDir
    }
    New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
    Expand-Archive -Force -Path $ZipPath -DestinationPath $ExtractDir

    $libraryDir = Get-ChildItem -Path $ExtractDir -Recurse -Directory |
        Where-Object { Test-Path (Join-Path $_.FullName "bin\pdftotext.exe") } |
        Select-Object -First 1

    if (-not $libraryDir) {
        throw "Could not locate Library/bin/pdftotext.exe in extracted Poppler package."
    }

    if (Test-Path $TargetDir) {
        Remove-Item -Recurse -Force $TargetDir
    }
    New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
    Copy-Item -Path $libraryDir.FullName -Destination (Join-Path $TargetDir "Library") -Recurse -Force
}

$binDir = Join-Path $TargetDir "Library\bin"
& (Join-Path $binDir "pdftotext.exe") -v 2>&1 | Select-Object -First 1
& (Join-Path $binDir "pdfimages.exe") -v 2>&1 | Select-Object -First 1
Write-Host "Poppler is ready: $binDir"
