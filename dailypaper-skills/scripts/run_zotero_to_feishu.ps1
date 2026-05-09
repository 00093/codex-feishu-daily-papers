param(
    [Parameter(Mandatory = $true)]
    [string]$Collection,
    [string]$Model = "gpt-5.5",
    [int]$Limit = 0,
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

$limitText = if ($Limit -gt 0) { "Process at most $Limit papers." } else { "Process every paper in the collection that still needs a note." }

$prompt = @(
    "Use the repository Zotero batch paper-reading workflow and save paper notes to Feishu.",
    "",
    "Zotero collection:",
    $Collection,
    "",
    "Limit:",
    $limitText,
    "",
    "Requirements:",
    "1. Read skills/paper-reader/SKILL.md, skills/paper-reader/references/zotero-guide.md, and skills/_shared/user-config.json.",
    "2. Recursively read papers in that Zotero collection and child collections. Prefer existing Feishu notes in notes-index.json.",
    "3. Generate a Feishu note for each unprocessed paper; do not write to Obsidian.",
    "4. Update ~/.dailypapers/notes-index.json after each completed paper so the workflow can resume after interruption.",
    "5. If lark-cli, Feishu auth, Zotero paths, or config is unavailable, report the exact missing item and next command; do not pretend completion."
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
    throw "Codex Zotero batch step failed."
}
