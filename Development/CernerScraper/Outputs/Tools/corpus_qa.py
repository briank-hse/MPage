"""
Corpus QA report.

Reads the current corpus JSONL files and processing cache, then emits a Markdown
report to Outputs/Reports/corpus_qa.md and a summary to stdout.

Run from the repo root:
    python Outputs/Tools/corpus_qa.py
    python Outputs/Tools/corpus_qa.py --output path/to/report.md
"""

import argparse
import json
import re
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]
CORPUS_DIR = BASE_DIR / "Outputs" / "Corpus"
REPORTS_DIR = BASE_DIR / "Outputs" / "Reports"
STATE_DIR = BASE_DIR / "Outputs" / "State"

DOCUMENTS_JSONL = CORPUS_DIR / "mpages_documents.jsonl"
CHUNKS_JSONL = CORPUS_DIR / "mpages_chunks.jsonl"
CACHE_JSON = STATE_DIR / "processing_cache.json"

ENRICHMENT_FIELDS = [
    "product_area",
    "integration_pattern",
    "output_pattern",
    "runtime_context",
    "artifact_type",
    "search_terms",
    "exact_terms",
    "topic_tags",
    "contains_code",
    "code_languages",
]


def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    records = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def is_meaningful(value) -> bool:
    """True when a field value carries real classification (not a default/absent marker)."""
    if value is None or value == "" or value == "unknown" or value is False:
        return False
    if isinstance(value, list) and len(value) == 0:
        return False
    return True


def field_coverage(records: list[dict], fields: list[str]) -> dict:
    total = len(records)
    result = {}
    for field in fields:
        present = sum(1 for r in records if field in r)
        nonempty = sum(1 for r in records if is_meaningful(r.get(field)))
        result[field] = {"present": present, "nonempty": nonempty, "total": total}
    return result


def detect_forum_duplicates(chunks: list[dict]) -> dict:
    """
    Detect forum docs where the original_post body contains comment text.
    Probe: first 25 words of any comment chunk appear verbatim in the
    combined original_post text of the same doc.
    """
    by_doc: dict = defaultdict(lambda: {"op": [], "comments": []})
    for chunk in chunks:
        doc_id = chunk.get("doc_id")
        stype = chunk.get("section_type")
        body = (chunk.get("body") or "").lower()
        if not doc_id or not stype:
            continue
        if stype == "original_post":
            by_doc[doc_id]["op"].append(body)
        elif stype == "comment":
            by_doc[doc_id]["comments"].append(body)

    forum_docs = {k for k, v in by_doc.items() if v["comments"]}
    duplicated: list[str] = []

    for doc_id in forum_docs:
        data = by_doc[doc_id]
        if not data["op"]:
            continue
        combined_op = " ".join(data["op"])
        for comment_body in data["comments"][:5]:
            probe = " ".join(comment_body.split()[:25])
            if len(probe) >= 40 and probe in combined_op:
                duplicated.append(doc_id)
                break

    return {
        "forum_docs_with_comments": len(forum_docs),
        "duplicated_count": len(duplicated),
        "example_doc_ids": duplicated[:5],
    }


def load_cache(path: Path) -> dict:
    if not path.exists():
        return {}
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(raw, dict) and "files" in raw:
            return raw["files"]
        return raw if isinstance(raw, dict) else {}
    except Exception:
        return {}


