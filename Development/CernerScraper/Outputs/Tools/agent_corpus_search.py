"""
Agent-oriented search for the full MPages corpus.

This is a general investigation tool for the entire corpus, separate from the
interactive `search_knowledge.py` script.

Examples:
    python Outputs/Tools/agent_corpus_search.py --query "XMLCCLRequest timeout" --format text
    python Outputs/Tools/agent_corpus_search.py --query "MPAGES_EVENT orders" --mode hybrid
    python Outputs/Tools/agent_corpus_search.py --query "POWERPLANFLEX" --mode exact --platform forum
    python Outputs/Tools/agent_corpus_search.py --query "EKS_ALERT.*SIGNORDER" --mode regex
    python Outputs/Tools/agent_corpus_search.py --query "patient source synonym" --mode overlap
    python Outputs/Tools/agent_corpus_search.py --expand-doc-id forum_223440 --format text
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]
CORPUS_DIR = BASE_DIR / "Outputs" / "Corpus"
DOCUMENTS_JSONL = CORPUS_DIR / "mpages_documents.jsonl"
CHUNKS_JSONL = CORPUS_DIR / "mpages_chunks.jsonl"

DOC_FIELDS = (
    ("title", 4.0, lambda r: r.get("title_clean") or r.get("title") or ""),
    ("group_name", 2.0, lambda r: r.get("group_name") or ""),
    ("platform", 1.0, lambda r: r.get("platform") or ""),
    ("product_area", 1.5, lambda r: r.get("product_area") or ""),
    ("integration_pattern", 1.5, lambda r: r.get("integration_pattern") or ""),
    ("output_pattern", 1.25, lambda r: r.get("output_pattern") or ""),
    ("runtime_context", 1.25, lambda r: r.get("runtime_context") or ""),
    ("search_terms", 1.75, lambda r: r.get("search_terms") or []),
    ("exact_terms", 2.25, lambda r: r.get("exact_terms") or []),
    ("topic_tags", 1.5, lambda r: r.get("topic_tags") or []),
    ("linked_wiki_titles", 1.5, lambda r: r.get("linked_wiki_titles") or []),
    ("body_preview", 1.5, lambda r: r.get("body_preview") or ""),
)

CHUNK_FIELDS = (
    ("title", 3.5, lambda r: r.get("title_clean") or r.get("title") or ""),
    ("group_name", 1.5, lambda r: r.get("group_name") or ""),
    ("section_title", 2.0, lambda r: r.get("section_title") or ""),
    ("speaker", 1.25, lambda r: r.get("speaker") or ""),
    ("product_area", 1.0, lambda r: r.get("product_area") or ""),
    ("integration_pattern", 1.0, lambda r: r.get("integration_pattern") or ""),
    ("artifact_type", 1.0, lambda r: r.get("artifact_type") or ""),
    ("search_terms", 1.75, lambda r: r.get("search_terms") or []),
    ("exact_terms", 2.25, lambda r: r.get("exact_terms") or []),
    ("topic_tags", 1.5, lambda r: r.get("topic_tags") or []),
    ("linked_wiki_titles", 1.5, lambda r: r.get("linked_wiki_titles") or []),
    ("body", 1.0, lambda r: r.get("body") or ""),
)


def load_jsonl(path: Path) -> list[dict]:
    records: list[dict] = []
    with open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if line:
                records.append(json.loads(line))
    return records


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", (text or "").strip().lower())


def words(text: str) -> list[str]:
    return re.findall(r"[a-z0-9_]+", norm(text))


def tokens(text: str) -> list[str]:
    parts = words(text)
    return parts + [f"{parts[i]} {parts[i + 1]}" for i in range(len(parts) - 1)]


def text_for_field(record: dict, getter) -> str:
    value = getter(record)
    if isinstance(value, list):
        return " ".join(str(item) for item in value if item)
    return str(value or "")


def record_blob(record: dict, field_specs) -> str:
    parts = [record.get("doc_id") or "", record.get("canonical_url") or ""]
    parts.extend(text_for_field(record, getter) for _, _, getter in field_specs)
    return norm(" ".join(part for part in parts if part))


def overlap_score(query_counter: Counter, text: str) -> float:
    bag = Counter(tokens(text))
    if not bag:
        return 0.0
    matched = sum(min(query_counter[token], bag[token]) for token in query_counter if token in bag)
    return matched / (max(len(bag), 4) ** 0.5)


def exact_score(query_text: str, query_terms: set[str], text: str) -> float:
    if not text:
        return 0.0
    if query_text and query_text in norm(text):
        return 8.0
    if query_terms and all(term in norm(text) for term in query_terms):
        return 4.0
    return 0.0


def score_record(record: dict, field_specs, query_counter: Counter, query_text: str, query_terms: set[str], mode: str, pattern) -> float:
    total = 0.0
    for field_name, weight, getter in field_specs:
        text = text_for_field(record, getter)
        if not text:
            continue
        if mode == "regex":
            hits = len(pattern.findall(text))
            total += weight * hits
            continue
        if mode in {"overlap", "hybrid"}:
            total += weight * overlap_score(query_counter, text)
        if mode in {"exact", "hybrid"}:
            total += weight * exact_score(query_text, query_terms, text)
        if mode == "hybrid" and query_text and query_text in norm(text) and field_name in {"title", "section_title"}:
            total += weight * 2.0
    if record.get("is_accepted_answer"):
        if mode == "exact":
            total += 3.0
        elif mode == "regex":
            total += 2.0
        else:
            total += 2.5
    return total


def field_contains(record: dict, field_name: str, needle: str | None) -> bool:
    if not needle:
        return True
    return norm(needle) in norm(str(record.get(field_name) or ""))


def record_matches_filters(record: dict, args, blob: str) -> bool:
    if args.platform and norm(record.get("platform") or "") != norm(args.platform):
        return False
    if args.doc_id and (record.get("doc_id") or "") != args.doc_id:
        return False
    if not field_contains(record, "group_name", args.group):
        return False
    if not field_contains(record, "speaker", args.speaker):
        return False
    if not field_contains(record, "section_title", args.section):
        return False
    if not field_contains(record, "product_area", args.product_area):
        return False
    if not field_contains(record, "integration_pattern", args.integration_pattern):
        return False
    if not field_contains(record, "output_pattern", args.output_pattern):
        return False
    if not field_contains(record, "runtime_context", args.runtime_context):
        return False
    if not field_contains(record, "artifact_type", args.artifact_type):
        return False
    for term in args.exclude or []:
        if norm(term) in blob:
            return False
    for term in args.must or []:
        if norm(term) not in blob:
            return False
    return True


def snippet(text: str, max_chars: int) -> str:
    flat = re.sub(r"\s+", " ", text or "").strip()
    if len(flat) > max_chars:
        return flat[:max_chars].rstrip() + "..."
    return flat


def matched_terms(text: str, query_terms: set[str]) -> list[str]:
    blob = norm(text)
    return sorted(term for term in query_terms if term and term in blob)


def split_sentences(text: str) -> list[str]:
    collapsed = re.sub(r"\s+", " ", text or "").strip()
    if not collapsed:
        return []
    parts = re.split(r"(?<=[.!?])\s+", collapsed)
    return [part.strip() for part in parts if part.strip()]


def evidence_sentences(text: str, query_text: str, query_terms: set[str], limit: int) -> list[str]:
    if not text:
        return []
    sentences = split_sentences(text)
    scored: list[tuple[float, str]] = []
    for sentence in sentences:
        blob = norm(sentence)
        score = 0.0
        if query_text and query_text in blob:
            score += 5.0
        score += sum(1.0 for term in query_terms if term in blob)
        if score > 0:
            scored.append((score, sentence))
    scored.sort(key=lambda item: item[0], reverse=True)
    return [sentence for _, sentence in scored[:limit]]


def build_section_maps(chunks: list[dict]) -> tuple[dict[tuple, dict], dict[str, tuple]]:
    sections: dict[tuple, dict] = {}
    chunk_to_section: dict[str, tuple] = {}
    grouped: dict[tuple, list[dict]] = defaultdict(list)
    for chunk in chunks:
        key = (
            chunk.get("doc_id") or "",
            int(chunk.get("section_index") or 0),
            chunk.get("section_title") or "",
            chunk.get("speaker") or "",
        )
        grouped[key].append(chunk)
        chunk_id = chunk.get("chunk_id")
        if chunk_id:
            chunk_to_section[chunk_id] = key

    for key, records in grouped.items():
        ordered = sorted(records, key=lambda item: int(item.get("chunk_index") or 0))
        body = " ".join((record.get("body") or "").strip() for record in ordered).strip()
        sections[key] = {
            "doc_id": key[0],
            "section_index": key[1],
            "section_title": key[2],
            "speaker": key[3],
            "chunk_ids": [record.get("chunk_id") for record in ordered],
            "chunk_indexes": [record.get("chunk_index") for record in ordered],
            "body": body,
        }
    return sections, chunk_to_section


def expand_document(doc_id: str, documents: list[dict], chunks: list[dict]) -> dict:
    document = next((doc for doc in documents if doc.get("doc_id") == doc_id), None)
    if document is None:
        raise ValueError(f"Document not found: {doc_id}")
    grouped: dict[tuple, list[dict]] = defaultdict(list)
    for chunk in chunks:
        if chunk.get("doc_id") != doc_id:
            continue
        key = (
            int(chunk.get("section_index") or 0),
            chunk.get("section_title") or "",
            chunk.get("speaker") or "",
        )
        grouped[key].append(chunk)
    sections = []
    for key in sorted(grouped):
        records = sorted(grouped[key], key=lambda item: int(item.get("chunk_index") or 0))
        body = " ".join((record.get("body") or "").strip() for record in records).strip()
        sections.append({"section_index": key[0], "section_title": key[1], "speaker": key[2], "body": body})
    return {
        "doc_id": doc_id,
        "title": document.get("title_clean") or document.get("title"),
        "platform": document.get("platform"),
        "group_name": document.get("group_name"),
        "canonical_url": document.get("canonical_url"),
        "section_count": len(sections),
        "sections": sections,
    }


def search(args) -> dict:
    documents = load_jsonl(Path(args.documents_jsonl))
    chunks = load_jsonl(Path(args.chunks_jsonl))
    if args.expand_doc_id:
        return {"document": expand_document(args.expand_doc_id, documents, chunks)}

    if not args.query:
        raise ValueError("--query is required unless --expand-doc-id is used")

    query_text = norm(args.query)
    query_counter = Counter(tokens(args.query))
    query_terms = set(words(args.query))
    if args.mode == "semantic":
        args.mode = "overlap"
    pattern = re.compile(args.query, 0 if args.case_sensitive else re.IGNORECASE) if args.mode == "regex" else None
    document_by_id = {record.get("doc_id") or "": record for record in documents}
    sections_by_key, chunk_to_section = build_section_maps(chunks)

    doc_scores = []
    for idx, record in enumerate(documents):
        blob = record_blob(record, DOC_FIELDS)
        if not record_matches_filters(record, args, blob):
            continue
        score = score_record(record, DOC_FIELDS, query_counter, query_text, query_terms, args.mode, pattern)
        if score > 0:
            doc_scores.append((score, idx))
    doc_scores.sort(key=lambda item: item[0], reverse=True)
    doc_score_map = {documents[idx].get("doc_id") or "": score for score, idx in doc_scores}

    chunks_by_doc: dict[str, list[dict]] = defaultdict(list)
    for chunk in chunks:
        chunks_by_doc[chunk.get("doc_id") or ""].append(chunk)

    chunk_candidates = []
    for chunk in chunks:
        doc_id = chunk.get("doc_id") or ""
        if args.doc_id and doc_id != args.doc_id:
            continue
        blob = record_blob(chunk, CHUNK_FIELDS)
        if not record_matches_filters(chunk, args, blob):
            continue
        chunk_score = score_record(chunk, CHUNK_FIELDS, query_counter, query_text, query_terms, args.mode, pattern)
        score = chunk_score + (doc_score_map.get(doc_id, 0.0) * 0.35)
        if score <= 0:
            continue
        chunk_candidates.append((score, chunk_score, chunk))

    chunk_candidates.sort(key=lambda item: item[0], reverse=True)

    results = []
    seen_doc_ids: set[str] = set()
    for score, chunk_score, chunk in chunk_candidates:
        doc_id = chunk.get("doc_id") or ""
        if args.scope == "doc" and doc_id in seen_doc_ids:
            continue
        seen_doc_ids.add(doc_id)
        related = []
        if args.neighbors > 0:
            doc_chunks = sorted(chunks_by_doc[doc_id], key=lambda item: int(item.get("chunk_index") or 0))
            pos = next((i for i, item in enumerate(doc_chunks) if item.get("chunk_id") == chunk.get("chunk_id")), None)
            if pos is not None:
                start = max(0, pos - args.neighbors)
                end = min(len(doc_chunks), pos + args.neighbors + 1)
                for idx in range(start, end):
                    if idx == pos:
                        continue
                    related.append(
                        {
                            "chunk_id": doc_chunks[idx].get("chunk_id"),
                            "chunk_index": doc_chunks[idx].get("chunk_index"),
                            "section_title": doc_chunks[idx].get("section_title"),
                            "speaker": doc_chunks[idx].get("speaker"),
                            "snippet": snippet(doc_chunks[idx].get("body") or "", args.max_chars // 2),
                        }
                    )
        section_key = chunk_to_section.get(chunk.get("chunk_id") or "")
        section = sections_by_key.get(section_key)
        section_body = (section or {}).get("body") or (chunk.get("body") or "")
        extracted_text = section_body if args.extract == "section" else (chunk.get("body") or "")
        evidence = evidence_sentences(section_body, query_text, query_terms, args.sentences)
        term_hits = matched_terms(section_body, query_terms)
        parent_doc = document_by_id.get(doc_id, {})
        results.append(
            {
                "score": round(score, 6),
                "chunk_score": round(chunk_score, 6),
                "doc_score": round(doc_score_map.get(doc_id, 0.0), 6),
                "doc_id": doc_id,
                "chunk_id": chunk.get("chunk_id"),
                "chunk_index": chunk.get("chunk_index"),
                "total_chunks": chunk.get("total_chunks"),
                "title": chunk.get("title_clean") or chunk.get("title"),
                "platform": chunk.get("platform"),
                "group_name": chunk.get("group_name"),
                "section_title": chunk.get("section_title"),
                "speaker": chunk.get("speaker"),
                "product_area": chunk.get("product_area"),
                "integration_pattern": chunk.get("integration_pattern"),
                "runtime_context": chunk.get("runtime_context"),
                "artifact_type": chunk.get("artifact_type"),
                "is_accepted_answer": bool(chunk.get("is_accepted_answer")),
                "canonical_url": chunk.get("canonical_url"),
                "matched_terms": term_hits,
                "extract_type": args.extract,
                "section_index": (section or {}).get("section_index"),
                "section_chunk_indexes": (section or {}).get("chunk_indexes"),
                "section_text": snippet(extracted_text, args.max_chars),
                "evidence_sentences": evidence,
                "snippet": snippet(chunk.get("body") or "", args.max_chars),
                "document_title": parent_doc.get("title_clean") or parent_doc.get("title"),
                "neighbors": related,
            }
        )
        if len(results) >= args.limit:
            break

    return {
        "query": args.query,
        "mode": args.mode,
        "scope": args.scope,
        "result_count": len(results),
        "results": results,
    }


def format_text(payload: dict) -> str:
    if "document" in payload:
        doc = payload["document"]
        lines = ["=" * 78, f"DOC_ID: {doc['doc_id']}", f"TITLE: {doc['title']}", "=" * 78]
        if doc.get("canonical_url"):
            lines.append(doc["canonical_url"])
        for section in doc.get("sections") or []:
            lines.append("")
            lines.append(f"[{section['section_index']}] {section['section_title']} | {section['speaker']}".rstrip())
            lines.append(section["body"])
        return "\n".join(lines)

    lines = ["=" * 78, f"QUERY: {payload['query']}", f"MODE: {payload['mode']}", "=" * 78]
    for idx, item in enumerate(payload["results"], 1):
        lines.append("")
        lines.append(f"-- {idx}. {item['title']}")
        lines.append(
            f"   score={item['score']} | chunk_score={item.get('chunk_score')} | doc_score={item.get('doc_score')} | "
            f"doc_id={item['doc_id']} | chunk={item['chunk_index']}/{item['total_chunks']}"
        )
        lines.append(f"   [{(item.get('platform') or '?').upper()}] {item.get('group_name') or ''}".rstrip())
        if item.get("section_title"):
            lines.append(f"   section: {item['section_title']}")
        if item.get("speaker"):
            lines.append(f"   speaker: {item['speaker']}")
        if item.get("is_accepted_answer"):
            lines.append("   accepted_answer: true")
        if item.get("matched_terms"):
            lines.append(f"   matched_terms: {', '.join(item['matched_terms'])}")
        if item.get("canonical_url"):
            lines.append(f"   {item['canonical_url']}")
        lines.append("")
        lines.append(item["section_text"] if item.get("extract_type") == "section" else item["snippet"])
        for sentence in item.get("evidence_sentences") or []:
            lines.append("")
            lines.append(f"   evidence: {sentence}")
        for neighbor in item.get("neighbors") or []:
            lines.append("")
            lines.append(
                f"   neighbor chunk {neighbor['chunk_index']}: {neighbor.get('section_title') or ''} {neighbor.get('speaker') or ''}".rstrip()
            )
            lines.append(f"   {neighbor['snippet']}")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="General agent-oriented corpus search")
    parser.add_argument("--query", help="Search query")
    parser.add_argument("--mode", choices=["hybrid", "overlap", "semantic", "exact", "regex"], default="hybrid")
    parser.add_argument("--scope", choices=["doc", "chunk"], default="doc")
    parser.add_argument("--limit", type=int, default=6)
    parser.add_argument("--platform", choices=["wiki", "forum"])
    parser.add_argument("--group")
    parser.add_argument("--speaker")
    parser.add_argument("--section")
    parser.add_argument("--product-area")
    parser.add_argument("--integration-pattern")
    parser.add_argument("--output-pattern")
    parser.add_argument("--runtime-context")
    parser.add_argument("--artifact-type")
    parser.add_argument("--doc-id")
    parser.add_argument("--must", action="append")
    parser.add_argument("--exclude", action="append")
    parser.add_argument("--neighbors", type=int, default=0)
    parser.add_argument("--max-chars", type=int, default=500)
    parser.add_argument("--extract", choices=["chunk", "section"], default="section")
    parser.add_argument("--sentences", type=int, default=3)
    parser.add_argument("--expand-doc-id")
    parser.add_argument("--case-sensitive", action="store_true")
    parser.add_argument("--format", choices=["json", "text"], default="json")
    parser.add_argument("--documents-jsonl", default=str(DOCUMENTS_JSONL))
    parser.add_argument("--chunks-jsonl", default=str(CHUNKS_JSONL))
    args = parser.parse_args()
    args.limit = max(1, min(args.limit, 50))
    return args


def main() -> None:
    args = parse_args()
    try:
        payload = search(args)
    except Exception as exc:
        print(json.dumps({"error": str(exc)}, indent=2))
        sys.exit(1)
    if args.format == "text":
        print(format_text(payload))
    else:
        print(json.dumps(payload, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
