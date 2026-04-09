"""
MPages Knowledge Base Search
Searches the chunk corpus and returns relevant sections.

Usage:
    python Outputs/Tools/search_knowledge.py
    python Outputs/Tools/search_knowledge.py "how do I configure XMLCclRequest timeout"
    python Outputs/Tools/search_knowledge.py --results 10 "MPAGES_EVENT orders"
    python Outputs/Tools/search_knowledge.py --platform wiki "configure patient list columns"
    python Outputs/Tools/search_knowledge.py --rebuild
"""

import argparse
import json
import math
import pickle
import re
import sys
from collections import Counter
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]
JSONL_FILE = BASE_DIR / "Outputs" / "Corpus" / "mpages_chunks.jsonl"
INDEX_FILE = BASE_DIR / "Outputs" / "State" / "search_index.pkl"
DEFAULT_N = 6
MAX_N = 20
BODY_PREVIEW = 600


def load_records(jsonl_path: Path) -> list[dict]:
    records = []
    with open(jsonl_path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def tokenize(text: str) -> list[str]:
    words = re.findall(r"[a-z0-9_]+", (text or "").lower())
    bigrams = [f"{words[idx]} {words[idx + 1]}" for idx in range(len(words) - 1)]
    return words + bigrams


def build_index(records: list[dict]) -> dict:
    doc_terms: list[Counter] = []
    doc_norms: list[float] = []
    doc_freq: Counter = Counter()

    for record in records:
        fields = [
            record.get("title_clean") or record.get("title") or "",
            record.get("group_name") or "",
            record.get("section_title") or "",
            record.get("speaker") or "",
            record.get("body") or "",
        ]
        tokens = tokenize(" ".join(fields))
        term_counts = Counter(tokens)
        doc_terms.append(term_counts)
        doc_freq.update(term_counts.keys())

    total_docs = max(len(records), 1)
    idf = {
        term: math.log((1 + total_docs) / (1 + freq)) + 1.0
        for term, freq in doc_freq.items()
    }

    for term_counts in doc_terms:
        norm = math.sqrt(sum((count * idf.get(term, 0.0)) ** 2 for term, count in term_counts.items())) or 1.0
        doc_norms.append(norm)

    return {
        "idf": idf,
        "doc_terms": doc_terms,
        "doc_norms": doc_norms,
    }


def get_index(jsonl_path: Path, index_path: Path, force_rebuild: bool = False):
    jsonl_mtime = jsonl_path.stat().st_mtime

    if not force_rebuild and index_path.exists():
        with open(index_path, "rb") as handle:
            cached = pickle.load(handle)
        if cached.get("mtime") == jsonl_mtime:
            print(f"[Index loaded from cache: {len(cached['records'])} chunks]")
            return cached["records"], cached["index"]
        print("[Chunk corpus updated - rebuilding index...]")
    else:
        print("[Building index...]")

    records = load_records(jsonl_path)
    index = build_index(records)
    index_path.parent.mkdir(parents=True, exist_ok=True)
    with open(index_path, "wb") as handle:
        pickle.dump({"mtime": jsonl_mtime, "records": records, "index": index}, handle)

    print(f"[Index built: {len(records)} chunks from {jsonl_path}]")
    return records, index


def search(query: str, records, index: dict, n: int = DEFAULT_N, platform: str | None = None) -> list[tuple[float, dict]]:
    idf = index["idf"]
    doc_terms = index["doc_terms"]
    doc_norms = index["doc_norms"]

    query_terms = Counter(tokenize(query))
    query_norm = math.sqrt(sum((count * idf.get(term, 0.0)) ** 2 for term, count in query_terms.items())) or 1.0

    scores: list[float] = []
    for idx, term_counts in enumerate(doc_terms):
        if platform and records[idx].get("platform", "").lower() != platform.lower():
            scores.append(0.0)
            continue
        dot = 0.0
        for term, q_count in query_terms.items():
            if term in term_counts:
                dot += (q_count * idf.get(term, 0.0)) * (term_counts[term] * idf.get(term, 0.0))
        scores.append(dot / (query_norm * doc_norms[idx]) if dot else 0.0)

    results = []
    seen_docs = set()
    for idx in sorted(range(len(scores)), key=lambda i: scores[i], reverse=True):
        if scores[idx] <= 0:
            break
        doc_id = records[idx].get("doc_id") or records[idx].get("source_file", "")
        if doc_id in seen_docs:
            continue
        seen_docs.add(doc_id)
        results.append((float(scores[idx]), records[idx]))
        if len(results) >= n:
            break
    return results


def clean_body(body: str, max_chars: int = BODY_PREVIEW) -> str:
    text = re.sub(r"\n{3,}", "\n\n", body or "").strip()
    if len(text) > max_chars:
        text = text[:max_chars].rstrip() + "..."
    return text


def format_results(results: list[tuple[float, dict]], query: str) -> str:
    lines = [
        "=" * 70,
        f"QUERY: {query}",
        f"Top {len(results)} results from MPages knowledge base",
        "=" * 70,
    ]

    for rank, (score, record) in enumerate(results, 1):
        title = record.get("title_clean") or record.get("title") or record.get("source_file", "Unknown")
        platform = (record.get("platform") or "?").upper()
        group = record.get("group_name") or ""
        section = record.get("section_title") or ""
        speaker = record.get("speaker") or ""
        url = record.get("canonical_url") or ""
        chunk_info = f"chunk {record.get('chunk_index', '?')}/{record.get('total_chunks', '?')}"
        source_label = f"[{platform}]"
        if group:
            source_label += f" {group}"

        lines.append("")
        lines.append(f"-- {rank}. {title}")
        lines.append(f"   {source_label} | score: {score:.3f} | {chunk_info}")
        if section:
            lines.append(f"   section: {section}")
        if speaker:
            lines.append(f"   speaker: {speaker}")
        if url:
            lines.append(f"   {url}")
        lines.append("")
        lines.append(clean_body(record.get("body", "")))

    lines.append("")
    lines.append("=" * 70)
    lines.append("Paste the relevant sections above along with your question into Codex.")
    lines.append("=" * 70)
    return "\n".join(lines)


def interactive_loop(records, index: dict, n: int, platform: str | None):
    print("\nMPages Knowledge Search (type 'quit' to exit, 'help' for options)")
    print("-" * 50)
    while True:
        try:
            query = input("\nSearch: ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nBye.")
            break

        if not query:
            continue
        if query.lower() in {"quit", "exit", "q"}:
            break
        if query.lower() == "help":
            print("  Commands:")
            print("  :n <number>     change result count")
            print("  :wiki           filter to wiki pages only")
            print("  :forum          filter to forum posts only")
            print("  :all            remove platform filter")
            print("  quit            exit")
            continue
        if query.startswith(":n "):
            try:
                n = max(1, min(MAX_N, int(query[3:])))
                print(f"  Results per query set to {n}")
            except ValueError:
                print("  Usage: :n <number>")
            continue
        if query == ":wiki":
            platform = "wiki"
            print("  Filtering to wiki pages")
            continue
        if query == ":forum":
            platform = "forum"
            print("  Filtering to forum posts")
            continue
        if query == ":all":
            platform = None
            print("  Platform filter cleared")
            continue

        results = search(query, records, index, n=n, platform=platform)
        if not results:
            print("  No results found.")
            continue

        output = format_results(results, query)
        print(output)


def main():
    parser = argparse.ArgumentParser(description="Search MPages knowledge base")
    parser.add_argument("query", nargs="*", help="Search query (omit for interactive mode)")
    parser.add_argument("--results", "-n", type=int, default=DEFAULT_N, help=f"Number of results (default {DEFAULT_N})")
    parser.add_argument("--platform", choices=["wiki", "forum"], help="Filter by platform")
    parser.add_argument("--rebuild", action="store_true", help="Force index rebuild")
    parser.add_argument("--jsonl", default=str(JSONL_FILE), help=f"Path to JSONL (default: {JSONL_FILE})")
    parser.add_argument("--index", default=str(INDEX_FILE), help=f"Path to index cache (default: {INDEX_FILE})")
    args = parser.parse_args()

    jsonl_path = Path(args.jsonl)
    index_path = Path(args.index)

    if not jsonl_path.exists():
        print(f"ERROR: JSONL file not found: {jsonl_path}")
        print("Run CernerScraper.py first or pass --jsonl <path>.")
        sys.exit(1)

    records, index = get_index(jsonl_path, index_path, force_rebuild=args.rebuild)
    n = max(1, min(MAX_N, args.results))
    platform = args.platform

    if args.query:
        query = " ".join(args.query)
        results = search(query, records, index, n=n, platform=platform)
        if not results:
            print("No results found.")
            sys.exit(0)
        print(format_results(results, query))
    else:
        interactive_loop(records, index, n=n, platform=platform)


if __name__ == "__main__":
    main()
