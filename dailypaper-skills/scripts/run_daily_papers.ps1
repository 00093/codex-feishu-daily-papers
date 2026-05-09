param(
    [int]$Days = 1,
    [string]$Model = "gpt-5.5",
    [switch]$SkipFetch,
    [switch]$SkipReview,
    [switch]$SkipNotes,
    [switch]$DangerouslyBypassSandbox
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$TmpDir = Join-Path $HOME "tmp"
$TopPath = Join-Path $TmpDir "daily_papers_top30.json"
$EnrichedPath = Join-Path $TmpDir "daily_papers_enriched.json"
$LocalDataDir = Join-Path $HOME ".dailypapers"
$LatestReviewMetaPath = Join-Path $LocalDataDir "latest-review.json"
$NotesIndexPath = Join-Path $LocalDataDir "notes-index.json"
$LocalPopplerBin = Join-Path $RepoRoot ".tools\poppler\Library\bin"
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
if (Test-Path $LocalPopplerBin) {
    $env:PATH = "$LocalPopplerBin;$env:PATH"
}

function Get-LarkCliCommand {
    $configPath = Join-Path $RepoRoot "skills\_shared\user-config.local.json"
    if (-not (Test-Path $configPath)) {
        $configPath = Join-Path $RepoRoot "skills\_shared\user-config.json"
    }
    $config = Get-Content -Raw -Encoding UTF8 $configPath | ConvertFrom-Json
    return [string]$config.feishu.lark_cli
}

function Invoke-LarkCli {
    param([string[]]$Arguments)

    $command = Get-LarkCliCommand
    if ([string]::IsNullOrWhiteSpace($command)) {
        throw "lark_cli is not configured in skills\_shared\user-config.local.json."
    }

    if ($command -match '^\s*powershell(\.exe)?\s+') {
        Invoke-Expression "$command $($Arguments -join ' ')"
    } else {
        & $command @Arguments
    }
    return $LASTEXITCODE
}

function Add-ToolPaths {
    $pathsToAdd = @()

    $localPythonDir = Join-Path $RepoRoot ".tools\python"
    if (Test-Path $localPythonDir) {
        $pathsToAdd += $localPythonDir
    }

    $localNodeDir = Join-Path $RepoRoot ".tools\node"
    if (Test-Path $localNodeDir) {
        $pathsToAdd += $localNodeDir
    }

    $localNpmGlobalDir = Join-Path $RepoRoot ".tools\npm-global"
    if (Test-Path $localNpmGlobalDir) {
        $pathsToAdd += $localNpmGlobalDir
    }

    $vscodeBin = Get-ChildItem "$HOME\.vscode\extensions" -Recurse -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -like "*\bin\windows-x86_64" } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($vscodeBin) {
        $pathsToAdd += $vscodeBin.FullName
    }

    if ($pathsToAdd.Count -gt 0) {
        $env:PATH = (($pathsToAdd + @($env:PATH)) -join ";")
    }
}

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

function Assert-LarkReady {
    Write-Host "Checking Feishu CLI auth..."
    $output = Invoke-LarkCli -Arguments @("auth", "status") 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $output
        $lark = Get-LarkCliCommand
        throw @"
Feishu CLI is installed but not configured/authenticated.

Run these two commands, complete the browser verification, then rerun this workflow:

$lark config init --new
$lark auth login --recommend
"@
    }

    $scopeString = $RequiredFeishuScopes -join " "
    $scopeCheck = Invoke-LarkCli -Arguments @("auth", "check", "--scope", $scopeString) 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $scopeCheck
        $lark = Get-LarkCliCommand
        throw @"
Feishu auth exists, but the granted scopes are not enough for document write/send operations.

Run this command and complete the browser authorization:

$lark auth login --scope "$scopeString"
"@
    }
}

function Resolve-Python {
    $embedded = Join-Path $RepoRoot ".tools\python\python.exe"
    if (Test-Path $embedded) {
        return @($embedded)
    }

    foreach ($candidate in @("python", "python3")) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($cmd -and $cmd.Source -notlike "*WindowsApps*") {
            try {
                & $candidate -c "import sys" 2>$null
                if ($LASTEXITCODE -eq 0) {
                    return @($candidate)
                }
            } catch {
            }
        }
    }

    $py = Get-Command "py" -ErrorAction SilentlyContinue
    if ($py) {
        try {
            & py -3 -c "import sys" 2>$null
            if ($LASTEXITCODE -eq 0) {
                return @("py", "-3")
            }
        } catch {
        }
    }

    throw "No working Python found. Run scripts\bootstrap_portable_python.ps1 first."
}

