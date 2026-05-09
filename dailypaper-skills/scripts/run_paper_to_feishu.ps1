param(
    [Parameter(Mandatory = $true)]
    [string]$Paper,
    [string]$Mode = "full",
    [string]$Model = "gpt-5.5",
    [switch]$DangerouslyBypassSandbox
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$RequiredFeishuScopes = @(
    "wiki:node:create",
    "wiki:node:read",
    "wiki:node:retrieve",
    "wiki:space:read",
    "docs:document.content:read",
    "docx:document:create",
    "docx:document:readonly",
    "docx:document:write_only",
    "im:message",
    "im:chat:read"
)

function Resolve-Codex {
    $cmd = Get-Command "codex" -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    $vscodeCodex = Get-ChildItem "$HOME\.vscode\extensions" -Recurse -Filter codex.exe -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($vscodeCodex) {
        return $vscodeCodex.FullName
    }

    throw "codex CLI was not found. Install Codex CLI or expose codex.exe in PATH."
}
$codex = Resolve-Codex

$config = Get-Content -Raw -Encoding UTF8 (Join-Path $RepoRoot "skills\_shared\user-config.local.json") | ConvertFrom-Json
$larkCli = [string]$config.feishu.lark_cli
if ([string]::IsNullOrWhiteSpace($larkCli)) {
    throw "lark_cli is not configured in skills\_shared\user-config.local.json."
}
if ($larkCli -match '^\s*powershell(\.exe)?\s+') {
    Invoke-Expression "$larkCli auth status"
} else {
    & $larkCli auth status
}
if ($LASTEXITCODE -ne 0) {
    throw "Feishu CLI is not configured/authenticated. Run: $larkCli config init --new ; then: $larkCli auth login --recommend"
}

$scopeString = $RequiredFeishuScopes -join " "
if ($larkCli -match '^\s*powershell(\.exe)?\s+') {
    Invoke-Expression "$larkCli auth check --scope `"$scopeString`""
} else {
    & $larkCli auth check --scope $scopeString
}
if ($LASTEXITCODE -ne 0) {
    throw "Feishu CLI login exists but lacks required scopes. Run: $larkCli auth login --scope `"$scopeString`""
}

$prompt = @(
    "Use the repository paper-reader workflow to read and analyze this paper, then save the result to Feishu.",
    "",
    "Paper input:",
    $Paper,
    "",
    "Reading mode:",
    $Mode,
    "",
    "Requirements:",
    "1. Read skills/paper-reader/SKILL.md and skills/_shared/user-config.json.",
    "2. Save the output to the Feishu wiki node configured as wenxian_node_token; do not write to Obsidian.",
    "3. In full mode, preserve formulas, figures, tables, method contribution, experiments, limitations, and reproducibility assessment.",
    "4. After creating or updating the Feishu doc, write the record to ~/.dailypapers/notes-index.json.",
    "5. If lark-cli, Feishu auth, or config is unavailable, report the exact missing item and next command; do not pretend completion."
) -join "`n"

$args = @("exec", "-m", $Model, "-C", $RepoRoot)
if ($DangerouslyBypassSandbox) {
    $args += "--dangerously-bypass-approvals-and-sandbox"
} else {
    $sandboxMode = if ($env:OS -eq "Windows_NT") { "danger-full-access" } else { "workspace-write" }
    $args += @("--sandbox", $sandboxMode, "--add-dir", $HOME)
}
$args += $prompt

& $codex @args
if ($LASTEXITCODE -ne 0) {
    throw "Codex paper-reader step failed."
}
