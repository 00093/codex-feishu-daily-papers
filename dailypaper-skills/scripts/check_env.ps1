param(
    [switch]$Strict
)

$ErrorActionPreference = "Stop"
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$ConfigPath = Join-Path $RepoRoot "skills\_shared\user-config.json"
$LocalConfigPath = Join-Path $RepoRoot "skills\_shared\user-config.local.json"
$FatalCount = 0
$WarnCount = 0

function Write-Item {
    param(
        [string]$Status,
        [string]$Name,
        [string]$Detail = ""
    )

    $line = "[{0}] {1}" -f $Status, $Name
    if ($Detail) {
        $line = "$line - $Detail"
    }
    Write-Host $line
}

function Add-Fail {
    param([string]$Name, [string]$Detail)
    $script:FatalCount += 1
    Write-Item "FAIL" $Name $Detail
}

function Add-Warn {
    param([string]$Name, [string]$Detail)
    $script:WarnCount += 1
    Write-Item "WARN" $Name $Detail
}

function Add-Pass {
    param([string]$Name, [string]$Detail = "")
    Write-Item "PASS" $Name $Detail
}

function Expand-UserPath {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return ""
    }
    if ($PathValue.StartsWith("~")) {
        return (Join-Path $HOME $PathValue.Substring(2))
    }
    return $PathValue
}

function Get-Config {
    $config = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
    if (Test-Path $LocalConfigPath) {
        $local = Get-Content -Raw -Encoding UTF8 $LocalConfigPath | ConvertFrom-Json
        foreach ($prop in $local.PSObject.Properties) {
            if ($null -ne $config.($prop.Name) -and $config.($prop.Name) -is [pscustomobject] -and $prop.Value -is [pscustomobject]) {
                foreach ($child in $prop.Value.PSObject.Properties) {
                    $config.($prop.Name) | Add-Member -NotePropertyName $child.Name -NotePropertyValue $child.Value -Force
                }
            } else {
                $config | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
            }
        }
    }
    return $config
}

function Test-Executable {
    param(
        [string]$Name,
        [string[]]$Candidates,
        [switch]$Required,
        [string]$WarnText
    )

    foreach ($candidate in $Candidates) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $expanded = Expand-UserPath $candidate
        if ($expanded -match '^\s*powershell(\.exe)?\s+') {
            Add-Pass $Name $expanded
            return $expanded
        }
        if (Test-Path $expanded) {
            Add-Pass $Name $expanded
            return $expanded
        }
        $cmd = Get-Command $expanded -ErrorAction SilentlyContinue
        if ($cmd) {
            Add-Pass $Name $cmd.Source
            return $cmd.Source
        }
    }

    if ($Required) {
        Add-Fail $Name $WarnText
    } else {
        Add-Warn $Name $WarnText
    }
    return $null
}

function Test-Node {
    $embedded = Join-Path $RepoRoot ".tools\node\node.exe"
    if (Test-Path $embedded) {
        $version = & $embedded --version
        Add-Pass "Node.js" "$embedded ($version)"
        return $embedded
    }

    $cmd = Get-Command "node" -ErrorAction SilentlyContinue
    if ($cmd) {
        $version = & node --version
        Add-Pass "Node.js" "$($cmd.Source) ($version)"
        return $cmd.Source
    }

    Add-Warn "Node.js" "Not found. Run scripts\bootstrap_lark_cli.ps1 to install portable Node and lark-cli."
    return $null
}

