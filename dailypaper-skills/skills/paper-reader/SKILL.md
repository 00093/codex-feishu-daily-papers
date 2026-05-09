---
name: paper-reader
description: |
  Read a single academic paper from arXiv, local PDF, or Zotero metadata and
  generate a structured Feishu note. Use when the workflow needs a compact but
  useful note for embodied AI / VLA / world model / robotics papers.
---

# paper-reader

This repository now uses `paper-reader` as a small reference bundle rather than
an agent-orchestrated skill. The active entrypoints are:

- `scripts/run_paper_to_feishu.ps1`
- `scripts/run_zotero_to_feishu.ps1`
- `scripts/notes_to_feishu.py`

## Current Role

Use the assets and references in this folder for:

- paper-note structure
- Zotero helper queries
- lightweight note generation

## Important References

- `assets/paper-note-template.md`
- `assets/zotero_helper.py`
- `references/zotero-guide.md`

## Output Target

Primary output target is Feishu, not Obsidian.

When adapting or extending this folder, prefer:

- concise structured markdown
- method name
- title / authors / affiliations / links
- short method summary
- selected figure or caption hints
- a short “why it matters” section for embodied / VLA / RL / world-model work