function Invoke-Python {
    param(
        [string[]]$PythonCommand,
        [string[]]$Arguments,
        [string]$StdoutPath
    )

    $exe = $PythonCommand[0]
    $prefixArgs = @()
    if ($PythonCommand.Length -gt 1) {
        $prefixArgs = $PythonCommand[1..($PythonCommand.Length - 1)]
    }
    $allArgs = @($prefixArgs + $Arguments)

    if ($StdoutPath) {
        $stderrPath = "$StdoutPath.stderr.log"
        if (Test-Path $stderrPath) {
            Remove-Item -Force $stderrPath
        }
        $process = Start-Process -FilePath $exe -ArgumentList $allArgs -NoNewWindow -Wait -PassThru -RedirectStandardOutput $StdoutPath -RedirectStandardError $stderrPath
        if (Test-Path $stderrPath) {
            Get-Content -Encoding UTF8 $stderrPath | ForEach-Object { Write-Host $_ }
        }
        return $process.ExitCode
    } else {
        & $exe @allArgs
        return $LASTEXITCODE
    }
}

function Invoke-CodexStep {
    param(
        [string]$Name,
        [string]$Prompt
    )

    $codex = Resolve-Codex

    $args = @("exec", "-m", $Model, "-C", $RepoRoot)
    if ($DangerouslyBypassSandbox) {
        $args += "--dangerously-bypass-approvals-and-sandbox"
    } else {
        # On Windows, Feishu user auth is stored outside the workspace and the
        # Codex workspace-write sandbox cannot reliably access it. Use
        # danger-full-access so review/notes steps can see the valid token.
        $sandboxMode = if ($env:OS -eq "Windows_NT") { "danger-full-access" } else { "workspace-write" }
        $args += @("--sandbox", $sandboxMode, "--add-dir", $HOME)
    }
    $args += $Prompt

    Write-Host ""
    Write-Host "Starting Codex step: $Name"
    & $codex @args
    if ($LASTEXITCODE -ne 0) {
        throw "Codex step failed: $Name"
    }
}

function Invoke-RepoPythonScript {
    param(
        [string]$ScriptPath,
        [string[]]$Arguments
    )

    $python = Resolve-Python
    $exitCode = Invoke-Python -PythonCommand $python -Arguments @($ScriptPath) + $Arguments
    if ($exitCode -ne 0) {
        throw "Python script failed: $ScriptPath"
    }
}

if ($Days -lt 1) {
    throw "Days must be >= 1."
}

Add-ToolPaths

New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null
New-Item -ItemType Directory -Force -Path $LocalDataDir | Out-Null

$python = Resolve-Python

if (-not $SkipFetch) {
    $fetchScript = Join-Path $RepoRoot "skills\daily-papers\fetch_and_score.py"
    $enrichScript = Join-Path $RepoRoot "skills\daily-papers\enrich_papers.py"

    Write-Host "Fetching papers for $Days day(s)..."
    $exitCode = Invoke-Python -PythonCommand $python -Arguments @($fetchScript, "--days", "$Days") -StdoutPath $TopPath
    if ($exitCode -ne 0) {
        throw "fetch_and_score.py failed."
    }

    Write-Host "Enriching papers..."
    $exitCode = Invoke-Python -PythonCommand $python -Arguments @($enrichScript, $TopPath, $EnrichedPath)
    if ($exitCode -ne 0) {
        throw "enrich_papers.py failed."
    }
}

if (-not (Test-Path $EnrichedPath)) {
    throw "Enriched input not found: $EnrichedPath"
}

if (-not $SkipReview -or -not $SkipNotes) {
    Assert-LarkReady
}

if (-not $SkipReview) {
    if (Test-Path $LatestReviewMetaPath) {
        Remove-Item -Force $LatestReviewMetaPath
    }
    $reviewScript = Join-Path $RepoRoot "scripts\review_to_feishu.py"
    Invoke-RepoPythonScript -ScriptPath $reviewScript -Arguments @("$Days")

    if (-not (Test-Path $LatestReviewMetaPath)) {
        throw "Review step finished without generating $LatestReviewMetaPath. Stopping before notes."
    }
}

if (-not $SkipNotes) {
    $notesScript = Join-Path $RepoRoot "scripts\notes_to_feishu.py"
    Invoke-RepoPythonScript -ScriptPath $notesScript -Arguments @()
}

Write-Host ""
Write-Host "Daily papers workflow finished."
Write-Host "Enriched data: $EnrichedPath"
