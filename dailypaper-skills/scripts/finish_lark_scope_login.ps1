$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LarkCli = Join-Path $RepoRoot ".tools\bin\lark-cli.ps1"
$StatePath = Join-Path $HOME ".dailypapers\pending-lark-login.json"

if (-not (Test-Path $StatePath)) {
    throw "No pending login found at $StatePath. Run start_lark_scope_login.ps1 first."
}

$state = Get-Content -Raw -Encoding UTF8 $StatePath | ConvertFrom-Json
if (-not $state.device_code) {
    throw "Pending login file does not contain device_code."
}

powershell -ExecutionPolicy Bypass -File $LarkCli auth login --device-code $state.device_code
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) {
    throw "Finishing device login failed."
}

Remove-Item -Force $StatePath
Write-Host "Login completed and pending state cleared."
