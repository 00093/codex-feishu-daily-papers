# Architecture

This repository currently runs one direct pipeline:

```text
fetch_and_score.py
  -> daily_papers_top30.json
  -> enrich_papers.py
  -> daily_papers_enriched.json
  -> review_to_feishu.py
  -> notes_to_feishu.py
```

## Fetch

File:
`skills/daily-papers/fetch_and_score.py`

Responsibilities:

- fetch Hugging Face daily papers
- fetch Hugging Face trending papers
- fetch arXiv candidates
- score papers with robotics-focused heuristics
- deduplicate and filter by local history

Output:

- `~/tmp/daily_papers_top30.json`

## Enrich

File:
`skills/daily-papers/enrich_papers.py`

Responsibilities:

- fetch arXiv HTML pages
- extract authors, affiliations, figure URL, section headers, captions
- infer method names and short summaries
- mark likely real-world experiment signals

Output:

- `~/tmp/daily_papers_enriched.json`

## Review

File:
`scripts/review_to_feishu.py`

Responsibilities:

- classify papers into review buckets
- build the daily markdown review
- create a Feishu document
- update local metadata and `.history.json`

Outputs:

- `~/tmp/daily_papers_review.md`
- `~/.dailypapers/latest-review.json`
- `~/.dailypapers/.history.json`

## Notes

File:
`scripts/notes_to_feishu.py`

Responsibilities:

- read must-read titles from `latest-review.json`
- create one Feishu note per must-read paper
- write / update `notes-index.json`
- backfill note links into the daily review doc

Output:

- `~/.dailypapers/notes-index.json`

## Wrappers

Primary wrapper:

- `scripts/run_daily_papers.ps1`

Other wrappers:

- `scripts/run_paper_to_feishu.ps1`
- `scripts/run_zotero_to_feishu.ps1`
- `scripts/check_env.ps1`

## Config

Public defaults:

- `skills/_shared/user-config.json`

Local override:

- `skills/_shared/user-config.local.json`

The loader merges the local override on top of the public config.