function Test-Python {
    $embedded = Join-Path $RepoRoot ".tools\python\python.exe"
    if (Test-Path $embedded) {
        $version = & $embedded -c "import sys; print(sys.version.split()[0])"
        Add-Pass "Python" "$embedded ($version)"
        return $embedded
    }

    $candidates = @("python", "python3", "py")
    foreach ($candidate in $candidates) {
        $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
        if (-not $cmd) {
            continue
        }
        if ($cmd.Source -like "*WindowsApps*") {
            continue
        }
        try {
            if ($candidate -eq "py") {
                $version = & $candidate -3 -c "import sys; print(sys.version.split()[0])" 2>$null
                if ($LASTEXITCODE -eq 0 -and $version) {
                    Add-Pass "Python" "py -3 ($version)"
                    return "py -3"
                }
            } else {
                $version = & $candidate -c "import sys; print(sys.version.split()[0])" 2>$null
                if ($LASTEXITCODE -eq 0 -and $version) {
                    Add-Pass "Python" "$candidate ($version)"
                    return $candidate
                }
            }
        } catch {
        }
    }

    Add-Fail "Python" "No working Python found. Run scripts\bootstrap_portable_python.ps1 or install Python 3.8+."
    return $null
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

Add-ToolPaths
$config = Get-Config
Write-Host "DailyPaper environment check"
Write-Host "Repo: $RepoRoot"
Write-Host ""

$python = Test-Python
$node = Test-Node
$null = Test-Executable "Codex CLI" @("codex") -Required -WarnText "Install or repair Codex CLI."
$localRg = Get-ChildItem "$HOME\.vscode\extensions" -Recurse -Filter rg.exe -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($localRg) {
    $null = Test-Executable "rg" @($localRg.FullName, "rg") -WarnText "rg is optional but helpful for Codex skill runs."
}
$null = Test-Executable "curl" @("curl") -Required -WarnText "curl is required for arXiv/HuggingFace fetching."
$localLark = Join-Path $RepoRoot ".tools\bin\lark-cli.cmd"
$larkCli = Test-Executable "lark-cli" @($config.feishu.lark_cli, $localLark, "lark-cli") -Required -WarnText "Feishu upload/push cannot run until lark-cli is installed and authenticated."
$localPopplerBin = Join-Path $RepoRoot ".tools\poppler\Library\bin"
$null = Test-Executable "pdftotext" @((Join-Path $localPopplerBin "pdftotext.exe"), "pdftotext") -WarnText "PDF affiliation extraction will be reduced without poppler pdftotext. Run scripts\bootstrap_poppler.ps1."
$null = Test-Executable "pdfimages" @((Join-Path $localPopplerBin "pdfimages.exe"), "pdfimages") -WarnText "PDF image extraction will be reduced without poppler pdfimages. Run scripts\bootstrap_poppler.ps1."

$zoteroDb = Expand-UserPath $config.paths.zotero_db
$zoteroStorage = Expand-UserPath $config.paths.zotero_storage
if (Test-Path $zoteroDb) {
    Add-Pass "Zotero database" $zoteroDb
} else {
    Add-Warn "Zotero database" "Not found at $zoteroDb. Zotero features will be unavailable."
}
if (Test-Path $zoteroStorage) {
    Add-Pass "Zotero storage" $zoteroStorage
} else {
    Add-Warn "Zotero storage" "Not found at $zoteroStorage. Local PDF lookup will be unavailable."
}

if ($larkCli) {
    try {
        if ($larkCli -match '^\s*powershell(\.exe)?\s+') {
            $authOutput = Invoke-Expression "$larkCli auth status 2>&1"
        } else {
            $authOutput = & $larkCli auth status 2>&1
        }
        if ($LASTEXITCODE -eq 0) {
            Add-Pass "lark-cli auth" "auth status succeeded"
        } else {
            Add-Warn "lark-cli auth" "Run: $larkCli auth login --recommend"
        }
    } catch {
        Add-Warn "lark-cli auth" "Could not check auth. Run: $larkCli auth status"
    }
}

$tmpDir = Join-Path $HOME "tmp"
if (Test-Path $tmpDir) {
    Add-Pass "Temp directory" $tmpDir
} else {
    Add-Warn "Temp directory" "Will be created at $tmpDir."
}

Write-Host ""
Write-Host "Result: $FatalCount fatal issue(s), $WarnCount warning(s)."
if ($FatalCount -gt 0 -or ($Strict -and $WarnCount -gt 0)) {
    exit 1
}
