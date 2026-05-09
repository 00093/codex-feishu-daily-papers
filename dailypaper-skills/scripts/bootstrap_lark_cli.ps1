param(
    [string]$NodeVersion = "24.15.0",
    [string]$Registry = "https://registry.npmmirror.com",
    [switch]$SkipNpmInstall
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ToolsDir = Join-Path $RepoRoot ".tools"
$NodeDir = Join-Path $ToolsDir "node"
$NodeZip = Join-Path $ToolsDir "node-v$NodeVersion-win-x64.zip"
$NodeExtractRoot = Join-Path $ToolsDir "node-v$NodeVersion-win-x64"
$NodeUrl = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip"
$NpmPrefix = Join-Path $ToolsDir "npm-global"
$BinDir = Join-Path $ToolsDir "bin"
$LarkWrapper = Join-Path $BinDir "lark-cli.cmd"
$LarkPsWrapper = Join-Path $BinDir "lark-cli.ps1"
$ConfigPath = Join-Path $RepoRoot "skills\_shared\user-config.local.json"

New-Item -ItemType Directory -Force -Path $ToolsDir, $NpmPrefix, $BinDir | Out-Null

if (-not (Test-Path (Join-Path $NodeDir "node.exe"))) {
    Write-Host "Downloading portable Node.js $NodeVersion..."
    Write-Host $NodeUrl
    curl.exe -L $NodeUrl -o $NodeZip

    Write-Host "Extracting Node.js..."
    Expand-Archive -Force -Path $NodeZip -DestinationPath $ToolsDir
    if (Test-Path $NodeDir) {
        Remove-Item -Recurse -Force $NodeDir
    }
    Rename-Item -Path $NodeExtractRoot -NewName "node"
}

$env:PATH = "$NodeDir;$NpmPrefix;$env:PATH"
$nodeExe = Join-Path $NodeDir "node.exe"
$npmCmd = Join-Path $NodeDir "npm.cmd"

& $nodeExe --version
& $npmCmd --version

if (-not $SkipNpmInstall) {
    Write-Host "Installing @larksuite/cli to $NpmPrefix..."
    & $npmCmd install -g @larksuite/cli --prefix $NpmPrefix --registry=$Registry
    if ($LASTEXITCODE -ne 0) {
        throw "npm install @larksuite/cli failed."
    }
}

$installedCli = Join-Path $NpmPrefix "lark-cli.cmd"
if (-not (Test-Path $installedCli)) {
    throw "lark-cli.cmd was not found after npm install: $installedCli"
}

$wrapper = @"
@echo off
"$nodeExe" "$NpmPrefix\node_modules\@larksuite\cli\scripts\run.js" %*
"@
Set-Content -Path $LarkWrapper -Value $wrapper -Encoding Default

$psWrapper = @"
& "$nodeExe" "$NpmPrefix\node_modules\@larksuite\cli\scripts\run.js" @args
exit `$LASTEXITCODE
"@
Set-Content -Path $LarkPsWrapper -Value $psWrapper -Encoding UTF8

$localConfig = [ordered]@{}
if (Test-Path $ConfigPath) {
    $loadedConfig = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
    foreach ($prop in $loadedConfig.PSObject.Properties) {
        $localConfig[$prop.Name] = $prop.Value
    }
}
if (-not $localConfig.Contains("feishu")) {
    $localConfig["feishu"] = [ordered]@{}
}
if ($localConfig["feishu"] -isnot [System.Collections.IDictionary]) {
    $feishu = [ordered]@{}
    foreach ($prop in $localConfig["feishu"].PSObject.Properties) {
        $feishu[$prop.Name] = $prop.Value
    }
    $localConfig["feishu"] = $feishu
}
$localConfig["feishu"]["lark_cli"] = "powershell -ExecutionPolicy Bypass -File `"$LarkPsWrapper`""
$localConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $ConfigPath -Encoding UTF8

Write-Host "lark-cli wrapper: $LarkWrapper"
Write-Host "Config updated: $ConfigPath"
Write-Host ""
Write-Host "Next manual/auth step:"
Write-Host "$LarkWrapper config init"
Write-Host "$LarkWrapper auth login --recommend"
Write-Host "$LarkWrapper auth status"
