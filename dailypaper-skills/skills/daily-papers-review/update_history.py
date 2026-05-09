#!/usr/bin/env python3
"""
update_history.py - Update the recommendation history file.

Stores history under local_data_dir() / .history.json instead of Obsidian.
"""

import argparse
import json
import re
import sys
from datetime import datetime, timedelta
from pathlib import Path

_SHARED_DIR = Path(__file__).resolve().parent.parent / "_shared"
if str(_SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(_SHARED_DIR))

from user_config import history_file_path, temp_file_path

HISTORY_FILE = history_file_path()
DAYS_TO_KEEP = 30


def load_history() -> list:
    if not HISTORY_FILE.exists():
        return []
    try:
        with open(HISTORY_FILE, 'r', encoding='utf-8') as f:
            return json.load(f)
    except (json.JSONDecodeError, FileNotFoundError):
        return []


def save_history(history: list):
    HISTORY_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(HISTORY_FILE, 'w', encoding='utf-8') as f:
        json.dump(history, f, ensure_ascii=False, indent=2)


def extract_arxiv_id_from_url(url: str) -> str:
    m = re.search(r'arxiv\.org/abs/(\d+\.\d+)', url)
    return m.group(1) if m else ""


def load_from_enriched(path: str) -> list:
    with open(path, 'r', encoding='utf-8') as f:
        papers = json.load(f)

    entries = []
    for p in papers:
        arxiv_id = p.get('arxiv_id', '')
        if not arxiv_id:
            arxiv_id = extract_arxiv_id_from_url(p.get('url', ''))
        if arxiv_id:
            entries.append({
                'id': arxiv_id,
                'title': p.get('title', '')[:200],
                'score': p.get('score', 0),
            })
    return entries


def load_from_recommendation(path: str) -> list:
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()
    arxiv_ids = re.findall(r'arxiv\.org/abs/(\d+\.\d+)', content)
    return [{'id': arxiv_id, 'title': ''} for arxiv_id in arxiv_ids]


def update_history(entries: list, date: str, preserve_earliest: bool = True):
    history = load_history()
    existing_ids = {h.get('id') for h in history if h.get('id')}

    added = 0
    for entry in entries:
        arxiv_id = entry.get('id', '')
        if not arxiv_id:
            continue

        if arxiv_id not in existing_ids:
            history.append({
                'id': arxiv_id,
                'date': date,
                'title': entry.get('title', ''),
            })
            existing_ids.add(arxiv_id)
            added += 1
        elif preserve_earliest:
            for h in history:
                if h.get('id') == arxiv_id and h.get('date', '') > date:
                    h['date'] = date
                    break

    cutoff_date = (datetime.strptime(date, '%Y-%m-%d') - timedelta(days=DAYS_TO_KEEP)).strftime('%Y-%m-%d')
    history = [h for h in history if h.get('date', '') >= cutoff_date]

    save_history(history)
    return added


def main():
    parser = argparse.ArgumentParser(description='Update recommendation history')
    parser.add_argument('--arxiv-ids', nargs='+', help='arXiv IDs to add')
    parser.add_argument('--from-enriched', help='Path to enriched JSON file')
    parser.add_argument('--from-recommendation', help='Path to recommendation markdown file')
    parser.add_argument('--date', required=True, help='Date (YYYY-MM-DD)')
    args = parser.parse_args()

    entries = []
    if args.arxiv_ids:
        entries = [{'id': aid, 'title': ''} for aid in args.arxiv_ids]
    elif args.from_enriched:
        entries = load_from_enriched(args.from_enriched)
    elif args.from_recommendation:
        entries = load_from_recommendation(args.from_recommendation)
    else:
        auto_enriched = temp_file_path('daily_papers_enriched.json')
        if auto_enriched.exists():
            entries = load_from_enriched(str(auto_enriched))
        else:
            print('Error: missing input', file=sys.stderr)
            sys.exit(1)

    added = update_history(entries, args.date)
    print(f'Added {added} new entries to history')


if __name__ == '__main__':
    main()
