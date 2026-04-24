# AGENTS.md

## Purpose

This repository builds a searchable local corpus from Oracle Health / Cerner wiki pages and forum discussions.

The corpus is broader than any single topic. Search workflows and tooling should be general-purpose and work across:

- MPages development
- Discern / CCL
- Expert rules
- PowerChart / PowerOrders
- XMLCCLRequest
- UI and payload guidance
- platform and product documentation

## Repository Rules

- Only modify files inside this repository.
- Do not create shadow copies.
- Do not copy files between directories.
- Use minimal patch edits instead of rewriting entire files.
- Confirm file paths before editing.

## Canonical Corpus Files

- `Outputs/Corpus/mpages_documents.jsonl`
- `Outputs/Corpus/mpages_chunks.jsonl`
- `Outputs/Corpus/mpages_manual.jsonl`

The main records for investigation are:

- `mpages_documents.jsonl` for title-level and document-level discovery
- `mpages_chunks.jsonl` for section-level search and evidence extraction

## Search Tools

Human-oriented search:

- `Outputs/Tools/search_knowledge.py`

Agent-oriented search:

- `Outputs/Tools/agent_corpus_search.py`

Use the agent-oriented tool when a task needs structured output, filters, thread expansion, or answer-ready evidence extraction.

## Preferred General Workflow

### 1. Start with agent search

Run from the repo root:

```powershell
python .\Outputs\Tools\agent_corpus_search.py --query "XMLCCLRequest timeout" --format text
python .\Outputs\Tools\agent_corpus_search.py --query "MPAGES_EVENT orders" --mode hybrid
python .\Outputs\Tools\agent_corpus_search.py --query "discern alert flex" --platform forum --format text
```

Use `--mode hybrid` by default. The agent tool searches chunk-level evidence across the whole corpus and is intended to return material that can be cited in answers.

### 2. Narrow with filters

Use filters when the first pass is too broad:

```powershell
python .\Outputs\Tools\agent_corpus_search.py --query "patient list columns" --platform wiki
python .\Outputs\Tools\agent_corpus_search.py --query "signorder" --group "Discern Expert Rules"
python .\Outputs\Tools\agent_corpus_search.py --query "XMLCclRequest" --integration-pattern "xmlcclrequest"
```

Useful filters:

- `--platform`
- `--group`
- `--speaker`
- `--section`
- `--product-area`
- `--integration-pattern`
- `--output-pattern`
- `--runtime-context`
- `--artifact-type`
- `--doc-id`

### 3. Switch modes when needed

Use different modes depending on the investigation:

- `hybrid`: best default for most questions
- `overlap`: wider recall based on weighted token overlap
- `exact`: literal phrase or all-terms matching
- `regex`: pattern matching for template names, event names, code markers, or record members

Examples:

```powershell
python .\Outputs\Tools\agent_corpus_search.py --query "EKS_ALERT_FLEX_A" --mode exact
python .\Outputs\Tools\agent_corpus_search.py --query "EKS_.*_L" --mode regex
python .\Outputs\Tools\agent_corpus_search.py --query "patient source synonym" --mode overlap
```

### 4. Prefer section extraction for answering

For answer generation, keep the default section extraction or specify it explicitly:

```powershell
python .\Outputs\Tools\agent_corpus_search.py --query "MPAGES_EVENT orders" --extract section --format text
python .\Outputs\Tools\agent_corpus_search.py --query "XMLCCLRequest timeout" --extract section --sentences 3
```

The tool returns:

- top matching section text
- matched query terms
- evidence sentences
- source metadata for citation

### 5. Expand a specific document

After finding a relevant `doc_id`, expand the full document:

```powershell
python .\Outputs\Tools\agent_corpus_search.py --expand-doc-id forum_223440 --format text
```

Use this to inspect full threads, accepted answers, and follow-up clarifications.

### 6. Use neighbors for local context

If a result is relevant but incomplete, include surrounding chunks:

```powershell
python .\Outputs\Tools\agent_corpus_search.py --query "orders for signature" --neighbors 1 --format text
```

## Cerner Corpus Search for Source Changes

Use the local Cerner corpus when validating CCL table relationships, query patterns, or Millennium data-model assumptions before changing source queries.

- Corpus path: `Outputs/Corpus`
- Search helper: `Outputs/Tools/agent_corpus_search.py`
- Start broad searches with the helper to identify candidate documents, then use `--expand-doc-id <doc_id>` for the promising `forum_*` or `wiki_*` result. Do not rely on snippets alone as proof.
- Use exact table, column, template, event, or record-member searches for schema-sensitive questions, for example `--query "DCP_FORMS_ACTIVITY_PRSNL" --mode exact --format text`.
- If a document ID is already known, prefer `--expand-doc-id` over searching for the doc ID as a normal query; ranked search can miss the exact document.
- Treat raw `rg` over JSONL as a way to find exact terms and document IDs, not as the primary evidence-reading step because output can be noisy.
- Distinguish terminology carefully. User wording such as `created by`, `performed by`, `saved by`, `signed by`, `updated by`, and `first user` may map to different fields or tables.
- Keep CCL syntax in CCL form. Do not translate examples into SQL `JOIN ... ON` style when updating `.txt`, `.prg`, or CCL query files; use `JOIN ... WHERE ...` patterns unless the existing query uses another valid CCL construct.

Phrase conclusions by evidence strength:

- `supported by corpus` when expanded documents show the table relationship and intended meaning
- `likely but needs Cerner validation` when examples imply the pattern but do not define it
- `not supported` when the corpus only shows a generic pattern such as `UPDT_ID -> PRSNL`

## Query Design Guidance

Search with both business language and technical language.

Good query styles:

- user phrasing: `patient list filter`, `open orders tab`, `sign powerplan`
- technical phrasing: `MPAGES_EVENT`, `XMLCCLRequest`, `SIGNORDER`, `POWERPLANFLEX`
- mixed phrasing: `alert on signorder`, `xmlcclrequest timeout`, `mpage event orders`

When investigating a concept:

1. Search the plain-English phrase.
2. Search likely code or template identifiers.
3. Search adjacent workflow states or synonyms.
4. Expand the strongest matching documents before concluding.

## Output Expectations

When summarizing corpus findings:

- cite `doc_id`
- cite title
- cite section title and speaker when relevant
- distinguish the question from the answer
- prefer answer text over title-only inference
- state when the corpus shows a workaround rather than a native feature
- state when evidence is absent rather than assuming impossibility

## Corpus Maintenance

### Cache version discipline

`CernerScraper.py` keeps a `PROCESSING_CACHE_VERSION` constant. Any change to the following must increment that constant so the next run forces a full re-parse:

- Extraction logic (`extract_forum_content`, `extract_wiki_content`, `extract_*_segments`)
- Segmentation or chunking (`build_segments`, `chunk_text`)
- Enrichment rules (`build_enrichment`, `build_document_enrichment`)
- Any field added to or removed from chunk/document records

Bumping the version invalidates all cached parse results, so the next `python CernerScraper.py` re-processes every file.

### QA report

Run before and after any corpus change to measure quality:

```powershell
python .\Outputs\Tools\corpus_qa.py
```

Output: `Outputs/Reports/corpus_qa.md`. Tracks forum-duplication counts, enrichment coverage, platform breakdown, unknown-platform counts, and size outliers.

## Notes

- `search_knowledge.py` remains useful for quick manual lookup.
- `agent_corpus_search.py` is the preferred tool for repeatable agent investigations.
- Avoid adding topic-specific heuristics to this file unless they are clearly reusable across the broader corpus.