def run_qa(documents: list[dict], chunks: list[dict], cache_files: dict) -> dict:
    total_docs = len(documents)
    total_chunks = len(chunks)

    doc_platform = Counter(r.get("platform", "unknown") for r in documents)
    chunk_platform = Counter(r.get("platform", "unknown") for r in chunks)

    cache_status: Counter = Counter()
    for entry in cache_files.values():
        if isinstance(entry, dict):
            cache_status[entry.get("status", "unknown")] += 1

    doc_enrichment = field_coverage(documents, ENRICHMENT_FIELDS)
    chunk_enrichment = field_coverage(chunks, ENRICHMENT_FIELDS)

    dup_result = detect_forum_duplicates(chunks)

    unknown_docs = [r for r in documents if r.get("platform") == "unknown"]
    unknown_examples = [
        {
            "title": (r.get("title_clean") or r.get("title") or "")[:80],
            "source_file": r.get("source_file", ""),
            "canonical_url": r.get("canonical_url", ""),
        }
        for r in unknown_docs[:8]
    ]

    error_entries, notext_entries = [], []
    for path, entry in cache_files.items():
        if not isinstance(entry, dict):
            continue
        status = entry.get("status")
        if status == "error":
            error_entries.append(
                {"path": path, "error": (entry.get("error") or "")[:120]}
            )
        elif status == "no_text":
            notext_entries.append({"path": path})

    large_docs = sorted(documents, key=lambda r: r.get("word_count", 0), reverse=True)[:5]
    large_chunks = sorted(chunks, key=lambda r: r.get("word_count", 0), reverse=True)[:5]
    small_chunks = [r for r in chunks if 0 < r.get("word_count", 0) < 20]

    # Chunks with at least one enrichment field meaningful
    enriched_any = sum(
        1 for r in chunks if any(is_meaningful(r.get(f)) for f in ENRICHMENT_FIELDS)
    )

    return {
        "total_docs": total_docs,
        "total_chunks": total_chunks,
        "doc_platform": dict(doc_platform),
        "chunk_platform": dict(chunk_platform),
        "cache_status": dict(cache_status),
        "doc_enrichment": doc_enrichment,
        "chunk_enrichment": chunk_enrichment,
        "forum_duplication": dup_result,
        "unknown_platform_count": len(unknown_docs),
        "unknown_platform_examples": unknown_examples,
        "error_examples": error_entries[:5],
        "notext_examples": notext_entries[:5],
        "enriched_any_chunks": enriched_any,
        "large_docs": [
            {
                "doc_id": r.get("doc_id", ""),
                "title": (r.get("title_clean") or r.get("title", ""))[:70],
                "words": r.get("word_count", 0),
            }
            for r in large_docs
        ],
        "large_chunks": [
            {"chunk_id": r.get("chunk_id", ""), "words": r.get("word_count", 0)}
            for r in large_chunks
        ],
        "small_chunk_count": len(small_chunks),
    }


