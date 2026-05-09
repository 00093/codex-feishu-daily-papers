#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

_SHARED_DIR = Path(__file__).resolve().parents[1] / "skills" / "_shared"
if str(_SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(_SHARED_DIR))

from user_config import (
    latest_review_meta_path,
    lark_cli_path,
    notes_index_file_path,
    push_user_open_id,
    temp_file_path,
    wiki_space_id,
)


def load_json(path: Path) -> dict | list:
    return json.loads(path.read_text(encoding="utf-8"))


def infer_method_name(paper: dict) -> str:
    methods = paper.get("method_names") or []
    for candidate in methods:
        candidate = str(candidate).strip()
        if candidate:
            return candidate
    title = str(paper.get("title", "")).strip()
    return title.split(":", 1)[0].strip() if ":" in title else title[:80]


def short(text: str, n: int) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    return text[:n] + ("..." if len(text) > n else "")


def build_note_markdown(paper: dict) -> str:
    method_name = infer_method_name(paper)
    title = str(paper.get("title", ""))
    url = str(paper.get("url", ""))
    figure_url = str(paper.get("figure_url", "")).strip()
    section_headers = paper.get("section_headers") or []
    captions = paper.get("captions") or []

    lines = [
        f"# {method_name}",
        "",
        f"- **标题**: {title}",
        f"- **链接**: {url}",
        f"- **作者**: {short(str(paper.get('authors', '')), 300)}",
        f"- **机构**: {short(str(paper.get('affiliations', '')), 300)}",
        f"- **来源**: {paper.get('source', '')}",
        f"- **评分**: {paper.get('score', '')}",
        "",
        "## 核心问题",
        short(str(paper.get("abstract", "")), 800),
        "",
        "## 方法概览",
        short(str(paper.get("method_summary", "")) or str(paper.get("abstract", "")), 1000),
        "",
        "## 关键点",
    ]

    for header in section_headers[:8]:
        lines.append(f"- {header}")

    lines.extend(["", "## 图示线索"])
    if figure_url:
        lines.extend([f"![main figure]({figure_url})", ""])
    if captions:
        for cap in captions[:6]:
            lines.append(f"- {cap}")
    else:
        lines.append("- 当前元数据未抽到稳定 caption，可后续深读时补。")

    lines.extend(
        [
            "",
            "## 适合怎么读",
            "- 先看它和世界模型 / VLA / 机器人策略的接口设计。",
            "- 再看实验是否真的覆盖长时序、真实机器人或关键子任务。",
            "- 如果你要做后续 related work，这篇更适合作为方法接口或系统设计参考。",
            "",
            "## 备注",
            "- 本轮笔记基于当前抓取到的 arXiv 元数据与 HTML 线索自动整理。",
            "- 如果后面装好 Poppler，可以继续补公式、更多图片与表格。",
            "",
        ]
    )
    return "\n".join(lines)


def lark_command(*args: str, cwd: Path | None = None) -> dict:
    cmd = [
        "powershell",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(Path(lark_cli_path().split('"')[-2])) if " -File " in lark_cli_path() else lark_cli_path(),
        *args,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", cwd=str(cwd) if cwd else None)
    if result.returncode != 0:
        raise RuntimeError(result.stdout or result.stderr)
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(result.stdout or result.stderr) from exc


def create_doc_with_fallback(title: str, markdown_file: Path) -> dict:
    targets = []
    configured_space = wiki_space_id().strip()
    if configured_space:
        targets.append(("wiki-space", configured_space))
    targets.append(("wiki-space", "my_library"))

    last_error: RuntimeError | None = None
    for flag, value in targets:
        try:
            return lark_command(
                "docs",
                "+create",
                f"--{flag}",
                value,
                "--title",
                title,
                "--markdown",
                "placeholder",
                cwd=markdown_file.parent,
            )
        except RuntimeError as exc:
            last_error = exc
            text = str(exc)
            if "permission denied" not in text.lower():
                raise

    assert last_error is not None
    raise last_error


def extract_doc_fields(response: dict) -> tuple[str, str]:
    data = response.get("data")
    if not isinstance(data, dict):
        raise RuntimeError(json.dumps(response, ensure_ascii=False))

    if data.get("status") == "running" and data.get("task_id"):
        raise RuntimeError(json.dumps(response, ensure_ascii=False))

    doc_id = data.get("doc_id") or data.get("document_id") or data.get("doc_token")
    doc_url = data.get("doc_url") or data.get("url")
    if not doc_id or not doc_url:
        raise RuntimeError(json.dumps(response, ensure_ascii=False))
    return str(doc_id), str(doc_url)


def load_notes_index() -> list[dict]:
    path = notes_index_file_path()
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))


def save_notes_index(index: list[dict]) -> None:
    notes_index_file_path().write_text(json.dumps(index, ensure_ascii=False, indent=2), encoding="utf-8")


def update_review_doc(meta: dict, notes_index: list[dict]) -> None:
    review_path = Path(meta["review_markdown_path"])
    text = review_path.read_text(encoding="utf-8")
    for item in notes_index:
        title = item["paper_title"]
        pattern = rf"(### \d+\. {re.escape(title)}\n(?:.*\n)*?- \*\*链接\*\*: .*\n)"
        repl = rf"\1- 📒 **笔记**: [{item['method_name']}]({item['doc_url']})\n"
        if f"[{item['method_name']}]({item['doc_url']})" in text:
            continue
        text = re.sub(pattern, repl, text, count=1)

    review_path.write_text(text, encoding="utf-8")
    lark_command(
        "docs",
        "+update",
        "--doc",
        meta["doc_token"],
        "--mode",
        "overwrite",
        "--markdown",
        f"@{review_path.name}",
        cwd=review_path.parent,
    )


def send_message(doc_url: str) -> None:
    user_id = push_user_open_id().strip()
    if not user_id:
        return
    try:
        lark_command(
            "im",
            "+messages-send",
            "--as",
            "user",
            "--user-id",
            user_id,
            "--text",
            f"重点论文笔记已生成\n{doc_url}",
        )
    except RuntimeError:
        return


def main() -> None:
    meta = load_json(latest_review_meta_path())
    enriched = load_json(temp_file_path("daily_papers_enriched.json"))
    must_titles = set(meta.get("must_read_titles", []))
    selected = [paper for paper in enriched if paper.get("title") in must_titles]

    notes_index = load_notes_index()
    known = {item["method_name"].lower(): item for item in notes_index if "method_name" in item}

    created: list[dict] = []
    for paper in selected:
        method_name = infer_method_name(paper)
        if method_name.lower() in known:
            created.append(known[method_name.lower()])
            continue

        note_md = build_note_markdown(paper)
        note_path = temp_file_path(f"{re.sub(r'[^A-Za-z0-9._-]+', '_', method_name)}.md")
        note_path.write_text(note_md, encoding="utf-8")
        created_doc = create_doc_with_fallback(method_name, note_path)
        doc_id, doc_url = extract_doc_fields(created_doc)
        item = {
            "method_name": method_name,
            "paper_title": paper["title"],
            "doc_token": doc_id,
            "doc_url": doc_url,
            "updated_at": datetime.now().strftime("%Y-%m-%d"),
        }
        notes_index.append(item)
        created.append(item)

    save_notes_index(notes_index)
    update_review_doc(meta, created)
    if created:
        send_message(meta["doc_url"])

    print(json.dumps({"created_count": len(created), "review_url": meta["doc_url"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
