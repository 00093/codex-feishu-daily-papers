param(
    [Parameter(Mandatory = $true)]
    [string]$Scope
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$LarkCli = Join-Path $RepoRoot ".tools\bin\lark-cli.ps1"
$StateDir = Join-Path $HOME ".dailypapers"
$StatePath = Join-Path $StateDir "pending-lark-login.json"

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null

$output = powershell -ExecutionPolicy Bypass -File $LarkCli auth login --scope $Scope --no-wait --json
if ($LASTEXITCODE -ne 0) {
    throw $output
}

$json = $output | ConvertFrom-Json
$json | Add-Member -NotePropertyName scope -NotePropertyValue $Scope -Force
$json | ConvertTo-Json -Depth 10 | Set-Content -Path $StatePath -Encoding UTF8

Write-Host "Pending login saved to: $StatePath"
Write-Host ""
Write-Host "Open this URL in the browser and finish authorization:"
Write-Host $json.verification_uri_complete
Write-Host ""
Write-Host "Then run:"
Write-Host "powershell -ExecutionPolicy Bypass -File `"$RepoRoot\scripts\finish_lark_scope_login.ps1`""
