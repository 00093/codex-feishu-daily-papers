# dailypaper-skills

`dailypaper-skills` is a Codex-first project for collecting daily embodied AI / VLA / world-model / robotics RL papers and publishing the result to Feishu.

This repository is trimmed to the current working path only:

- fetch and rank daily papers
- enrich metadata from arXiv
- create a Feishu daily review
- create Feishu notes for must-read papers
- optionally read from Zotero

## Main Entry Points

- `scripts/run_daily_papers.ps1`
  Full daily pipeline.

- `scripts/run_paper_to_feishu.ps1`
  Single-paper flow.

- `scripts/run_zotero_to_feishu.ps1`
  Zotero collection flow.

- `scripts/check_env.ps1`
  Local environment check.

## Scope

The default ranking is tuned for:

- embodied AI
- VLA / vision-language-action
- robotic world models
- reinforcement learning for robots
- real robot / sim-to-real / manipulation / navigation

It intentionally downranks generic LLM, coding-agent, finance, medical, and media-generation papers.

## Repo Layout

```text
scripts/
  bootstrap_*.ps1
  check_env.ps1
  run_daily_papers.ps1
  run_paper_to_feishu.ps1
  run_zotero_to_feishu.ps1
  review_to_feishu.py
  notes_to_feishu.py

skills/
  daily-papers/
    fetch_and_score.py
    enrich_papers.py
    extract_affiliations.py
    parse_arxiv.py
  daily-papers-review/
    update_history.py
  paper-reader/
    SKILL.md
    assets/
    references/
  _shared/
    user-config.json
    user-config.local.example.json
    user_config.py
```

## Setup

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\check_env.ps1
```

If Python or Feishu CLI is missing:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\bootstrap_portable_python.ps1
powershell -ExecutionPolicy Bypass -File scripts\bootstrap_lark_cli.ps1
```

Optional for better PDF extraction:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\bootstrap_poppler.ps1
```

## Feishu Auth

Required scopes for the daily review / notes flow:

- `wiki:node:create`
- `wiki:node:read`
- `wiki:node:retrieve`
- `wiki:space:read`
- `docs:document.content:read`
- `docx:document:create`
- `docx:document:readonly`
- `docx:document:write_only`
- `im:message`
- `im:chat:read`

Device-code helper scripts are included:

- `scripts/start_lark_scope_login.ps1`
- `scripts/finish_lark_scope_login.ps1`

## Config

Public defaults:

- `skills/_shared/user-config.json`

Local machine override:

- `skills/_shared/user-config.local.json`

Start from:

- `skills/_shared/user-config.local.example.json`

`user-config.local.json` is ignored by git and should contain your local Feishu and preference overrides.

## Run

Daily run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_daily_papers.ps1 -Days 1
```

Single paper:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_paper_to_feishu.ps1 -Paper "https://arxiv.org/abs/2605.03269"
```

Zotero collection:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_zotero_to_feishu.ps1 -Collection "VLA"
```

## Local State

- temp data: `~/tmp/`
- workflow state: `~/.dailypapers/`

Important local outputs:

- `~/tmp/daily_papers_enriched.json`
- `~/tmp/daily_papers_review.md`
- `~/.dailypapers/latest-review.json`
- `~/.dailypapers/notes-index.json`
- `~/.dailypapers/.history.json`

## Publishing To GitHub

Do not commit:

- `.tools/`
- `skills/_shared/user-config.local.json`
- `~/.dailypapers/` exports copied into the repo
- temp markdown / json output

The current `.gitignore` already excludes these.

## License

Apache-2.0. See `LICENSE`.