def render_markdown(qa: dict, timestamp: str) -> str:
    lines: list[str] = []

    def h(level: int, text: str) -> None:
        lines.append("")
        lines.append("#" * level + " " + text)
        lines.append("")

    def row(*cells) -> str:
        return "| " + " | ".join(str(c) for c in cells) + " |"

    lines.append("# Corpus QA Report")
    lines.append("")
    lines.append(f"Generated: {timestamp}")

    h(2, "Overview")
    lines.append(row("Metric", "Count"))
    lines.append(row("---", "---"))
    lines.append(row("Total documents", f"{qa['total_docs']:,}"))
    lines.append(row("Total chunks", f"{qa['total_chunks']:,}"))
    lines.append(
        row(
            "Chunks with any enrichment",
            f"{qa['enriched_any_chunks']:,} ({100*qa['enriched_any_chunks']/max(qa['total_chunks'],1):.1f}%)",
        )
    )

    h(2, "Platform Breakdown")
    lines.append("**Documents:**")
    lines.append("")
    for plat, count in sorted(qa["doc_platform"].items()):
        pct = 100 * count / max(qa["total_docs"], 1)
        lines.append(f"- `{plat}`: {count:,} ({pct:.1f}%)")
    lines.append("")
    lines.append("**Chunks:**")
    lines.append("")
    for plat, count in sorted(qa["chunk_platform"].items()):
        pct = 100 * count / max(qa["total_chunks"], 1)
        lines.append(f"- `{plat}`: {count:,} ({pct:.1f}%)")

    h(2, "Processing Cache Status")
    for status, count in sorted(qa["cache_status"].items()):
        lines.append(f"- `{status}`: {count:,}")

    h(2, "Forum Duplication Check (F1)")
    dup = qa["forum_duplication"]
    severity = "**ISSUE**" if dup["duplicated_count"] > 0 else "OK"
    lines.append(f"- Forum docs with comments: {dup['forum_docs_with_comments']:,}")
    lines.append(
        f"- Likely-duplicated docs: {dup['duplicated_count']:,} — {severity}"
    )
    if dup["example_doc_ids"]:
        lines.append(f"- Examples: {', '.join(dup['example_doc_ids'])}")

    h(2, "Enrichment Field Coverage (F2)")

    for label, enrichment, total in [
        ("Chunks", qa["chunk_enrichment"], qa["total_chunks"]),
        ("Documents", qa["doc_enrichment"], qa["total_docs"]),
    ]:
        h(3, label)
        lines.append(row("Field", "Key Present", "Meaningful Value", "Coverage %"))
        lines.append(row("---", "---", "---", "---"))
        for field, counts in enrichment.items():
            pct = 100 * counts["nonempty"] / max(total, 1)
            flag = "" if pct >= 95 else (" [!]" if pct >= 50 else " [x]")
            lines.append(
                row(
                    f"`{field}`",
                    f"{counts['present']:,}",
                    f"{counts['nonempty']:,}",
                    f"{pct:.1f}%{flag}",
                )
            )

    h(2, "Unknown-Platform Documents")
    lines.append(f"Count: {qa['unknown_platform_count']:,}")
    if qa["unknown_platform_examples"]:
        lines.append("")
        lines.append("Examples:")
        for ex in qa["unknown_platform_examples"]:
            lines.append(
                f"- **{ex['title']}** — `{ex['source_file']}` — `{ex['canonical_url']}`"
            )

    if qa["error_examples"] or qa["notext_examples"]:
        h(2, "Errors / No-text Files")
        if qa["error_examples"]:
            lines.append(f"Error status ({len(qa['error_examples'])} shown):")
            for ex in qa["error_examples"]:
                lines.append(f"- `{Path(ex['path']).name}`: {ex['error']}")
        if qa["notext_examples"]:
            lines.append(f"\nNo-text status ({len(qa['notext_examples'])} shown):")
            for ex in qa["notext_examples"]:
                lines.append(f"- `{Path(ex['path']).name}`")

    h(2, "Size Outliers")
    lines.append("**Largest documents (by word count):**")
    lines.append("")
    for doc in qa["large_docs"]:
        lines.append(f"- `{doc['doc_id']}`: {doc['words']:,} words — {doc['title']}")
    lines.append("")
    lines.append(f"**Small chunks (<20 words)**: {qa['small_chunk_count']:,}")

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Corpus QA report")
    parser.add_argument(
        "--output",
        type=Path,
        default=REPORTS_DIR / "corpus_qa.md",
        help="Path for the output Markdown report",
    )
    args = parser.parse_args()

    documents = load_jsonl(DOCUMENTS_JSONL)
    chunks = load_jsonl(CHUNKS_JSONL)
    cache_files = load_cache(CACHE_JSON)

    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M")
    qa = run_qa(documents, chunks, cache_files)
    md = render_markdown(qa, timestamp)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(md, encoding="utf-8")
    print(f"QA report written to {args.output}")
    print()
    print(f"Documents : {qa['total_docs']:,}")
    print(f"Chunks    : {qa['total_chunks']:,}")
    dup = qa["forum_duplication"]
    print(
        f"Forum dup : {dup['duplicated_count']:,} of {dup['forum_docs_with_comments']:,} forum docs affected"
    )
    total = qa["total_chunks"]
    print(
        f"Enriched  : {qa['enriched_any_chunks']:,} of {total:,} chunks have 1+ meaningful enrichment field"
    )
    print(f"Unknown   : {qa['unknown_platform_count']:,} unknown-platform docs")


if __name__ == "__main__":
    main()
