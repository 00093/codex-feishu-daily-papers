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
    history_file_path,
    latest_review_meta_path,
    lark_cli_path,
    notes_index_file_path,
    push_chat_id,
    push_user_open_id,
    temp_file_path,
    wiki_space_id,
    wenxian_node_token,
)


MUST_READ_KEYWORDS = [
    "world model",
    "world action model",
    "vla",
    "vision-language-action",
    "robotic world model",
    "robot policy",
]


def load_enriched(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))


def paper_text(paper: dict) -> str:
    return f"{paper.get('title', '')} {paper.get('abstract', '')}".lower()


def infer_method_name(paper: dict) -> str:
    methods = paper.get("method_names") or []
    for candidate in methods:
        candidate = str(candidate).strip()
        if not candidate:
            continue
        if re.fullmatch(r"[A-Z0-9][A-Za-z0-9\-]{1,24}", candidate):
            return candidate
    title = str(paper.get("title", "")).strip()
    if ":" in title:
        return title.split(":", 1)[0].strip()
    return title[:80]


def classify_papers(papers: list[dict]) -> tuple[list[dict], list[dict], list[dict]]:
    must_read: list[dict] = []
    worth: list[dict] = []
    skip: list[dict] = []

    for paper in papers:
        score = int(paper.get("score", 0) or 0)
        text = paper_text(paper)
        title = str(paper.get("title", ""))
        has_anchor = any(keyword in text for keyword in MUST_READ_KEYWORDS)
        high_signal = score >= 10 or (
            score >= 8 and (
                "real robot" in text
                or "manipulation" in text
                or "planning" in text
                or "dexterous" in text
            )
        )

        if has_anchor and high_signal:
            must_read.append(paper)
        elif score >= 7 or has_anchor:
            worth.append(paper)
        else:
            skip.append(paper)

    must_read = must_read[:6]
    worth = [p for p in worth if p not in must_read]
    return must_read, worth, skip


def short_affiliations(paper: dict) -> str:
    text = str(paper.get("affiliations", "")).strip()
    return text[:180] + ("..." if len(text) > 180 else "")


def short_summary(paper: dict, length: int = 220) -> str:
    summary = str(paper.get("method_summary", "")).strip()
    if not summary:
        summary = str(paper.get("abstract", "")).strip()
    summary = re.sub(r"\s+", " ", summary)
    return summary[:length] + ("..." if len(summary) > length else "")


def recommendation_line(paper: dict, bucket: str) -> str:
    title = str(paper.get("title", ""))
    score = int(paper.get("score", 0) or 0)
    text = paper_text(paper)

    if bucket == "must":
        if "world action model" in text or "world model" in text:
            return "更像能直接影响机器人策略设计的世界模型线，值得优先跟。"
        if "vla" in text or "vision-language-action" in text:
            return "和 VLA 主线贴得很近，而且不是空泛叙事，值得优先读。"
        return "和具身 / 机器人主线贴得紧，信息密度高，值得优先读。"

    if bucket == "worth":
        if "real robot" in text:
            return "有真实机器人或强工程味，适合按需求补读。"
        if "navigation" in text or "planning" in text:
            return "偏子方向增强，不一定是今天最核心，但对主线有补充。"
        return "方向相关，适合放进候补池，不必第一时间开读。"

    return "相关但优先级不高，今天先不占用主阅读时间。"


def render_bucket(name: str, papers: list[dict], bucket: str) -> str:
    lines = [f"## {name}", ""]
    if not papers:
        lines.extend(["- 暂无", ""])
        return "\n".join(lines)

    for i, paper in enumerate(papers, 1):
        title = str(paper.get("title", ""))
        method_name = infer_method_name(paper)
        authors = str(paper.get("authors", "")).strip()
        url = str(paper.get("url", "")).strip()
        source = str(paper.get("source", "")).strip()
        upvotes = paper.get("hf_upvotes", "")
        score = int(paper.get("score", 0) or 0)

        lines.extend(
            [
                f"### {i}. {title}",
                f"- **方法名**: {method_name}",
                f"- **来源**: {source}" + (f" / HF upvotes: {upvotes}" if upvotes != "" else ""),
                f"- **分数**: {score}",
                f"- **作者**: {authors[:220]}",
                f"- **机构**: {short_affiliations(paper)}",
                f"- **链接**: {url}",
                f"- **一句话**: {short_summary(paper)}",
                f"- **建议**: {recommendation_line(paper, bucket)}",
                "",
            ]
        )

    return "\n".join(lines)


def build_review_markdown(
    date_str: str,
    days: int,
    must_read: list[dict],
    worth: list[dict],
    skip: list[dict],
) -> str:
    intro = (
        f"# {date_str} 论文点评\n\n"
        f"本次窗口：最近 {days} 天。\n\n"
        "今天这批更值得看的主线还是机器人世界模型、VLA 与具身策略结合。"
        " 纯泛 RL、纯视觉生成、偏离机器人语境的工作我已经尽量压到后面。"
    )

    summary = (
        "## 总览\n\n"
        f"- 必读：{len(must_read)} 篇\n"
        f"- 值得看：{len(worth)} 篇\n"
        f"- 可跳过：{len(skip)} 篇\n"
    )

    return "\n\n".join(
        [
            intro,
            summary,
            render_bucket("🔥 必读", must_read, "must"),
            render_bucket("👀 值得看", worth, "worth"),
            render_bucket("🫳 可跳过", skip, "skip"),
        ]
    ).strip() + "\n"


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
                f"@{markdown_file.name}",
                cwd=markdown_file.parent,
            )
        except RuntimeError as exc:
            last_error = exc
            text = str(exc)
            if "permission denied" not in text.lower():
                raise

    assert last_error is not None
    raise last_error


def update_history(enriched_path: Path, date_str: str) -> None:
    script = Path(__file__).resolve().parents[1] / "skills" / "daily-papers-review" / "update_history.py"
    python_exe = Path(__file__).resolve().parents[1] / ".tools" / "python" / "python.exe"
    subprocess.run(
        [str(python_exe), str(script), "--from-enriched", str(enriched_path), "--date", date_str],
        check=True,
        capture_output=True,
        text=True,
        encoding="utf-8",
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
            f"今日论文点评已生成\n{doc_url}",
        )
    except RuntimeError:
        # Message delivery is a nice-to-have; do not fail document creation or local state writes.
        return


def main() -> None:
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    enriched_path = temp_file_path("daily_papers_enriched.json")
    papers = load_enriched(enriched_path)
    must_read, worth, skip = classify_papers(papers)

    today = datetime.now().strftime("%Y-%m-%d")
    review_path = temp_file_path("daily_papers_review.md")
    review_md = build_review_markdown(today, days, must_read, worth, skip)
    review_path.write_text(review_md, encoding="utf-8")

    create = create_doc_with_fallback(f"{today}-论文点评", review_path)
    doc_id = create["data"]["doc_id"]
    doc_url = create["data"]["doc_url"]

    latest_review_meta_path().write_text(
        json.dumps(
            {
                "date": today,
                "days": days,
                "doc_token": doc_id,
                "doc_url": doc_url,
                "title": f"{today}-论文点评",
                "must_read_titles": [paper["title"] for paper in must_read],
                "review_markdown_path": str(review_path),
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )

    update_history(enriched_path, today)
    send_message(doc_url)

    print(
        json.dumps(
            {
                "doc_id": doc_id,
                "doc_url": doc_url,
                "must_read_count": len(must_read),
                "worth_count": len(worth),
                "skip_count": len(skip),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
