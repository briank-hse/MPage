"""
MPages Knowledge Scraper & Local Ingestor
Processes manually downloaded .html and .mhtml files from Oracle Health 
community forums and Cerner Wiki pages. Outputs clean JSONL for AI ingestion.

Setup:
    pip install html2text jsonlines beautifulsoup4

Run:
    python CernerScraper.py
"""



import html
import json
import logging
import os
import re
import hashlib
import unicodedata
from pathlib import Path
from urllib.parse import urlparse, unquote, quote

from bs4 import BeautifulSoup, UnicodeDammit
import html2text
import jsonlines

# Config

BASE_DIR = Path(__file__).resolve().parent

LOCAL_DOWNLOADS_DIR = BASE_DIR / "DownloadedFiles"
GROUP_METADATA_DIR = BASE_DIR / "GroupMetadata"   # folder to place Group Search Results HTML files

OUTPUTS_DIR = BASE_DIR / "Outputs"
CORPUS_DIR = OUTPUTS_DIR / "Corpus"
REPORTS_DIR = OUTPUTS_DIR / "Reports"
STATE_DIR = OUTPUTS_DIR / "State"
LOGS_DIR = OUTPUTS_DIR / "Logs"
TOOLS_DIR = OUTPUTS_DIR / "Tools"

ROOT_DOWNLOADED_OUTPUT = BASE_DIR / "Downloaded_Pages.html"
ROOT_MISSING_OUTPUT = BASE_DIR / "Missing_Pages.html"

DOCUMENTS_OUTPUT = CORPUS_DIR / "mpages_documents.jsonl"
CHUNKS_OUTPUT = CORPUS_DIR / "mpages_chunks.jsonl"
LEGACY_OUTPUT = CORPUS_DIR / "mpages_manual.jsonl"
INDEX_FILE = STATE_DIR / "search_index.pkl"
PROCESSING_CACHE_FILE = STATE_DIR / "processing_cache.json"
PROCESSING_CACHE_VERSION = 2  # bump whenever extract_*, build_segments, chunk_text, or enrichment logic changes
MISSING_LINK_HISTORY_FILE = STATE_DIR / "missing_links_history.json"
IGNORED_LINKS_FILE = STATE_DIR / "ignored_links.json"
LOG_FILE = LOGS_DIR / "scraper.log"
MANAGE_MISSING_LINKS_SCRIPT = TOOLS_DIR / "manage_missing_links.py"
SEARCH_KNOWLEDGE_SCRIPT = TOOLS_DIR / "search_knowledge.py"
VENV_PYTHON = BASE_DIR / ".venv" / "Scripts" / "python.exe"

REFERENCE_DOMAINS = {"developer.mozilla.org", "docs.oracle.com", "flashes.cerner.com"}

# Chunking config


def _fs_path(path: str | Path) -> str:
    raw = os.fspath(path)
    if os.name != "nt":
        return raw

    absolute = os.path.abspath(raw)
    if absolute.startswith("\\\\?\\"):
        return absolute
    if absolute.startswith("\\\\"):
        return "\\\\?\\UNC\\" + absolute[2:]
    return "\\\\?\\" + absolute


def _read_text_file(path: str | Path, *, encoding: str = "utf-8", errors: str = "ignore") -> str:
    with open(_fs_path(path), "r", encoding=encoding, errors=errors) as handle:
        return handle.read()


def _read_bytes_file(path: str | Path) -> bytes:
    with open(_fs_path(path), "rb") as handle:
        return handle.read()

CHUNK_SIZE = 400   # target words per chunk
CHUNK_OVERLAP = 40    # overlap words between chunks

# Logging

for _folder in (OUTPUTS_DIR, CORPUS_DIR, REPORTS_DIR, STATE_DIR, LOGS_DIR, TOOLS_DIR):
    _folder.mkdir(parents=True, exist_ok=True)

import sys as _sys
_stream_handler = logging.StreamHandler(_sys.stdout)
try:
    # On Windows, stdout may use cp1252 which cannot encode some Unicode chars.
    _stream_handler.stream = open(
        _sys.stdout.fileno(), mode="w", encoding="utf-8", closefd=False, buffering=1
    )
except Exception:
    pass

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(LOG_FILE, encoding="utf-8"),
        _stream_handler,
    ],
)
log = logging.getLogger(__name__)

def load_group_metadata() -> dict[str, dict]:
    meta_dir = Path(GROUP_METADATA_DIR)
    if not meta_dir.exists():
        return {}

    html_files = list(meta_dir.glob("*.[hH][tT][mM]*"))
    if not html_files:
        return {}

    group_map: dict[str, dict] = {}

    for fpath in html_files:
        try:
            html = _read_text_file(fpath, encoding="utf-8", errors="ignore")
            soup = BeautifulSoup(html, "html.parser")
            all_links = [
                (a.get_text(strip=True), a["href"])
                for a in soup.find_all("a", href=True)
                if a.get_text(strip=True)
            ]
            current_group_name: str | None = None
            current_group_url:  str | None = None
            for text, href in all_links:
                if href.startswith("/"):
                    href = "https://community.oracle.com" + href
                if (re.search(r"/oraclehealth/group/\d", href) and
                        not any(x in href for x in ("/join/", "/leave/", "/browse/"))):
                    current_group_name = text
                    current_group_url  = href
                elif re.search(r"/oraclehealth/discussion/\d+", href):
                    disc_url = re.sub(r"#.*$", "", href)
                    if current_group_name and disc_url not in group_map:
                        gid_m = re.search(r"/group/(\d+)-", current_group_url or "")
                        group_map[disc_url] = {
                            "group_name": current_group_name,
                            "group_id":   gid_m.group(1) if gid_m else None,
                            "group_url":  current_group_url,
                        }
        except Exception as exc:
            log.warning("load_group_metadata: could not parse %s: %s", fpath.name, exc)

    log.info("Group metadata: %d discussion->group mappings from %d file(s)", len(group_map), len(html_files))
    return group_map

GROUP_METADATA: dict[str, dict] = {}

# ── html2text ─────────────────────────────────────────────────────────────────



h2t = html2text.HTML2Text()
h2t.ignore_links = True
h2t.ignore_images = True
h2t.body_width = 0

_CODE_TAG_RE = re.compile(r"<(?:pre|code)\b", re.IGNORECASE)
_CCL_LANG_RE = re.compile(
    r"\b(?:subroutine|define\s+script|;go\b|mpages_event|mpages_svc|ccllink|"
    r"cclnewsessionwindow|xmlcclrequest|record\s+\w+\s*\()",
    re.IGNORECASE,
)
_SQL_LANG_RE = re.compile(
    r"\b(?:select\s+[\w\*\(]|from\s+\w|group\s+by\b|order\s+by\b|inner\s+join\b|left\s+join\b)",
    re.IGNORECASE,
)
_JS_LANG_RE = re.compile(
    r"(?:function\s*[\w(]|(?:var|let|const)\s+\w|document\.\w|window\.\w|"
    r"\.innerHTML\b|=>\s*[{(]|\$\s*\()",
)
_HTML_LANG_RE = re.compile(r"<(?:html|body|div|span|table|tr|td|form|input)\b", re.IGNORECASE)
_CSS_LANG_RE = re.compile(
    r"(?:font-size\s*:|margin\s*:|padding\s*:|display\s*:|background(?:-color)?\s*:|border\s*:)",
    re.IGNORECASE,
)


def detect_code_info(html_fragment: str) -> tuple[bool, list[str]]:
    """Inspect raw HTML for <pre>/<code> blocks before text conversion.

    Returns (contains_code, code_languages).  Must be called on the HTML,
    not on the already-converted text, because html2text removes the tag markers.
    """
    if not html_fragment or not _CODE_TAG_RE.search(html_fragment):
        return False, []
    code_soup = BeautifulSoup(html_fragment, "html.parser")
    blocks = code_soup.find_all(["pre", "code"])
    if not blocks:
        return False, []
    combined = "\n".join(el.get_text() for el in blocks)
    langs: list[str] = []
    if _CCL_LANG_RE.search(combined):
        langs.append("ccl")
    if _SQL_LANG_RE.search(combined) and "ccl" not in langs:
        langs.append("sql")
    if _JS_LANG_RE.search(combined):
        langs.append("javascript")
    if _HTML_LANG_RE.search(combined):
        langs.append("html")
    if _CSS_LANG_RE.search(combined):
        langs.append("css")
    if len(langs) > 1:
        langs = ["mixed"]
    return True, langs


def _maybe_fix_mojibake(text: str) -> str:
    if not text:
        return ""
    if "\u00c2" not in text and "\u00e2" not in text:
        return text
    try:
        repaired = text.encode("latin-1", errors="ignore").decode("utf-8", errors="ignore")
    except UnicodeError:
        return text
    old_noise = text.count("\u00c2") + text.count("\u00e2")
    new_noise = repaired.count("\u00c2") + repaired.count("\u00e2")
    return repaired if new_noise < old_noise else text


def normalize_text(text: str) -> str:
    if not text:
        return ""
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = _maybe_fix_mojibake(text)
    text = unicodedata.normalize("NFKC", text)
    for old, new in (("\u00a0", " "), ("\u200b", ""), ("\u200c", ""), ("\u200d", ""), ("\ufeff", "")):
        text = text.replace(old, new)
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def preview_text(text: str, max_chars: int = 320) -> str:
    text = normalize_text(text)
    if len(text) <= max_chars:
        return text
    return text[:max_chars].rstrip() + "..."


def clean_title(title: str) -> str:
    title = normalize_text(title)
    return re.sub(
        r"\s*[-\u2013\u2014]+\s*(?:Help Pages\s*[-\u2013\u2014]+\s*)?"
        r"(?:MPages Development Wiki|Reference Pages|Bedrock Help Pages|Discern Help Pages|"
        r"CernerWorks Reference Pages|Cerner Wiki|Oracle Health)"
        r"(?:\s*[-\u2013\u2014]+\s*Cerner Wiki)?\s*$",
        "",
        title,
        flags=re.IGNORECASE,
    ).strip() or title


def normalize_url(url: str) -> str:
    if not url:
        return ""
    url = re.sub(r"[#?].*$", "", url).rstrip("/")
    url = re.sub(r"^http://", "https://", url, flags=re.IGNORECASE)
    url = re.sub(
        r"^https://wiki\.cerner\.com/display/public/",
        "https://wiki.cerner.com/display/",
        url,
        flags=re.IGNORECASE,
    )
    return url


def build_doc_id(platform: str, canonical_url: str, fallback_hash: str) -> str:
    canonical_url = normalize_url(canonical_url)
    if platform == "forum":
        match = re.search(r"/discussion/(\d+)", canonical_url)
        if match:
            return f"forum_{match.group(1)}"
    if canonical_url:
        digest = hashlib.md5(canonical_url.encode("utf-8")).hexdigest()[:16]
        return f"{platform or 'doc'}_{digest}"
    return f"file_{fallback_hash[:16]}"


def build_chunk_id(doc_id: str, chunk_index: int) -> str:
    return f"{doc_id}_chunk_{chunk_index:04d}"


def html_to_text(html: str) -> str:
    return normalize_text(h2t.handle(html or ""))


def detect_platform(canonical_url: str, source_name: str, html_hint: str = "") -> str:
    canonical_url = (canonical_url or "").lower()
    source_name = (source_name or "").lower()
    html_hint = (html_hint or "").lower()

    if any(host in canonical_url for host in ["wiki.cerner.com", "mpages-dev-docs.cerner.com", "pages.github.cerner.com", "mpages-fusion.cerner.com"]):
        return "wiki"
    if "community.oracle.com" in canonical_url:
        return "forum"
    if (
        "cerner wiki" in source_name
        or ("wiki" in source_name and "oracle" not in source_name)
        or "custom mpages development" in source_name
    ):
        return "wiki"
    if "oracle health" in source_name or "oraclehealth" in html_hint:
        return "forum"
    return "unknown"


def chunk_text(text: str, chunk_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    paragraphs = [p.strip() for p in re.split(r"\n{2,}", normalize_text(text)) if p.strip()]
    chunks, current, current_len = [], [], 0

    for para in paragraphs:
        para_words = len(para.split())

        if para_words > chunk_size:
            if current:
                chunks.append("\n\n".join(current))
                current, current_len = [], 0
            sentences = [s.strip() for s in re.split(r"(?<=[.!?])\s+|\n", para) if s.strip()]
            sub, sub_len = [], 0
            for sent in sentences:
                sw = len(sent.split())
                if sub_len + sw > chunk_size and sub:
                    chunks.append(" ".join(sub))
                    sub, sub_len = [], 0
                sub.append(sent)
                sub_len += sw
            if sub:
                chunks.append(" ".join(sub))
            continue

        if current_len + para_words > chunk_size and current:
            chunks.append("\n\n".join(current))
            while current and current_len - len(current[0].split()) >= overlap:
                current_len -= len(current[0].split())
                current.pop(0)

        current.append(para)
        current_len += para_words

    if current:
        chunks.append("\n\n".join(current))

    return chunks


def decode_html_bytes(raw: bytes) -> str:
    try:
        raw = UnicodeDammit.detwingle(raw)
    except Exception:
        pass
    dammit = UnicodeDammit(raw, is_html=True)
    text = dammit.unicode_markup or raw.decode("utf-8", errors="replace")
    return normalize_text(text)


def read_html_from_file(path: str) -> str:
    raw = _read_bytes_file(path)
    if path.lower().endswith(".mhtml"):
        import email as _email
        msg = _email.message_from_bytes(raw)
        for part in msg.walk():
            if part.get_content_type() == "text/html":
                payload = part.get_payload(decode=True) or b""
                html = decode_html_bytes(payload)
                break
        else:
            raise ValueError(f"No HTML part found in {path}")
    else:
        html = decode_html_bytes(raw)
    html = re.sub(r' src="data:[^"]{100,}"', ' src=""', html)
    html = re.sub(r" src='data:[^']{100,}'", " src=''", html)
    html = re.sub(r"url\(data:[^)]{100,}\)", "url()", html)
    return html


def write_jsonl(path: Path, records: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with jsonlines.open(path, mode="w") as writer:
        for record in records:
            writer.write(record)


def load_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with jsonlines.open(path) as reader:
        return list(reader)



def load_processing_cache() -> dict[str, dict]:
    if not PROCESSING_CACHE_FILE.exists():
        return {}
    try:
        loaded = json.loads(PROCESSING_CACHE_FILE.read_text(encoding="utf-8"))
    except Exception as exc:
        log.warning("Could not read %s: %s", PROCESSING_CACHE_FILE.name, exc)
        return {}

    if not isinstance(loaded, dict):
        return {}

    if "files" in loaded:
        if loaded.get("version") != PROCESSING_CACHE_VERSION or not isinstance(loaded.get("files"), dict):
            return {}
        raw_files = loaded["files"]
    else:
        raw_files = loaded

    return {
        str(source_path): payload
        for source_path, payload in raw_files.items()
        if isinstance(source_path, str) and isinstance(payload, dict)
    }


def save_processing_cache(cache: dict[str, dict]) -> None:
    payload = {
        "version": PROCESSING_CACHE_VERSION,
        "files": {source_path: cache[source_path] for source_path in sorted(cache)},
    }
    PROCESSING_CACHE_FILE.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def build_source_record_maps(documents: list[dict], chunks: list[dict]) -> tuple[dict[str, dict], dict[str, list[dict]]]:
    docs_by_source: dict[str, dict] = {}
    chunks_by_source: dict[str, list[dict]] = {}

    for document in documents:
        source_path = document.get("source_path") or document.get("source_file")
        if source_path:
            docs_by_source[str(source_path)] = document

    for chunk in chunks:
        source_path = chunk.get("source_path") or chunk.get("source_file")
        if not source_path:
            continue
        key = str(source_path)
        chunks_by_source.setdefault(key, []).append(chunk)

    for source_path, records in chunks_by_source.items():
        records.sort(key=lambda record: int(record.get("chunk_index", 0)))

    return docs_by_source, chunks_by_source

def load_ignored_links() -> dict[str, dict]:
    if not IGNORED_LINKS_FILE.exists():
        return {}
    try:
        loaded = json.loads(IGNORED_LINKS_FILE.read_text(encoding="utf-8"))
    except Exception as exc:
        log.warning("Could not read %s: %s", IGNORED_LINKS_FILE.name, exc)
        return {}

    if not isinstance(loaded, dict):
        return {}

    ignored: dict[str, dict] = {}
    for raw_url, meta in loaded.items():
        url = normalize_url(str(raw_url))
        if not url:
            continue
        payload = meta if isinstance(meta, dict) else {"url": url}
        payload["url"] = url
        ignored[url] = payload
    return ignored


def save_ignored_links(ignored: dict[str, dict]) -> None:
    payload = {url: meta for url, meta in sorted(ignored.items())}
    IGNORED_LINKS_FILE.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")

def extract_links(html_or_text: str) -> dict:
    result = {"forum": [], "wiki": [], "reference": []}

    abs_urls = set(re.findall(r'https?://[^\s\)\]"\'<>]+', html_or_text))
    for url in abs_urls:
        clean = re.sub(r'[#?].*$', '', url).rstrip('/')
        if "dismissannouncement" in clean.lower(): continue
        try: domain = urlparse(clean).netloc
        except ValueError: continue

        if "community.oracle.com" in domain and re.search(r'/oraclehealth/discussion/\d+', clean):
            result["forum"].append(clean)
        elif "wiki.cerner.com" in domain and ("/display/" in clean or "/x/" in clean):
            result["wiki"].append(clean)
        elif any(d in domain for d in REFERENCE_DOMAINS):
            result["reference"].append(url)

    rel_wiki = set(re.findall(r'href=["\'](?:https://wiki\.cerner\.com)?(/(?:display|x)/[^"\'#?\s]+)', html_or_text))
    for path in rel_wiki:
        full = f"https://wiki.cerner.com{path}"
        result["wiki"].append(full)

    for k in result:
        result[k] = list(dict.fromkeys(result[k]))
    return result

# ── Platform-specific content extractors ─────────────────────────────────────

FORUM_NOISE_CLASSES = [
    "pageHeadingBox", "CommentForm", "writeComment", "FormWrapper", "LeaveCommentTitle",
    "Reactions", "ReactButton", "FlagMenu", "Flags", "Flyout", "InlineTags",
    "Pager", "selectLocale", "NewDiscussion", "AuthorMenu", "Item-Footer",
    "NotificationPreferences", "CommunityEvents", "Subcategories",
]

WIKI_NOISE_CLASSES = ["page-metadata", "plugin_pagetree", "confluence-information-macro"]

# ── Enrichment helpers ────────────────────────────────────────────────────────

_EXACT_TERM_RE = re.compile(r"\b[A-Z][A-Z0-9_]{4,}\b")

# Maps wiki URL space key (lowercase) to product_area vocabulary value
_WIKI_SPACE_PRODUCT: dict[str, str] = {
    "mpdevwiki": "mpages",
    "mpages": "mpages",
    "mpageschart": "mpages",
    "mpageschartlevel": "mpages",
    "bedrockhp": "bedrock",
    "bedrock": "bedrock",
    "1101discernhp": "discern",
    "discernhp": "discern",
    "discernexperthp": "discern",
    "da2hp": "discern",
    "cernerworksrp": "unknown",
    "reference": "unknown",
    "powercharthp": "powerchart",
    "powercharthome": "powerchart",
}

_PRODUCT_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bmpages?\b|\bcustom\s+mpage\b|\bmpage\b", re.IGNORECASE), "mpages"),
    (re.compile(r"\bbedrock\b", re.IGNORECASE), "bedrock"),
    (re.compile(r"\bprefmaint\b|\bpreferences\s+maintenance\b", re.IGNORECASE), "prefmaint"),
    (re.compile(r"\bdiscern\b|\bccl\b|\bexpert\s+rule\b", re.IGNORECASE), "discern"),
    (re.compile(r"\bpowerchart\b|\bpowerplan\b|\bpowerorders\b", re.IGNORECASE), "powerchart"),
]

_GROUP_PRODUCT_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"mpages?", re.IGNORECASE), "mpages"),
    (re.compile(r"discern|expert\s+rule|ccl", re.IGNORECASE), "discern"),
    (re.compile(r"powerchart|powerorders|millennium", re.IGNORECASE), "powerchart"),
    (re.compile(r"bedrock", re.IGNORECASE), "bedrock"),
]

_INTEGRATION_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bXMLCCLRequest\b", re.IGNORECASE), "xmlcclrequest"),
    (re.compile(r"\bXMLHTTPRequest\b", re.IGNORECASE), "xmlcclrequest"),
    (re.compile(
        r"\bdiscern.?report\b|\breport\s+viewer\b|\breport_param\b|\breport_name\b",
        re.IGNORECASE,
    ), "discern_report"),
    (re.compile(r"\bjson\b.{0,60}(?:select|from|ccl|subroutine)", re.IGNORECASE | re.DOTALL), "json_from_ccl"),
]

_RUNTIME_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bwebview.?2\b", re.IGNORECASE), "edge_webview2"),
    (re.compile(r"\bmicrosoft\s+edge\b|\bedge\s+browser\b|\bswitch.{0,20}(?:ie|edge)\b", re.IGNORECASE), "edge_webview2"),
    (re.compile(r"\binternet\s+explorer\b|\bie\s*11\b|\bie\.?11\b", re.IGNORECASE), "legacy_ie"),
    (re.compile(r"\boutside\s+powerchart\b|\bstandalone\s+browser\b", re.IGNORECASE), "outside_powerchart"),
]

_TOPIC_TAG_PATTERNS: list[tuple[re.Pattern, str]] = [
    (re.compile(r"\bmpages?\b|\bcustom\s+mpage\b", re.IGNORECASE), "mpages"),
    (re.compile(r"\bpowerchart\b", re.IGNORECASE), "powerchart"),
    (re.compile(r"\bedge\b|\bwebview.?2\b", re.IGNORECASE), "edge"),
    (re.compile(r"\bxmlcclrequest\b|\bxmlhttprequest\b", re.IGNORECASE), "xmlcclrequest"),
    (re.compile(r"\bprefmaint\b|\bpreferences\s+maintenance\b", re.IGNORECASE), "prefmaint"),
    (re.compile(r"\bdiscern.?report\b|\breport\s+viewer\b|\breport[_\s]param\b|\breport[_\s]name\b", re.IGNORECASE), "discern-report"),
    (re.compile(r"\bapplink\b|\bccllink\b|\bframeworklink\b|\bcclnewsessionwindow\b", re.IGNORECASE), "applink"),
    (re.compile(r"\bhtml.{0,10}output\b|\bhtml.{0,10}report\b|\bfull.{0,10}html\b", re.IGNORECASE), "html-output"),
    (re.compile(r"\bmpages.?event\b|\bmpages_event\b", re.IGNORECASE), "mpages"),
    (re.compile(r"\bbedrock\b", re.IGNORECASE), "bedrock"),
    (re.compile(r"\bdiscern\b", re.IGNORECASE), "discern"),
    (re.compile(r"\bpowerplan\b|\bpowerorders\b", re.IGNORECASE), "powerchart"),
]

_SEARCH_STOP_WORDS = frozenset(
    "with from that this have your using will after when what which into over also they"
    " just been some then more about only".split()
)


def _detect_product_area(canonical_url: str, title: str, group_name: str) -> str:
    space_m = re.search(r"/display/(?:public/)?([^/]+)/", canonical_url or "")
    if space_m:
        space = space_m.group(1).lower()
        if space in _WIKI_SPACE_PRODUCT and _WIKI_SPACE_PRODUCT[space] != "unknown":
            return _WIKI_SPACE_PRODUCT[space]
    url_lower = (canonical_url or "").lower()
    if any(host in url_lower for host in ("mpages-dev-docs", "pages.github.cerner", "mpages-fusion")):
        return "mpages"
    if group_name:
        for pat, area in _GROUP_PRODUCT_PATTERNS:
            if pat.search(group_name):
                return area
    for pat, area in _PRODUCT_PATTERNS:
        if pat.search(title or ""):
            return area
    return "unknown"


def _detect_integration_pattern(body: str, title: str, contains_code: bool) -> str:
    combined = (title or "") + " " + (body or "")
    for pat, result in _INTEGRATION_PATTERNS:
        if pat.search(combined):
            return result
    return "scriptrequest" if contains_code else "static_content"


def _detect_output_pattern(body: str, title: str) -> str:
    combined = ((title or "") + " " + (body or "")).lower()
    if re.search(r"\bjson\b.{0,40}(?:output|response|return|format)\b", combined) or re.search(r"(?:output|response|return|format).{0,40}\bjson\b", combined):
        return "json"
    if re.search(r"full\s+html|html\s+output|html\s+report|html\s+driver", combined):
        return "full_html"
    return "unknown"


def _detect_runtime_context(body: str, title: str) -> str:
    combined = (title or "") + " " + (body or "")
    for pat, result in _RUNTIME_PATTERNS:
        if pat.search(combined):
            return result
    return "unknown"


def _detect_artifact_type(section_type: str, contains_code: bool, body: str) -> str:
    if contains_code:
        return "code_example"
    if section_type == "original_post":
        return "forum_post"
    if section_type == "comment":
        return "forum_comment"
    if re.search(r"\b(?:troubl|workaround|not\s+work|error|issue|broken|fix)\b", (body or "").lower()):
        return "troubleshooting"
    return "wiki_section"


def _detect_topic_tags(body: str, title: str) -> list[str]:
    combined = (title or "") + " " + (body or "")
    tags: list[str] = []
    seen: set[str] = set()
    for pat, tag in _TOPIC_TAG_PATTERNS:
        if tag not in seen and pat.search(combined):
            tags.append(tag)
            seen.add(tag)
    return tags


def _detect_exact_terms(body: str) -> list[str]:
    found = _EXACT_TERM_RE.findall(body or "")
    filtered = [t for t in dict.fromkeys(found) if len(t) >= 5 and not re.fullmatch(r"[IVX]+", t)]
    return filtered[:40]


def _detect_search_terms(exact_terms: list[str], title: str) -> list[str]:
    terms = [t.lower() for t in exact_terms]
    seen = set(terms)
    for word in re.findall(r"[A-Za-z][A-Za-z0-9_]{3,}", title or ""):
        lower = word.lower()
        if lower not in seen and lower not in _SEARCH_STOP_WORDS:
            terms.append(lower)
            seen.add(lower)
    return terms[:50]


def build_enrichment(
    *,
    canonical_url: str,
    title: str,
    section_type: str,
    body: str,
    group_name: str,
    contains_code: bool,
    code_languages: list[str],
) -> dict:
    """Return the 10 enrichment fields for a chunk record."""
    product_area = _detect_product_area(canonical_url, title, group_name)
    integration_pattern = _detect_integration_pattern(body, title, contains_code)
    output_pattern = _detect_output_pattern(body, title)
    runtime_context = _detect_runtime_context(body, title)
    artifact_type = _detect_artifact_type(section_type, contains_code, body)
    topic_tags = _detect_topic_tags(body, title)
    exact_terms = _detect_exact_terms(body)
    search_terms = _detect_search_terms(exact_terms, title)
    return {
        "product_area": product_area,
        "integration_pattern": integration_pattern,
        "output_pattern": output_pattern,
        "runtime_context": runtime_context,
        "artifact_type": artifact_type,
        "search_terms": search_terms,
        "exact_terms": exact_terms,
        "topic_tags": topic_tags,
        "contains_code": contains_code,
        "code_languages": code_languages if contains_code else [],
    }


def build_document_enrichment(
    chunk_enrichments: list[dict],
    canonical_url: str,
    title: str,
    group_name: str,
) -> dict:
    """Derive document-level enrichment fields from the union of its chunks."""
    from collections import Counter as _Counter

    if not chunk_enrichments:
        return build_enrichment(
            canonical_url=canonical_url,
            title=title,
            section_type="content",
            body="",
            group_name=group_name,
            contains_code=False,
            code_languages=[],
        )

    def first_nonempty(field: str, exclude: tuple = ("unknown", "", "static_content")) -> str:
        for e in chunk_enrichments:
            v = e.get(field, "")
            if v and v not in exclude:
                return v
        return chunk_enrichments[0].get(field, "unknown")

    product_area = first_nonempty("product_area", ("unknown", ""))
    integration_pattern = first_nonempty("integration_pattern", ("unknown", "static_content", ""))
    if not integration_pattern or integration_pattern in ("unknown", ""):
        integration_pattern = "static_content"
    output_pattern = first_nonempty("output_pattern", ("unknown", ""))
    if not output_pattern or output_pattern == "":
        output_pattern = "unknown"
    runtime_context = first_nonempty("runtime_context", ("unknown", ""))
    if not runtime_context or runtime_context == "":
        runtime_context = "unknown"

    ats = [e.get("artifact_type", "wiki_section") for e in chunk_enrichments]
    artifact_type = _Counter(ats).most_common(1)[0][0] if ats else "wiki_section"

    all_tags: list[str] = []
    seen_tags: set[str] = set()
    for e in chunk_enrichments:
        for tag in e.get("topic_tags", []):
            if tag not in seen_tags:
                all_tags.append(tag)
                seen_tags.add(tag)

    all_exact: list[str] = []
    seen_exact: set[str] = set()
    for e in chunk_enrichments:
        for t in e.get("exact_terms", []):
            if t not in seen_exact:
                all_exact.append(t)
                seen_exact.add(t)

    all_search: list[str] = []
    seen_search: set[str] = set()
    for e in chunk_enrichments:
        for t in e.get("search_terms", []):
            if t not in seen_search:
                all_search.append(t)
                seen_search.add(t)

    contains_code = any(e.get("contains_code") for e in chunk_enrichments)
    all_langs: list[str] = []
    seen_langs: set[str] = set()
    for e in chunk_enrichments:
        for lang in e.get("code_languages", []):
            if lang not in seen_langs:
                all_langs.append(lang)
                seen_langs.add(lang)
    if len(all_langs) > 1 and "mixed" not in all_langs:
        all_langs = ["mixed"]

    return {
        "product_area": product_area,
        "integration_pattern": integration_pattern,
        "output_pattern": output_pattern,
        "runtime_context": runtime_context,
        "artifact_type": artifact_type,
        "search_terms": all_search[:50],
        "exact_terms": all_exact[:50],
        "topic_tags": all_tags,
        "contains_code": contains_code,
        "code_languages": all_langs if contains_code else [],
    }


def extract_forum_content(soup: BeautifulSoup) -> str:
    parts = []
    # Save the comments reference before any DOM mutations so we still hold
    # it after removing the nested element from pagebox.
    comments = soup.find("ul", class_="Comments")

    pagebox = soup.find("section", class_="pageBox")
    if pagebox:
        for noise in pagebox.find_all(class_=FORUM_NOISE_CLASSES):
            noise.extract()
        for el in pagebox(["script", "style", "noscript", "iframe"]):
            el.extract()
        # ul.Comments is nested inside section.pageBox in Vanilla forum pages.
        # Removing it here prevents comment text from being emitted twice:
        # once inside the original_post segment and once per comment segment.
        nested = pagebox.find("ul", class_="Comments")
        if nested:
            nested.extract()
        parts.append(str(pagebox))
    else:
        log.warning("  Forum: could not find section.pageBox - falling back to <main>")
        fallback = soup.find("main") or soup.find(class_="MainContent")
        if fallback:
            parts.append(str(fallback))

    if comments:
        for noise in comments.find_all(class_=FORUM_NOISE_CLASSES):
            noise.extract()
        for el in comments(["script", "style", "noscript", "iframe"]):
            el.extract()
        parts.append(str(comments))

    return "\n".join(parts)


def extract_wiki_content(soup: BeautifulSoup) -> str:
    main = soup.find(id="main-content") or soup.find(id="content") or soup.find(class_="wiki-content")
    if not main:
        log.warning("  Wiki: could not find content container - falling back to full soup")
        main = soup

    for noise in main.find_all(class_=WIKI_NOISE_CLASSES):
        noise.extract()
    for el in main(["script", "style", "nav", "footer", "header", "aside", "noscript", "iframe"]):
        el.extract()

    return str(main)


def extract_group_info(soup: BeautifulSoup, source_url: str) -> dict:
    group_info: dict[str, str] = {}
    group_link = soup.find("a", href=re.compile(r"/group/\d", re.IGNORECASE))
    if group_link:
        gname = normalize_text(group_link.get_text(" ", strip=True))
        ghref = group_link.get("href", "")
        if ghref and not ghref.startswith("http"):
            ghref = "https://community.oracle.com" + ghref
        if gname:
            group_info = {"group_name": gname, "group_url": ghref}
    if not group_info and source_url:
        group_info = dict(GROUP_METADATA.get(source_url, {}))
    if not group_info:
        cat_meta = soup.find("meta", attrs={"name": "category"})
        cat_name = normalize_text(cat_meta.get("content", "")) if cat_meta else ""
        if cat_name:
            group_info = {"group_name": cat_name, "group_url": ""}
    group_url = group_info.get("group_url", "")
    group_id_match = re.search(r"/group/(\d+)-", group_url)
    if group_id_match:
        group_info["group_id"] = group_id_match.group(1)
    return group_info


def extract_author_name(node: BeautifulSoup) -> str:
    for link in node.find_all("a", href=re.compile(r"/profile/", re.IGNORECASE), limit=5):
        name = normalize_text(link.get_text(" ", strip=True))
        if name and name.lower() != "unknown":
            return name
    return ""


def extract_forum_segments(content_html: str) -> list[dict]:
    soup = BeautifulSoup(content_html, "html.parser")
    segments: list[dict] = []

    original = soup.find("section", class_="pageBox") or soup.find("main") or soup.find(class_="MainContent")
    if original:
        original_html = str(original)
        has_code, code_langs = detect_code_info(original_html)
        text = html_to_text(original_html)
        if text:
            segments.append({
                "section_type": "original_post",
                "section_title": "Original post",
                "speaker": extract_author_name(original),
                "text": text,
                "_contains_code": has_code,
                "_code_languages": code_langs,
            })

    comments = soup.find("ul", class_="Comments")
    if comments:
        items = [child for child in comments.find_all(recursive=False) if getattr(child, "name", None)]
        if not items:
            items = comments.find_all(["li", "article", "section"], recursive=False)
        for idx, item in enumerate(items, start=1):
            item_html = str(item)
            has_code, code_langs = detect_code_info(item_html)
            text = html_to_text(item_html)
            if not text:
                continue
            segments.append({
                "section_type": "comment",
                "section_title": f"Comment {idx}",
                "speaker": extract_author_name(item),
                "text": text,
                "_contains_code": has_code,
                "_code_languages": code_langs,
            })

    return segments


def extract_wiki_segments(content_html: str) -> list[dict]:
    soup = BeautifulSoup(content_html, "html.parser")
    root = soup.find() or soup
    segments: list[dict] = []
    current_title = "Overview"
    current_parts: list[str] = []

    def flush() -> None:
        nonlocal current_parts
        section_html = "".join(current_parts).strip()
        if not section_html:
            current_parts = []
            return
        has_code, code_langs = detect_code_info(section_html)
        text = html_to_text(section_html)
        if text:
            segments.append({
                "section_type": "section",
                "section_title": current_title,
                "speaker": "",
                "text": text,
                "_contains_code": has_code,
                "_code_languages": code_langs,
            })
        current_parts = []

    for child in list(root.children):
        name = getattr(child, "name", None)
        if name and re.fullmatch(r"h[1-6]", name):
            flush()
            heading = normalize_text(child.get_text(" ", strip=True))
            current_title = heading or "Overview"
            continue
        if getattr(child, "strip", None) and not str(child).strip():
            continue
        current_parts.append(str(child))

    flush()

    if not segments:
        has_code, code_langs = detect_code_info(str(root))
        text = html_to_text(str(root))
        if text:
            segments.append({
                "section_type": "section",
                "section_title": current_title,
                "speaker": "",
                "text": text,
                "_contains_code": has_code,
                "_code_languages": code_langs,
            })

    return segments


def build_segments(platform: str, content_html: str) -> list[dict]:
    if platform == "forum":
        return extract_forum_segments(content_html)
    if platform == "wiki":
        return extract_wiki_segments(content_html)
    text = html_to_text(content_html)
    return [{
        "section_type": "content",
        "section_title": "Content",
        "speaker": "",
        "text": text,
    }] if text else []


# Local File Processing

def get_file_hash(file_path: Path) -> str:
    hasher = hashlib.md5()
    hasher.update(_read_bytes_file(file_path))
    return hasher.hexdigest()


def process_local_directory() -> tuple[list[dict], list[dict]]:
    folder = Path(LOCAL_DOWNLOADS_DIR)
    log.info("Scanning %s for manual HTML/MHTML files...", LOCAL_DOWNLOADS_DIR)

    documents: list[dict] = []
    chunks: list[dict] = []
    seen_hashes: set[str] = set()
    seen_urls: set[str] = set()

    existing_documents = load_jsonl(DOCUMENTS_OUTPUT)
    existing_chunks = load_jsonl(CHUNKS_OUTPUT)
    docs_by_source, chunks_by_source = build_source_record_maps(existing_documents, existing_chunks)
    processing_cache = load_processing_cache()
    refreshed_cache: dict[str, dict] = {}

    reused_count = 0
    parsed_count = 0
    skipped_count = 0

    html_files = sorted(folder.rglob("*.[hH][tT][mM]*"), key=lambda p: str(p).lower())
    for file_path in html_files:
        source_path = file_path.relative_to(BASE_DIR).as_posix()
        stat = os.stat(_fs_path(file_path))
        cache_entry = processing_cache.get(source_path, {})
        cache_hit = (
            isinstance(cache_entry, dict)
            and cache_entry.get("mtime_ns") == stat.st_mtime_ns
            and cache_entry.get("size") == stat.st_size
        )

        if cache_hit:
            file_hash = str(cache_entry.get("file_hash", ""))
            dedup_key = str(cache_entry.get("dedup_key", "") or file_hash)
            status = str(cache_entry.get("status", ""))

            if file_hash and file_hash in seen_hashes:
                refreshed_cache[source_path] = cache_entry
                skipped_count += 1
                log.info("Skipping cached duplicate file hash: %s", file_path.name)
                continue

            if dedup_key and dedup_key in seen_urls:
                if file_hash:
                    seen_hashes.add(file_hash)
                refreshed_cache[source_path] = cache_entry
                skipped_count += 1
                log.info("Skipping cached duplicate URL: %s (File: %s)", dedup_key, file_path.name)
                continue

            if status == "processed":
                cached_document = docs_by_source.get(source_path)
                cached_chunks = chunks_by_source.get(source_path, [])
                if cached_document and cached_chunks:
                    platform = detect_platform(cached_document.get("canonical_url", ""), file_path.name)
                    if cached_document.get("platform") != platform:
                        cached_document["platform"] = platform
                        for chunk_record in cached_chunks:
                            chunk_record["platform"] = platform
                    documents.append(cached_document)
                    chunks.extend(cached_chunks)
                    if file_hash:
                        seen_hashes.add(file_hash)
                    if dedup_key:
                        seen_urls.add(dedup_key)
                    refreshed_cache[source_path] = cache_entry
                    reused_count += 1
                    log.info(
                        "Reused cached parse: %s -> %d chunk(s) across %d section(s)",
                        file_path.name,
                        int(cached_document.get("total_chunks", len(cached_chunks))),
                        int(cached_document.get("section_count", 0)),
                    )
                    continue

            if status == "no_text":
                if file_hash:
                    seen_hashes.add(file_hash)
                if dedup_key:
                    seen_urls.add(dedup_key)
                refreshed_cache[source_path] = cache_entry
                skipped_count += 1
                log.info("Skipping cached empty content: %s", file_path.name)
                continue

        file_hash = get_file_hash(file_path)
        if file_hash in seen_hashes:
            refreshed_cache[source_path] = {
                "status": "duplicate_hash",
                "file_hash": file_hash,
                "dedup_key": file_hash,
                "mtime_ns": stat.st_mtime_ns,
                "size": stat.st_size,
            }
            skipped_count += 1
            log.info("Skipping duplicate file hash: %s", file_path.name)
            continue

        try:
            html_content = read_html_from_file(str(file_path))
            soup = BeautifulSoup(html_content, "html.parser")

            raw_title = soup.title.string.strip() if soup.title and soup.title.string else file_path.stem
            title = normalize_text(raw_title)
            title_clean = clean_title(title)

            canonical_url = ""
            canon_tag = soup.find("link", rel="canonical")
            if canon_tag and canon_tag.get("href"):
                canonical_url = canon_tag["href"]
            else:
                og_url = soup.find("meta", property="og:url")
                if og_url and og_url.get("content"):
                    canonical_url = og_url["content"]
                else:
                    sf_match = re.search(r"url:\s*(https?://[^\s<>]+)", html_content[:5000], re.IGNORECASE)
                    if sf_match:
                        canonical_url = sf_match.group(1)
                    else:
                        rss_link = soup.find("link", type="application/rss+xml")
                        if rss_link and rss_link.get("href"):
                            canonical_url = rss_link["href"].replace("/feed.rss", "")
                        else:
                            slug = re.sub(r"\s*[-–—]+\s*Oracle Health\.html?$", "", file_path.name, flags=re.IGNORECASE).strip().lower()
                            for group_url in GROUP_METADATA.keys():
                                url_slug = re.sub(r"^\d+[-\s]*", "", group_url.split("/")[-1].replace("-", " ")).lower()
                                if url_slug and len(url_slug) > 8 and (url_slug in slug or slug.startswith(url_slug[:25])):
                                    canonical_url = group_url
                                    break

            canonical_url = normalize_url(canonical_url)

            platform = detect_platform(canonical_url, file_path.name, html_content[:2000])
            if platform == "unknown":
                log.warning("  Could not detect platform for %s - using full page", file_path.name)

            if platform == "wiki" and not canonical_url:
                space = "reference"
                if "MPages Development" in file_path.name:
                    space = "mpdevwiki"
                elif "Bedrock" in file_path.name:
                    space = "bedrockHP"
                elif "Discern" in file_path.name:
                    space = "1101discernHP"
                elif "CernerWorks" in file_path.name:
                    space = "cernerworksrp"
                canonical_url = f"https://wiki.cerner.com/display/{space}/{quote(title_clean.replace(' ', '+'), safe='+')}"
                canonical_url = normalize_url(canonical_url)

            dedup_key = canonical_url or file_hash
            if dedup_key in seen_urls:
                refreshed_cache[source_path] = {
                    "status": "duplicate_url",
                    "file_hash": file_hash,
                    "dedup_key": dedup_key,
                    "mtime_ns": stat.st_mtime_ns,
                    "size": stat.st_size,
                }
                seen_hashes.add(file_hash)
                skipped_count += 1
                log.info("Skipping duplicate URL: %s (File: %s)", canonical_url or file_hash, file_path.name)
                continue

            if platform == "wiki":
                content_html = extract_wiki_content(soup)
            elif platform == "forum":
                content_html = extract_forum_content(soup)
            else:
                content_html = str(soup)

            links = extract_links(content_html)
            if canonical_url:
                links["forum"] = [link for link in links["forum"] if normalize_url(link) != canonical_url]
                links["wiki"] = [link for link in links["wiki"] if normalize_url(link) != canonical_url]

            segments = build_segments(platform, content_html)
            if not segments:
                refreshed_cache[source_path] = {
                    "status": "no_text",
                    "file_hash": file_hash,
                    "dedup_key": dedup_key,
                    "mtime_ns": stat.st_mtime_ns,
                    "size": stat.st_size,
                }
                log.warning("  No text extracted from %s", file_path.name)
                seen_hashes.add(file_hash)
                seen_urls.add(dedup_key)
                skipped_count += 1
                continue

            group_info = extract_group_info(soup, canonical_url) if platform == "forum" else {}
            doc_id = build_doc_id(platform, canonical_url, file_hash)

            chunk_records: list[dict] = []
            chunk_enrichments: list[dict] = []
            full_text_parts: list[str] = []
            chunk_index = 1
            for section_index, segment in enumerate(segments, start=1):
                segment_text = normalize_text(segment.get("text", ""))
                if not segment_text:
                    continue
                full_text_parts.append(segment_text)
                seg_has_code = segment.get("_contains_code", False)
                seg_code_langs = segment.get("_code_languages", [])
                for chunk in chunk_text(segment_text):
                    enrichment = build_enrichment(
                        canonical_url=canonical_url,
                        title=title_clean or title,
                        section_type=segment.get("section_type", "content"),
                        body=chunk,
                        group_name=group_info.get("group_name", ""),
                        contains_code=seg_has_code,
                        code_languages=seg_code_langs,
                    )
                    chunk_enrichments.append(enrichment)
                    chunk_records.append({
                        "chunk_id": build_chunk_id(doc_id, chunk_index),
                        "doc_id": doc_id,
                        "type": "manual_upload_chunk",
                        "title": title,
                        "title_clean": title_clean,
                        "platform": platform,
                        "canonical_url": canonical_url,
                        "source_file": file_path.name,
                        "source_path": source_path,
                        "chunk_index": chunk_index,
                        "total_chunks": 0,
                        "section_index": section_index,
                        "section_title": segment.get("section_title", "Content"),
                        "section_type": segment.get("section_type", "content"),
                        "speaker": segment.get("speaker", ""),
                        "body": chunk,
                        "body_preview": preview_text(chunk, 280),
                        "word_count": len(chunk.split()),
                        "links_forum": links["forum"],
                        "links_wiki": links["wiki"],
                        "links_external": links["reference"],
                        **({k: v for k, v in group_info.items() if v}),
                        **enrichment,
                    })
                    chunk_index += 1

            total_chunks = len(chunk_records)
            for record in chunk_records:
                record["total_chunks"] = total_chunks

            full_text = "\n\n".join(full_text_parts)
            doc_enrichment = build_document_enrichment(
                chunk_enrichments,
                canonical_url=canonical_url,
                title=title_clean or title,
                group_name=group_info.get("group_name", ""),
            )
            document_record = {
                "doc_id": doc_id,
                "type": "manual_upload_document",
                "file_hash": file_hash,
                "title": title,
                "title_clean": title_clean,
                "source_file": file_path.name,
                "source_path": source_path,
                "platform": platform,
                "canonical_url": canonical_url,
                "links_forum": links["forum"],
                "links_wiki": links["wiki"],
                "links_external": links["reference"],
                "section_count": len(full_text_parts),
                "total_chunks": total_chunks,
                "word_count": len(full_text.split()),
                "body_preview": preview_text(full_text, 420),
                **({k: v for k, v in group_info.items() if v}),
                **doc_enrichment,
            }
            documents.append(document_record)
            chunks.extend(chunk_records)

            refreshed_cache[source_path] = {
                "status": "processed",
                "file_hash": file_hash,
                "dedup_key": dedup_key,
                "mtime_ns": stat.st_mtime_ns,
                "size": stat.st_size,
            }
            seen_hashes.add(file_hash)
            seen_urls.add(dedup_key)
            parsed_count += 1
            log.info("Processed: %s -> %d chunk(s) across %d section(s)", file_path.name, total_chunks, len(full_text_parts))

        except Exception as exc:
            refreshed_cache[source_path] = {
                "status": "error",
                "file_hash": file_hash,
                "dedup_key": file_hash,
                "mtime_ns": stat.st_mtime_ns,
                "size": stat.st_size,
                "error": str(exc),
            }
            log.warning("Failed to process %s: %s", file_path.name, exc)

    write_jsonl(DOCUMENTS_OUTPUT, documents)
    write_jsonl(CHUNKS_OUTPUT, chunks)
    write_jsonl(LEGACY_OUTPUT, chunks)
    save_processing_cache(refreshed_cache)

    log.info("Wrote %d documents to %s", len(documents), DOCUMENTS_OUTPUT)
    log.info("Wrote %d chunks to %s", len(chunks), CHUNKS_OUTPUT)
    log.info(
        "Processing cache: %d reused, %d parsed, %d skipped",
        reused_count,
        parsed_count,
        skipped_count,
    )
    return documents, chunks

def enrich_jsonl_group_metadata() -> None:
    doc_path = Path(DOCUMENTS_OUTPUT)
    if not doc_path.exists():
        return

    docs = load_jsonl(doc_path)
    if not docs:
        return

    from bs4 import BeautifulSoup as _BS

    dl_dir = Path(LOCAL_DOWNLOADS_DIR)
    updated = 0
    enriched_cache: dict[str, dict] = {}
    missing_file_count = 0

    for record in docs:
        if record.get("group_name") and record.get("canonical_url"):
            continue
        if record.get("platform") != "forum":
            continue

        fname = record.get("source_file", "")
        if fname in enriched_cache:
            data = enriched_cache[fname]
        else:
            data = {}
            file_path = dl_dir / fname
            if file_path.exists():
                try:
                    html = read_html_from_file(str(file_path))
                    soup = _BS(html, "html.parser")
                    data = extract_group_info(soup, normalize_url(record.get("canonical_url", "")))
                    canon_tag = soup.find("link", rel="canonical")
                    canon = normalize_url(canon_tag["href"]) if canon_tag and canon_tag.get("href") else normalize_url(record.get("canonical_url", ""))
                    if canon:
                        data["canonical_url"] = canon
                except Exception:
                    data = {}
            else:
                missing_file_count += 1
                stem = re.sub(r"\s*[-\u2013\u2014]+\s*Oracle Health\.html?$", "", fname, flags=re.IGNORECASE)
                stem = re.sub(r"\.html?$", "", stem, flags=re.IGNORECASE).strip()
                slug = re.sub(r"[^a-z0-9]+", "-", stem.lower()).strip("-")
                for url, ginfo in GROUP_METADATA.items():
                    url_slug = url.split("/")[-1]
                    if url_slug == slug or url_slug.startswith(slug[:30]):
                        data = {
                            "group_name": ginfo.get("group_name", ""),
                            "group_url": ginfo.get("group_url", ""),
                            "group_id": ginfo.get("group_id", ""),
                            "canonical_url": url,
                        }
                        break
            enriched_cache[fname] = data

        changed = False
        for key in ("group_name", "group_url", "group_id", "canonical_url"):
            if data.get(key) and not record.get(key):
                record[key] = data[key]
                changed = True
        if changed:
            updated += 1

    if not updated:
        if missing_file_count:
            log.warning("Enrichment: %d unique forum file(s) not found in %s/", missing_file_count, LOCAL_DOWNLOADS_DIR)
        return

    write_jsonl(doc_path, docs)
    doc_map = {record.get("doc_id"): record for record in docs}
    for chunk_path in (Path(CHUNKS_OUTPUT), Path(LEGACY_OUTPUT)):
        chunk_records = load_jsonl(chunk_path)
        if not chunk_records:
            continue
        changed_chunks = 0
        for chunk in chunk_records:
            doc = doc_map.get(chunk.get("doc_id"))
            if not doc:
                continue
            for key in ("group_name", "group_url", "group_id", "canonical_url"):
                if doc.get(key) and chunk.get(key) != doc.get(key):
                    chunk[key] = doc[key]
                    changed_chunks += 1
        if changed_chunks:
            write_jsonl(chunk_path, chunk_records)

    log.info("Enriched %d forum document(s) with group/canonical metadata.", updated)
    if missing_file_count:
        log.warning("Enrichment: %d unique forum file(s) not found in %s/", missing_file_count, LOCAL_DOWNLOADS_DIR)

DISCOVERY_OUTPUT = REPORTS_DIR / "MissingPages"

def _filename_to_title(fname: str) -> str:
    for suffix in [
        " - Discern Help Pages - Cerner Wiki.html",
        " - CernerWorks Reference Pages - Cerner Wiki.html",
    ]:
        if fname.lower().endswith(suffix.lower()):
            return fname[:-len(suffix)].replace("_", " ").replace("+", " ").strip().lower()
    for suffix in [
        " - MPages Development Wiki - Cerner Wiki.html", " - Reference Pages - Cerner Wiki.html",
        " - Bedrock Help Pages - Cerner Wiki.html", " - Cerner Wiki.html", " — Oracle Health.html",
        ".html", ".htm",
    ]:
        if fname.lower().endswith(suffix.lower()):
            return fname[:-len(suffix)].replace("_", " ").replace("+", " ").strip().lower()
    return fname.replace("_", " ").replace("+", " ").lower()

def _normalize_wiki_url(url: str) -> str:
    if not url:
        return ""
    full = url if url.startswith("http") else f"https://wiki.cerner.com{url}"
    full = re.sub(r"#.*$", "", full)
    full = re.sub(r"\?.*$", "", full)
    full = unquote(full).rstrip("/")
    full = re.sub(
        r"^https?://wiki\.cerner\.com/display/public/",
        "https://wiki.cerner.com/display/",
        full,
        flags=re.IGNORECASE,
    )
    full = re.sub(r"^http://", "https://", full, flags=re.IGNORECASE)
    return full.lower()

def _wiki_url_to_title(url: str) -> str | None:
    url = url if url.startswith("http") else f"https://wiki.cerner.com{url}"
    url = re.sub(r"#.*$", "", url)
    m = re.search(r"/display/(?:public/)?[^/]+/(.+)$", url)
    if m: return unquote(m.group(1).replace("+", " ")).strip().lower()
    return None

def _friendly_slug_title(value: str) -> str:
    text = value or ""
    if text.startswith("http"):
        parsed = urlparse(text)
        text = parsed.path.rstrip("/").split("/")[-1]
    text = unquote(text)
    text = re.sub(r"^\d+[-\s]*", "", text)
    text = re.sub(r"[_+\-]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text.title() if text else "Other"

def _categorise_wiki_space(space: str) -> str | None:
    space = (space or "").lower()
    if not space:
        return None

    if space == "mpdevwiki" or "r1mpageshp" in space or space == "dbarchhp":
        return "MPages Development"
    if "bedrockhp" in space:
        return "Bedrock"
    if any(x in space for x in ["healthecaehp", "healthcarehp", "healthecare", "healtheintent", "healthintent", "healtheedwhp", "caremanagementhp", "hchp", "hcintelligencehp", "healthedatalabhp", "healtheinsightshp", "healthelifehp", "healtherecordhp", "healtheregistrieshp", "hiriskshp", "mpmhp"]):
        return "HealtheIntent & Care Management"
    if space in ("help", "helpnl", "cernercentral", "eservicehp", "hitoolshp", "30olympushp", "rn", "courses", "wikihelp", "alldoc", "cls", "hsdoc", "llstandardlibrary", "regcom", "se"):
        return "Platform Help"
    if any(x in space for x in ["discernhp", "discernexperthp", "da2hp", "cernerworksrp", "cernerworks", "millenniumopshp", "knowledgeapps", "securityhp", "openlinkimhp", "commonwellhp", "consultingframeworktechnologyhp", "flashhp", "lightsonhp", "blueframehp", "aishp", "calhp", "icommandhp", "iawarehp", "mpipg", "physiciananalytics"]):
        return "Platform Admin"
    if "initiativedetail" in space or space.startswith("{"):
        return "Other"
    if any(x in space for x in ["performanceimprovement", "aohp", "carecompasshp", "cmptflowhp", "1101palhp", "staffassignhp", "1101supplychainhp", "cctahp", "groupchartinghp", "patienttimelinehp", "longplanhp", "nutritionaldashboardhp"]):
        return "MPages Worklists & Organizers"
    if any(x in space for x in ["maternity", "powertrials", "firstnet", "powerforms", "clinicalnotes", "infectioncontrol", "pharmnetinpatient", "pharmnetretail", "eprescribe", "eutmaterials", "cdcomponentshp", "chartsearchhp", "crdoc", "integratedchartinghp", "smarttemplateshp", "powercharthp", "enterprisemessaging", "millenniumpmhp", "1101dynamicdochp"]):
        return "Clinical Applications"
    if space.startswith("1101") or space.endswith("hp") or "hp" in space:
        return "Clinical Applications"
    return None

def _categorise_wiki(title: str, url: str) -> str:
    space_m = re.search(r"/display/(?:public/)?([^/]+)/", url)
    space = space_m.group(1).lower() if space_m else ""
    t = title.lower()
    host = urlparse(url if url.startswith("http") else f"https://wiki.cerner.com{url}").netloc.lower()

    space_category = _categorise_wiki_space(space)
    if space_category:
        return space_category

    if any(x in host for x in ["mpages-dev-docs.cerner.com", "pages.github.cerner.com", "mpages-fusion.cerner.com"]):
        if any(x in t for x in ["overview", "prerequisites", "installation", "quick start", "conventions", "custom mpages development"]):
            return "MPages Configuration"
        if any(x in t for x in ["bedrock", "custom styling", "fusioncomponent", "frameworklink", "infobutton", "kia", "linter", "listmaintenance", "mpages drivers", "mpages gaia", "native functions", "orders", "patientcontext", "patienteducation", "patientfocus", "patientsearch", "powerform", "powernote", "pregnancy", "scheduling", "taskdoc", "viewers", "workflow component"]):
            return "MPages Development"

    if any(x in t for x in ["dashboard", "healthecare", "care management", "care manager", "cases by status", "potential cases", "referral component", "acute case management"]): return "HealtheIntent & Care Management"
    if any(x in t for x in ["worklist", "organizer", "organiser", "schedule view", "palliative", "handoff", "procurement", "pcs worklist", "record restoration", "patient organizer", "physician handoff"]): return "MPages Worklists & Organizers"
    if any(x in t for x in ["configure", "install", "define", "design", "overview of", "understand", "all about", "patient list", "clinical event", "add a patient", "mpages reference", "implement"]): return "MPages Configuration"
    if any(x in t for x in ["enterprise java", "edge", "zoom level", "discern", "output viewer", "troubleshoot", "maintain", "servers and", "when to cycle", "millennium openid", "openid provider", "millennium operations", "enterprise appliance reference", "back-end products", "utilities reference", "contributor system", "cpm script", "millennium platform", "server 79", "businessobjects", "business objects", "reporting portal", "functional reports", "physician analytics", "openlink"]): return "Platform Admin"
    if any(x in t for x in ["pharmacy", "medication administration", "mar reference", "charge", "medical specialties", "powerorders", "plans reference", "laboratory", "preferences for common"]): return "Clinical Applications"
    return "Other"

def _check_unknown_spaces(records: list) -> None:
    seen_unknown: dict = {}
    for r in records:
        for url in r.get("links_wiki", []):
            m = re.search(r"/display/(?:public/)?([^/]+)/", url)
            if not m: continue
            space = m.group(1).lower()
            if space.startswith("{"):
                continue
            if _categorise_wiki_space(space) is None and space != "reference" and space not in seen_unknown:
                seen_unknown[space] = url
    if seen_unknown:
        log.warning("Unknown wiki spaces found — consider updating _categorise_wiki:")
        for space, example_url in sorted(seen_unknown.items()): log.warning("  [%s]  e.g. %s", space, example_url)


def generate_discovery_report():
    jsonl_path = Path(DOCUMENTS_OUTPUT)
    if not jsonl_path.exists():
        return

    import jsonlines as _jl
    with _jl.open(jsonl_path) as reader:
        records = list(reader)
    if not records:
        return
    _check_unknown_spaces(records)

    from datetime import datetime
    from collections import defaultdict

    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    out_dir = Path(DISCOVERY_OUTPUT)
    out_dir.mkdir(exist_ok=True)
    history_path = Path(MISSING_LINK_HISTORY_FILE)
    ignored_links = load_ignored_links()

    known_wiki_titles: set[str] = set()
    known_wiki_urls: set[str] = set()
    for record in records:
        src_file = record.get("source_file", "")
        canon_raw = (record.get("canonical_url") or "").strip()
        canon_norm = _normalize_wiki_url(canon_raw)
        is_wiki = (
            record.get("platform") == "wiki"
            or "wiki.cerner.com" in canon_raw.lower()
            or "cerner wiki" in src_file.lower()
        )
        if not is_wiki:
            continue
        if src_file:
            known_wiki_titles.add(_filename_to_title(src_file))
        if canon_norm:
            known_wiki_urls.add(canon_norm)
            canon_title = _wiki_url_to_title(canon_norm)
            if canon_title:
                known_wiki_titles.add(canon_title)

    wiki_candidates: dict[str, str] = {}
    for record in records:
        for url in record.get("links_wiki", []):
            full = _normalize_wiki_url(url)
            if not full or full in known_wiki_urls:
                continue
            title = _wiki_url_to_title(full)
            if title and title in known_wiki_titles:
                continue
            if title and title not in wiki_candidates:
                wiki_candidates[title] = full

    known_forum: set[str] = set()
    for record in records:
        if record.get("platform") != "forum":
            continue
        if record.get("canonical_url"):
            known_forum.add(record["canonical_url"].rstrip("/"))
        fname = record.get("source_file", "")
        slug = re.sub(r'\s*[??????-]+\s*Oracle Health\.html?$', '', fname, flags=re.IGNORECASE).strip().lower()
        if slug:
            known_forum.add(slug)

    forum_candidates: dict[str, str] = {}
    for record in records:
        for url in record.get("links_forum", []):
            full = re.sub(r"#.*$", "", url).rstrip("/") if url.startswith("http") else ""
            if not full or full in known_forum:
                continue
            url_slug = full.split("/")[-1].replace("-", " ").lower()
            url_slug_no_id = re.sub(r"^\d+\s*", "", url_slug)
            if any(url_slug_no_id in item or item in url_slug_no_id for item in known_forum if " " in item):
                continue
            if full not in forum_candidates:
                forum_candidates[full] = full

    missing_history: dict[str, str] = {}
    if history_path.exists():
        try:
            loaded = json.loads(history_path.read_text(encoding="utf-8"))
            if isinstance(loaded, dict):
                missing_history = {str(k): str(v) for k, v in loaded.items()}
        except Exception as exc:
            log.warning("Could not read %s: %s", history_path.name, exc)

    current_missing_urls = set(wiki_candidates.values()) | set(forum_candidates.keys())
    for url in current_missing_urls:
        if url not in missing_history:
            missing_history[url] = now

    try:
        history_path.write_text(json.dumps(missing_history, indent=2, sort_keys=True), encoding="utf-8")
    except Exception as exc:
        log.warning("Could not write %s: %s", history_path.name, exc)

    def forum_group_details(url: str) -> tuple[str, str, str]:
        ginfo = GROUP_METADATA.get(url, {})
        group_url = ginfo.get("group_url", "")
        gname = ginfo.get("group_name") or "Other"
        if gname.startswith("http"):
            gname = _friendly_slug_title(group_url or gname)
        title = url.split("/")[-1].replace("-", " ").title()
        title = re.sub(r"^\d+\s+", "", title)
        return gname, title, group_url

    def build_item(title: str, url: str, kind: str, bucket: str) -> dict:
        ignored_meta = ignored_links.get(url, {})
        if ignored_meta:
            ignored_meta.setdefault("url", url)
            ignored_meta.setdefault("kind", kind)
            ignored_meta.setdefault("bucket", bucket)
            ignored_meta.setdefault("title", title)
        return {
            "title": title,
            "url": url,
            "kind": kind,
            "bucket": bucket,
            "added": missing_history.get(url, ""),
            "ignored_at": ignored_meta.get("ignored_at", ""),
            "reason": ignored_meta.get("reason", ""),
        }

    active_wiki_by_cat: defaultdict[str, list] = defaultdict(list)
    ignored_wiki_by_cat: defaultdict[str, list] = defaultdict(list)
    for title, url in wiki_candidates.items():
        bucket = _categorise_wiki(title, url)
        item = build_item(title.title(), url, "wiki", bucket)
        if url in ignored_links:
            ignored_wiki_by_cat[bucket].append(item)
        else:
            active_wiki_by_cat[bucket].append(item)

    active_forum_by_group: defaultdict[str, list] = defaultdict(list)
    ignored_forum_by_group: defaultdict[str, list] = defaultdict(list)
    group_page_urls: dict[str, str] = {}
    for url in sorted(forum_candidates):
        group_name, title, group_url = forum_group_details(url)
        item = build_item(title, url, "forum", group_name)
        if group_url:
            group_page_urls[group_name] = group_url
        if url in ignored_links:
            ignored_forum_by_group[group_name].append(item)
        else:
            active_forum_by_group[group_name].append(item)

    if ignored_links:
        save_ignored_links(ignored_links)

    CATEGORY_ORDER = [
        "MPages Configuration",
        "MPages Development",
        "MPages Worklists & Organizers",
        "Bedrock",
        "Platform Admin",
        "Platform Help",
        "Clinical Applications",
        "HealtheIntent & Care Management",
        "Other",
    ]
    ordered_wiki_cats = sorted(set(active_wiki_by_cat) | set(ignored_wiki_by_cat), key=lambda cat: CATEGORY_ORDER.index(cat) if cat in CATEGORY_ORDER else 99)
    ordered_forum_cats = sorted(set(active_forum_by_group) | set(ignored_forum_by_group), key=lambda g: (g == "Other", g.lower()))

    total_wiki = sum(len(items) for items in active_wiki_by_cat.values())
    total_forum = sum(len(items) for items in active_forum_by_group.values())
    total_ignored_wiki = sum(len(items) for items in ignored_wiki_by_cat.values())
    total_ignored_forum = sum(len(items) for items in ignored_forum_by_group.values())

    if (total_wiki + total_forum + total_ignored_wiki + total_ignored_forum) == 0:
        log.info("Discovery report: no pages to report.")
        return

    log.info(
        "Discovery report: %d wiki + %d forum active, %d wiki + %d forum ignored -> %s + %s/",
        total_wiki,
        total_forum,
        total_ignored_wiki,
        total_ignored_forum,
        ROOT_MISSING_OUTPUT.name,
        out_dir,
    )

    command_python = str(VENV_PYTHON if VENV_PYTHON.exists() else Path("python"))
    command_python_js = json.dumps(command_python)
    manage_script = str(MANAGE_MISSING_LINKS_SCRIPT)
    manage_script_js = json.dumps(manage_script)
    downloads_dir_display = html.escape(str(LOCAL_DOWNLOADS_DIR), quote=True)
    root_index_href = html.escape(ROOT_MISSING_OUTPUT.name, quote=True)
    subpages_href_prefix = html.escape(DISCOVERY_OUTPUT.relative_to(BASE_DIR).as_posix(), quote=True)
    manage_script_display = html.escape(manage_script, quote=True)
    python_display = html.escape(command_python, quote=True)

    SHARED_CSS = """
    body { font-family: Segoe UI, Arial, sans-serif; margin: 2rem; color: #222; max-width: 1180px; }
    h1 { color: #c00; margin-bottom: 0.2rem; }
    h2 { margin-top: 1.5rem; border-bottom: 2px solid #c00; padding-bottom: 4px; }
    p { margin: 0.4rem 0 0.8rem; color: #555; font-size: 0.9rem; }
    a { color: #c00; text-decoration: none; }
    a:hover { text-decoration: underline; }
    .meta { font-size: 0.8rem; color: #888; margin-top: 0.2rem; }
    .back { font-size: 0.85rem; margin-bottom: 1rem; display: block; }
    table { border-collapse: collapse; width: 100%; margin-top: 0.5rem; }
    th { background: #444; color: #fff; text-align: left; padding: 6px 10px; font-size: 0.85rem; }
    td { padding: 5px 10px; border-bottom: 1px solid #eee; vertical-align: middle; }
    td.url { font-size: 0.72rem; color: #999; word-break: break-all; max-width: 380px; }
    td.added, td.ignored { font-size: 0.78rem; color: #666; white-space: nowrap; width: 130px; }
    td.reason { font-size: 0.78rem; color: #666; max-width: 220px; }
    td.act { white-space: nowrap; text-align: right; width: 220px; }
    tr:hover td { background: #fff8f8; }
    tr.queued-ignore td { background: #fff6df; }
    tr.queued-restore td { background: #edf8ed; }
    .btn { display: inline-block; padding: 3px 10px; color: #fff !important; border-radius: 3px; font-size: 0.78rem; text-decoration: none !important; white-space: nowrap; border: none; cursor: pointer; font-family: inherit; }
    .btn-open { background: #888; }
    .btn-open:hover { background: #555; }
    .btn-ignore { background: #b26a00; }
    .btn-ignore:hover { background: #8c5300; }
    .btn-restore { background: #2e7d32; }
    .btn-restore:hover { background: #1f5a23; }
    .btn-copy { background: #1e6bb8; }
    .btn-copy:hover { background: #15528e; }
    .btn-download { background: #5c4db1; }
    .btn-download:hover { background: #463a8a; }
    .btn-clear { background: #777; }
    .btn-clear:hover { background: #555; }
    .row-actions { display: flex; gap: 6px; justify-content: flex-end; flex-wrap: wrap; }
    code { background: #f0f0f0; padding: 1px 4px; border-radius: 3px; font-size: 0.85rem; }
    .badge { background: #c00; color: #fff; border-radius: 10px; padding: 1px 8px; font-size: 0.75rem; margin-left: 6px; }
    .index-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 10px; margin-top: 1rem; }
    .index-card { border: 1px solid #ddd; border-radius: 6px; padding: 12px 16px; text-decoration: none !important; color: #222 !important; transition: box-shadow 0.15s; display: block; }
    .index-card:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.15); }
    .index-card .title { font-weight: 600; font-size: 0.95rem; color: #c00; }
    .index-card .count { font-size: 0.82rem; color: #888; margin-top: 4px; }
    .dta-info { background: #e8f0fb; border: 1px solid #1e6bb8; border-radius: 4px; padding: 10px 16px; margin: 1rem 0; font-size: 0.88rem; }
    .dta-info ol { margin: 0.4rem 0 0 1.2rem; padding: 0; line-height: 1.9; }
    .ignore-info { background: #f8efe1; border: 1px solid #c98b2c; border-radius: 4px; padding: 10px 16px; margin: 1rem 0; font-size: 0.88rem; }
    .ignore-info code { background: #fff7ea; }
    .search-panel { background: #f7f7f7; border: 1px solid #d7d7d7; border-radius: 4px; padding: 12px 16px; margin: 1rem 0; }
    .search-input { width: 100%; max-width: 520px; padding: 8px 10px; border: 1px solid #bbb; border-radius: 4px; font-family: inherit; font-size: 0.9rem; }
    .search-results { margin-top: 1rem; }
    .search-results table { margin-top: 0.8rem; }
    .search-results td.title-cell { max-width: 360px; }
    .search-results td.meta-cell { font-size: 0.78rem; color: #666; white-space: nowrap; }
    .search-results td.link-cell { white-space: nowrap; text-align: right; }
    .search-empty { display: none; margin-top: 0.8rem; color: #666; font-size: 0.85rem; }
    .action-panel { background: #f7f7f7; border: 1px solid #d7d7d7; border-radius: 4px; padding: 12px 16px; margin: 1rem 0; }
    .action-toolbar { display: flex; gap: 8px; align-items: center; flex-wrap: wrap; margin-bottom: 0.8rem; }
    .action-textarea { width: 100%; min-height: 140px; font-family: Consolas, monospace; font-size: 0.82rem; padding: 10px; border: 1px solid #ccc; border-radius: 4px; resize: vertical; }
    .muted { font-size: 0.8rem; color: #666; }
    """

    def _sort_key(item: dict, primary_field: str) -> tuple[int, int, str]:
        primary_raw = item.get(primary_field) or item.get("added") or ""
        if primary_raw:
            try:
                primary_num = int(datetime.strptime(primary_raw, "%Y-%m-%d %H:%M").strftime("%Y%m%d%H%M"))
                return (0, -primary_num, item["title"].lower())
            except ValueError:
                pass
        url = item["url"]
        id_match = re.search(r"/discussion/(\d+)", url) or re.search(r"[?&]pageId=(\d+)", url) or re.search(r"/x/([A-Za-z0-9]+)$", url)
        if id_match:
            raw = id_match.group(1)
            try:
                numeric_id = int(raw, 36)
                return (1, -numeric_id, item["title"].lower())
            except Exception:
                pass
        ym_match = re.search(r"(20\d{2})[- /](0?[1-9]|1[0-2])", item["title"])
        if ym_match:
            year = int(ym_match.group(1))
            month = int(ym_match.group(2))
            return (2, -(year * 100 + month), item["title"].lower())
        return (3, 0, item["title"].lower())

    def _write_subpage(filename: str, title: str, items: list[dict], subtitle: str = "", group_url: str = "", ignored: bool = False) -> None:
        rows = ""
        primary_field = "ignored_at" if ignored else "added"
        action_name = "unignore" if ignored else "ignore"
        action_label = "Queue Restore" if ignored else "Queue Ignore"
        action_class = "btn-restore" if ignored else "btn-ignore"
        for item in sorted(items, key=lambda current: _sort_key(current, primary_field)):
            title_html = html.escape(item["title"], quote=True)
            url_html = html.escape(item["url"], quote=True)
            added_html = html.escape(item.get("added", ""), quote=True)
            ignored_html = html.escape(item.get("ignored_at", ""), quote=True)
            reason_html = html.escape(item.get("reason", ""), quote=True)
            action_js = html.escape(json.dumps(action_name), quote=True)
            url_js = html.escape(json.dumps(item["url"]), quote=True)
            title_js = html.escape(json.dumps(item["title"]), quote=True)
            rows += f'    <tr data-url="{url_html}">\n'
            rows += f'      <td><a href="{url_html}" target="_blank" rel="noopener">{title_html}</a></td>\n'
            rows += f'      <td class="url">{url_html}</td>\n'
            rows += f'      <td class="added">{added_html}</td>\n'
            if ignored:
                rows += f'      <td class="ignored">{ignored_html}</td>\n'
                rows += f'      <td class="reason">{reason_html}</td>\n'
            rows += (
                '      <td class="act"><div class="row-actions">'
                f'<a class="btn btn-open" href="{url_html}" target="_blank" rel="noopener">&#8599; Open</a>'
                f'<button type="button" class="btn {action_class}" onclick=\'queueLinkAction(this, {action_js}, {url_js}, {title_js})\'>{action_label}</button>'
                '</div></td>\n'
            )
            rows += '    </tr>\n'
        group_link = f' &nbsp;<a href="{html.escape(group_url, quote=True)}" target="_blank" rel="noopener" style="font-size:0.82rem">&#8599; Group page</a>' if group_url else ""
        ignore_cols = '<th>Ignored</th><th>Reason</th>' if ignored else ''
        page = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>{html.escape(title, quote=True)}</title>
  <style>{SHARED_CSS}</style>
</head>
<body>
  <a class="back" href="../../../{root_index_href}">&larr; Back to index</a>
  <h1>{html.escape(title)}{group_link}</h1>
  <p class="meta">{len(items)} page(s){(' &mdash; ' + html.escape(subtitle)) if subtitle else ''} &nbsp;|&nbsp; Generated: {now}</p>
  <div class="dta-info">
<strong>DownThemAll! (Firefox):</strong> right-click this page &rarr; DownThemAll &rarr;
Links tab &rarr; set folder to <code>{downloads_dir_display}</code> &rarr; Start
  </div>
  <div class="ignore-info">
<strong>{'Restore' if ignored else 'Ignore'} workflow:</strong>
this page is static HTML, so the buttons below queue PowerShell commands instead of editing the JSON directly.
Click the button for each link, then <strong>Copy commands</strong> or <strong>Download .ps1</strong>, run the commands, and re-run the scraper.
  </div>
  <div class="search-panel">
<input id="page-search" class="search-input" type="search" placeholder="Search this page by title or URL" oninput="filterPageRows()">
<div id="search-status" class="muted" style="margin-top: 0.5rem;">Showing all {len(items)} page(s).</div>
  </div>
  <div class="action-panel">
<div class="action-toolbar">
  <button type="button" class="btn btn-copy" onclick="copyPendingCommands()">Copy commands</button>
  <button type="button" class="btn btn-download" onclick="downloadPendingCommands()">Download .ps1</button>
  <button type="button" class="btn btn-clear" onclick="clearPendingCommands()">Clear queue</button>
  <span id="pending-status" class="muted">No commands queued yet.</span>
</div>
<textarea id="pending-commands" class="action-textarea" readonly placeholder="Queued commands will appear here."></textarea>
<div class="muted">Command target: <code>{python_display}</code> <code>{manage_script_display}</code></div>
  </div>
  <table>
<thead><tr><th>Page</th><th>URL</th><th>First Seen</th>{ignore_cols}<th></th></tr></thead>
<tbody>
{rows}    </tbody>
  </table>
  <script>
var commandPython = {command_python_js};
var manageScript = {manage_script_js};
var pendingCommands = [];

function psQuote(value) {{
  return "'" + String(value == null ? '' : value).replace(/'/g, "''") + "'";
}}

function setStatus(message) {{
  document.getElementById('pending-status').textContent = message;
}}

function renderCommands() {{
  var textarea = document.getElementById('pending-commands');
  textarea.value = pendingCommands.map(function(entry) {{ return entry.command; }}).join('\\r\\n');
  if (pendingCommands.length) {{
    setStatus(pendingCommands.length + ' command(s) queued.');
  }} else {{
    setStatus('No commands queued yet.');
  }}
}}

function queueLinkAction(button, action, url, title) {{
  var reason = action === 'ignore' ? 'ignored from missing pages UI' : '';
  var base = '& ' + psQuote(commandPython) + ' ' + psQuote(manageScript) + ' ' + action + ' ' + psQuote(url);
  var command = action === 'ignore' ? base + ' --reason ' + psQuote(reason) : base;
  pendingCommands = pendingCommands.filter(function(entry) {{ return entry.url !== url; }});
  pendingCommands.push({{ action: action, url: url, title: title, reason: reason, command: command }});
  var row = button.closest('tr');
  if (row) {{
    row.classList.remove('queued-ignore', 'queued-restore');
    row.classList.add(action === 'ignore' ? 'queued-ignore' : 'queued-restore');
  }}
  renderCommands();
}}

function copyPendingCommands() {{
  var textarea = document.getElementById('pending-commands');
  if (!textarea.value.trim()) {{
    return;
  }}
  textarea.focus();
  textarea.select();
  textarea.setSelectionRange(0, textarea.value.length);
  if (navigator.clipboard && window.isSecureContext) {{
    navigator.clipboard.writeText(textarea.value).then(function() {{ setStatus('Commands copied to clipboard.'); }}).catch(function() {{
      document.execCommand('copy');
      setStatus('Commands copied to clipboard.');
    }});
    return;
  }}
  document.execCommand('copy');
  setStatus('Commands copied to clipboard.');
}}

function downloadPendingCommands() {{
  var textarea = document.getElementById('pending-commands');
  if (!textarea.value.trim()) {{
    return;
  }}
  var blob = new Blob([textarea.value + '\\r\\n'], {{ type: 'text/plain;charset=utf-8' }});
  var link = document.createElement('a');
  var href = URL.createObjectURL(blob);
  link.href = href;
  link.download = 'missing_pages_actions.ps1';
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(href);
  setStatus('PowerShell script downloaded.');
}}

function clearPendingCommands() {{
  pendingCommands = [];
  Array.prototype.forEach.call(document.querySelectorAll('tr.queued-ignore, tr.queued-restore'), function(row) {{
    row.classList.remove('queued-ignore', 'queued-restore');
  }});
  renderCommands();
}}

function filterPageRows() {{
  var input = document.getElementById('page-search');
  var query = ((input && input.value) || '').trim().toLowerCase();
  var rows = document.querySelectorAll('tbody tr');
  var visibleCount = 0;
  Array.prototype.forEach.call(rows, function(row) {{
    var text = row.textContent.toLowerCase();
    var matches = !query || text.indexOf(query) !== -1;
    row.style.display = matches ? '' : 'none';
    if (matches) {{
      visibleCount += 1;
    }}
  }});
  var status = document.getElementById('search-status');
  if (status) {{
    status.textContent = query
      ? 'Showing ' + visibleCount + ' of ' + rows.length + ' page(s).'
      : 'Showing all ' + rows.length + ' page(s).';
  }}
}}

renderCommands();
  </script>
</body>
</html>"""
        (out_dir / filename).write_text(page, encoding="utf-8")

    sections_meta: list[dict] = []
    root_search_items: list[dict] = []
    for cat in ordered_wiki_cats:
        active_items = active_wiki_by_cat.get(cat, [])
        ignored_items = ignored_wiki_by_cat.get(cat, [])
        cat_slug = re.sub(r'\W+', '-', cat.lower()).strip('-')
        if active_items:
            fname = f"{cat_slug}.html"
            _write_subpage(fname, cat, active_items, subtitle="Cerner Wiki")
            sections_meta.append({"title": cat, "file": fname, "count": len(active_items), "type": "wiki"})
            for item in active_items:
                root_search_items.append({
                    "title": item["title"],
                    "url": item["url"],
                    "bucket": cat,
                    "kind": "Cerner Wiki",
                    "status": "Active",
                    "section_file": fname,
                    "section_title": cat,
                })
        if ignored_items:
            fname = f"ignored-{cat_slug}.html"
            _write_subpage(fname, f"Ignored - {cat}", ignored_items, subtitle="Cerner Wiki", ignored=True)
            sections_meta.append({"title": cat, "file": fname, "count": len(ignored_items), "type": "wiki-ignored"})
            for item in ignored_items:
                root_search_items.append({
                    "title": item["title"],
                    "url": item["url"],
                    "bucket": cat,
                    "kind": "Cerner Wiki",
                    "status": "Ignored",
                    "section_file": fname,
                    "section_title": f"Ignored - {cat}",
                })

    for gname in ordered_forum_cats:
        active_items = active_forum_by_group.get(gname, [])
        ignored_items = ignored_forum_by_group.get(gname, [])
        group_slug = re.sub(r'\W+', '-', gname.lower()).strip('-')
        if active_items:
            fname = f"forum-{group_slug}.html"
            _write_subpage(fname, gname, active_items, subtitle="Oracle Health Community", group_url=group_page_urls.get(gname, ""))
            sections_meta.append({"title": gname, "file": fname, "count": len(active_items), "type": "forum"})
            for item in active_items:
                root_search_items.append({
                    "title": item["title"],
                    "url": item["url"],
                    "bucket": gname,
                    "kind": "Oracle Health Community",
                    "status": "Active",
                    "section_file": fname,
                    "section_title": gname,
                })
        if ignored_items:
            fname = f"ignored-forum-{group_slug}.html"
            _write_subpage(fname, f"Ignored - {gname}", ignored_items, subtitle="Oracle Health Community", group_url=group_page_urls.get(gname, ""), ignored=True)
            sections_meta.append({"title": gname, "file": fname, "count": len(ignored_items), "type": "forum-ignored"})
            for item in ignored_items:
                root_search_items.append({
                    "title": item["title"],
                    "url": item["url"],
                    "bucket": gname,
                    "kind": "Oracle Health Community",
                    "status": "Ignored",
                    "section_file": fname,
                    "section_title": f"Ignored - {gname}",
                })

    def cards(section_type: str) -> str:
        html_cards = ""
        for section in sections_meta:
            if section["type"] != section_type:
                continue
            title_html = html.escape(section["title"], quote=True)
            html_cards += (
                f'<a class="index-card" href="{subpages_href_prefix}/{section["file"]}">'
                f'<div class="title">{title_html}</div><div class="count">{section["count"]} page(s)</div></a>\n'
            )
        return html_cards

    wiki_cards = cards("wiki")
    forum_cards = cards("forum")
    ignored_wiki_cards = cards("wiki-ignored")
    ignored_forum_cards = cards("forum-ignored")

    wiki_section = f"""  <h2>Cerner Wiki Pages <span class="badge">{total_wiki}</span></h2>
  <p>Pages referenced by downloaded content but not yet downloaded. Links inside each category are sorted with newly discovered pages first.</p>
  <div class="index-grid">
{wiki_cards}  </div>""" if wiki_cards else ""
    forum_section = f"""  <h2>Oracle Health Community Posts <span class="badge">{total_forum}</span></h2>
  <p>Referenced forum posts that are not yet downloaded. Links inside each group are sorted with newly discovered pages first.</p>
  <div class="index-grid">
{forum_cards}  </div>""" if forum_cards else ""
    ignored_wiki_section = f"""  <h2>Ignored Cerner Wiki Pages <span class="badge">{total_ignored_wiki}</span></h2>
  <p>Ignored links stay grouped by the same category so they can be revisited later.</p>
  <div class="index-grid">
{ignored_wiki_cards}  </div>""" if ignored_wiki_cards else ""
    ignored_forum_section = f"""  <h2>Ignored Oracle Health Community Posts <span class="badge">{total_ignored_forum}</span></h2>
  <p>Ignored forum links stay grouped by the same community group so they can be restored later if needed.</p>
  <div class="index-grid">
{ignored_forum_cards}  </div>""" if ignored_forum_cards else ""
    root_search_items_json = html.escape(json.dumps(root_search_items), quote=False)

    index_html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Missing Pages &mdash; {now}</title>
  <style>{SHARED_CSS}</style>
</head>
<body>
  <h1>MPages Scraper &mdash; Missing Pages</h1>
  <p class="meta">Generated: {now} &nbsp;|&nbsp; {total_wiki} wiki missing &nbsp;|&nbsp; {total_forum} forum posts &nbsp;|&nbsp; {total_ignored_wiki + total_ignored_forum} ignored</p>
  <div class="dta-info">
<strong>How to use:</strong>
<ol>
  <li>Open Firefox and log into wiki.cerner.com / community.oracle.com.</li>
  <li>Click a category card below to open its subpage.</li>
  <li>On the subpage: right-click &rarr; <strong>DownThemAll!</strong> &rarr; Links tab &rarr; set folder to <code>{downloads_dir_display}</code> &rarr; <strong>Start</strong>.</li>
  <li>Use <strong>Queue Ignore</strong> or <strong>Queue Restore</strong> on the subpage if you want the next run to move a link into or out of the ignored sections.</li>
  <li>Move downloaded files into <code>{downloads_dir_display}</code> and re-run the scraper.</li>
</ol>
  </div>
  <div class="ignore-info">
<strong>Ignore workflow:</strong>
category pages now include <strong>Queue Ignore</strong> and <strong>Queue Restore</strong> buttons.
Because this report is static HTML, those buttons build PowerShell commands for you to copy or download and run against <code>{manage_script_display}</code>.
  </div>
  <div class="search-panel">
<input id="index-search" class="search-input" type="search" placeholder="Search missing page names across all categories" oninput="filterIndexEntries()">
<div id="index-search-status" class="muted" style="margin-top: 0.5rem;">Search across {len(root_search_items)} missing page(s).</div>
<div id="index-search-empty" class="search-empty">No matching page titles.</div>
<div id="index-search-results" class="search-results" style="display:none;">
  <table>
    <thead><tr><th>Page</th><th>Category</th><th>Source</th><th>Status</th><th></th></tr></thead>
    <tbody id="index-search-results-body"></tbody>
  </table>
  <div class="muted" style="margin-top:0.5rem;">Results open the original page directly. Use <strong>Category Page</strong> to jump to the grouped report page.</div>
  </div>
  </div>
{wiki_section}
{forum_section}
{ignored_wiki_section}
{ignored_forum_section}
  <script>
var rootSearchItems = {root_search_items_json};

function escapeHtml(value) {{
  return String(value || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}}

function renderIndexResults(matches) {{
  var body = document.getElementById('index-search-results-body');
  var wrapper = document.getElementById('index-search-results');
  var empty = document.getElementById('index-search-empty');
  if (!body || !wrapper || !empty) {{
    return;
  }}
  if (!matches.length) {{
    body.innerHTML = '';
    wrapper.style.display = 'none';
    empty.style.display = '';
    return;
  }}
  var rows = [];
  for (var i = 0; i < matches.length; i += 1) {{
    var item = matches[i];
    rows.push(
      '<tr>' +
      '<td class="title-cell"><a href="' + escapeHtml(item.url) + '" target="_blank" rel="noopener">' + escapeHtml(item.title) + '</a></td>' +
      '<td class="meta-cell">' + escapeHtml(item.bucket) + '</td>' +
      '<td class="meta-cell">' + escapeHtml(item.kind) + '</td>' +
      '<td class="meta-cell">' + escapeHtml(item.status) + '</td>' +
      '<td class="link-cell"><a class="btn btn-open" href="{subpages_href_prefix}/' + escapeHtml(item.section_file) + '">Category Page</a></td>' +
      '</tr>'
    );
  }}
  body.innerHTML = rows.join('');
  wrapper.style.display = '';
  empty.style.display = 'none';
}}

function filterIndexEntries() {{
  var input = document.getElementById('index-search');
  var query = ((input && input.value) || '').trim().toLowerCase();
  var cards = document.querySelectorAll('.index-card');
  var status = document.getElementById('index-search-status');
  if (!query) {{
    Array.prototype.forEach.call(cards, function(card) {{
      card.style.display = '';
    }});
    renderIndexResults([]);
    if (status) {{
      status.textContent = 'Search across ' + rootSearchItems.length + ' missing page(s).';
    }}
    return;
  }}

  var matches = [];
  for (var i = 0; i < rootSearchItems.length; i += 1) {{
    var item = rootSearchItems[i];
    var haystack = (item.title + ' ' + item.bucket + ' ' + item.kind + ' ' + item.status).toLowerCase();
    if (haystack.indexOf(query) !== -1) {{
      matches.push(item);
    }}
  }}
  matches.sort(function(a, b) {{
    return a.title.toLowerCase() < b.title.toLowerCase() ? -1 : a.title.toLowerCase() > b.title.toLowerCase() ? 1 : 0;
  }});
  Array.prototype.forEach.call(cards, function(card) {{
    card.style.display = 'none';
  }});
  renderIndexResults(matches.slice(0, 250));
  if (status) {{
    status.textContent = 'Showing ' + matches.length + ' matching page(s).' + (matches.length > 250 ? ' Displaying first 250.' : '');
  }}
}}
  </script>
</body>
</html>"""
    ROOT_MISSING_OUTPUT.write_text(index_html, encoding="utf-8")


def print_corpus_summary() -> None:
    jsonl_path = Path(DOCUMENTS_OUTPUT)
    if not jsonl_path.exists(): return

    import jsonlines as _jl
    from collections import defaultdict
    with _jl.open(jsonl_path) as reader: records = list(reader)
    if not records: return

    seen_files: set[str] = set()
    files: list[dict] = []
    for r in records:
        if r["source_file"] not in seen_files:
            seen_files.add(r["source_file"])
            files.append(r)

    wiki_files   = [r for r in files if r.get("platform") == "wiki"]
    forum_files  = [r for r in files if r.get("platform") == "forum"]
    other_files  = [r for r in files if r.get("platform") not in ("wiki", "forum")]

    log.info("=" * 60)
    log.info(f"CORPUS SUMMARY  ({len(files)} downloaded files)")
    log.info("=" * 60)

    SUFFIX_TO_SPACE = {"MPages Development Wiki - Cerner Wiki": "mpdevwiki", "Reference Pages - Cerner Wiki": "reference", "Bedrock Help Pages - Cerner Wiki": "bedrockHP", "Discern Help Pages - Cerner Wiki": "1101discernHP", "CernerWorks Reference Pages - Cerner Wiki": "cernerworksrp", "Cerner Wiki": "help"}

    wiki_by_cat: defaultdict[str, int] = defaultdict(int)
    for r in wiki_files:
        url = r.get("canonical_url", "")
        if url: cat = _categorise_wiki(_wiki_url_to_title(url) or "", url)
        else:
            fname, space = r["source_file"], "reference"
            for suffix, sp in SUFFIX_TO_SPACE.items():
                if suffix.lower() in fname.lower(): space = sp; break
            cat = _categorise_wiki(_filename_to_title(fname), f"https://wiki.cerner.com/display/{space}/{_filename_to_title(fname).replace(' ', '+')}")
        wiki_by_cat[cat] += 1

    CATEGORY_ORDER = ["MPages Configuration", "MPages Development", "MPages Worklists & Organizers", "Bedrock", "Platform Admin", "Platform Help", "Clinical Applications", "HealtheIntent & Care Management", "Other"]
    log.info(f"\n  Cerner Wiki  ({len(wiki_files)} files)")
    for cat in sorted(wiki_by_cat.keys(), key=lambda c: CATEGORY_ORDER.index(c) if c in CATEGORY_ORDER else 99): log.info(f"    {wiki_by_cat[cat]:4d}  {cat}")

    forum_by_group: defaultdict[str, int] = defaultdict(int)
    for r in forum_files:
        group_name = r.get("group_name") or "Other (group unknown)"
        if group_name.startswith("http"):
            group_name = _friendly_slug_title(group_name)
        forum_by_group[group_name] += 1

    log.info(f"\n  Oracle Health Community  ({len(forum_files)} files)")
    for gname in sorted(forum_by_group.keys(), key=lambda g: ("other" in g.lower(), g.lower())): log.info(f"    {forum_by_group[gname]:4d}  {gname}")

    if other_files:
        log.info(f"\n  Other / unknown platform  ({len(other_files)} files)")
        for r in other_files: log.info(f"         {r['source_file']}")
    log.info("=" * 60)

# ── Downloaded Pages Report ───────────────────────────────────────────────────

DOWNLOADED_OUTPUT = ROOT_DOWNLOADED_OUTPUT

def generate_downloaded_report() -> None:
    jsonl_path = Path(DOCUMENTS_OUTPUT)
    if not jsonl_path.exists():
        return

    import jsonlines as _jl
    from collections import Counter
    from datetime import datetime
    
    with _jl.open(jsonl_path) as reader:
        records = list(reader)
    if not records:
        return

    seen_files: set[str] = set()
    files: list[dict] = []
    for r in records:
        if r["source_file"] not in seen_files:
            seen_files.add(r["source_file"])
            files.append(r)

    TITLE_SUFFIX_RE = re.compile(
        r'\s*[-–—]+\s*(?:Help Pages\s*[-–—]+\s*)?'
        r'(?:MPages Development Wiki|Reference Pages|Bedrock Help Pages|'
        r'Discern Help Pages|CernerWorks Reference Pages|Cerner Wiki|Oracle Health)'
        r'\s*(?:[-–—]+\s*Cerner Wiki)?\s*$',
        re.IGNORECASE,
    )

    def _forum_group(r: dict) -> tuple[str, str]:
        if r.get("group_name"): return r["group_name"], r.get("canonical_url", "")
        if r.get("canonical_url"):
            ginfo = GROUP_METADATA.get(r["canonical_url"].rstrip("/"), {})
            if ginfo: return ginfo["group_name"], r["canonical_url"]
        slug = re.sub(r'\s*[—–-]+\s*Oracle Health\.html?$', '', r["source_file"], flags=re.IGNORECASE).strip().lower()
        for url, ginfo in GROUP_METADATA.items():
            url_slug = re.sub(r'^\d+[-\s]*', '', url.split('/')[-1].replace('-', ' ')).lower()
            if url_slug and len(url_slug) > 8 and (url_slug in slug or slug.startswith(url_slug[:25])):
                return ginfo.get("group_name", "Unknown"), url
        return "Unknown", ""

    rows: list[dict] = []
    for r in files:
        platform = r.get("platform", "unknown")
        title = TITLE_SUFFIX_RE.sub("", r.get("title", r["source_file"])).strip()
        
        if platform == "wiki":
            canon = r.get("canonical_url", "")
            space = "reference"
            for suffix, sp in {"MPages Development Wiki - Cerner Wiki": "mpdevwiki", "Reference Pages - Cerner Wiki": "reference", "Bedrock Help Pages - Cerner Wiki": "bedrockHP", "Discern Help Pages - Cerner Wiki": "1101discernHP", "CernerWorks Reference Pages - Cerner Wiki": "cernerworksrp", "Cerner Wiki": "help"}.items():
                if suffix.lower() in r["source_file"].lower():
                    space = sp
                    break
            if not canon:
                canon = f"https://wiki.cerner.com/display/{space}/{quote(title.replace(' ', '+'), safe='+')}"
            category, group, url_display = _categorise_wiki(title.lower(), canon), "", canon
        elif platform == "forum":
            group, canon = _forum_group(r)
            category, url_display = "", canon
        else:
            category, group, url_display = "Unknown", "", r.get("canonical_url", "")

        rows.append({
            "title": title, "url": url_display, "platform": platform, 
            "category": category, "group": group, "chunks": r.get("total_chunks", 1), 
            "source_file": r["source_file"]
        })

    rows.sort(key=lambda x: ({"wiki": 0, "forum": 1}.get(x["platform"], 2), x["category"] or x["group"], x["title"].lower()))

    wiki_rows  = [r for r in rows if r["platform"] == "wiki"]
    forum_rows = [r for r in rows if r["platform"] == "forum"]
    wiki_by_cat  = Counter(r["category"] for r in wiki_rows)
    forum_by_grp = Counter(r["group"] for r in forum_rows)
    CATEGORY_ORDER = ["MPages Configuration", "MPages Development", "MPages Worklists & Organizers", "Bedrock", "Platform Admin", "Platform Help", "Clinical Applications", "HealtheIntent & Care Management", "Other"]

    def _tr(r: dict) -> str:
        url = r["url"]
        url_cell = f'<a href="{url}" target="_blank">{url}</a>' if url else '<span class="no-url">—</span>'
        tag_val = r["category"] or r["group"] or "Unknown"
        tag_class = tag_val.lower()
        platform_label = {"wiki": "Wiki", "forum": "Forum"}.get(r["platform"], r["platform"].title())
        return (
            f'<tr data-platform="{r["platform"]}" data-tag="{tag_class}">\n'
            f'  <td class="title-cell">{r["title"]}</td>\n'
            f'  <td class="url-cell">{url_cell}</td>\n'
            f'  <td class="plat-cell plat-{r["platform"]}">{platform_label}</td>\n'
            f'  <td class="cat-cell">{tag_val}</td>\n'
            f'  <td class="num-cell">{r["chunks"]}</td>\n'
            f'</tr>\n'
        )

    table_rows = "".join(_tr(r) for r in rows)

    html_cards = (
        f'<div class="sum-card" onclick="filterPlatform(\'wiki\')"><div class="sum-num">{len(wiki_rows)}</div><div class="sum-label">Wiki pages</div></div>\n'
        f'<div class="sum-card" onclick="filterPlatform(\'forum\')"><div class="sum-num">{len(forum_rows)}</div><div class="sum-label">Forum posts</div></div>\n'
        f'<div class="sum-card" onclick="clearFilters()"><div class="sum-num">{len(rows)}</div><div class="sum-label">Total files</div></div>\n'
    )

    html_chips = '<div class="chips">\n<span class="chip chip-all active" onclick="clearFilters()">All</span>\n'
    ordered_cats = sorted(wiki_by_cat.keys(), key=lambda c: CATEGORY_ORDER.index(c) if c in CATEGORY_ORDER else 99)
    for cat in ordered_cats:
        html_chips += f'<span class="chip chip-wiki" onclick="filterTag(\'{cat}\')">{cat} <b>{wiki_by_cat[cat]}</b></span>\n'
    for grp in sorted(forum_by_grp.keys(), key=lambda g: ("unknown" in g.lower(), g.lower())):
        html_chips += f'<span class="chip chip-forum" onclick="filterTag(\'{grp}\')">{grp} <b>{forum_by_grp[grp]}</b></span>\n'
    html_chips += '</div>\n'

    now = datetime.now().strftime("%Y-%m-%d %H:%M")
    total_chunks = sum(r["chunks"] for r in rows)

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Downloaded Pages &mdash; {now}</title>
  <style>
    * {{ box-sizing: border-box; }}
    body {{ font-family: Segoe UI, Arial, sans-serif; margin: 0; color: #222; background: #f8f8f8; }}
    header {{ background: #c00; color: #fff; padding: 1rem 2rem 0.8rem; }}
    header h1 {{ margin: 0; font-size: 1.4rem; }}
    header p  {{ margin: 0.2rem 0 0; font-size: 0.82rem; opacity: 0.85; }}
    .content {{ padding: 1.2rem 2rem; max-width: 1400px; margin: 0 auto; }}
    .summary {{ display: flex; gap: 12px; margin-bottom: 1rem; flex-wrap: wrap; }}
    .sum-card {{ background: #fff; border: 1px solid #ddd; border-radius: 6px; padding: 10px 20px; cursor: pointer; transition: box-shadow 0.15s; text-align: center; }}
    .sum-card:hover {{ box-shadow: 0 2px 8px rgba(0,0,0,0.12); }}
    .sum-num   {{ font-size: 1.6rem; font-weight: 700; color: #c00; line-height: 1; }}
    .sum-label {{ font-size: 0.78rem; color: #888; margin-top: 3px; }}
    .chips {{ display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 1rem; align-items: center; }}
    .chip {{ display: inline-block; padding: 3px 10px; border-radius: 12px; font-size: 0.78rem; cursor: pointer; border: 1px solid #ccc; background: #fff; user-select: none; transition: 0.1s; }}
    .chip:hover {{ border-color: #888; }}
    .chip.active {{ background: #c00; color: #fff; border-color: #c00; }}
    .chip b {{ font-weight: 700; }}
    .chip-wiki  {{ border-color: #1e6bb8; color: #1e4a80; }}
    .chip-wiki.active  {{ background: #1e6bb8; color: #fff; border-color: #1e6bb8; }}
    .chip-forum {{ border-color: #2e7d32; color: #1b5e20; }}
    .chip-forum.active {{ background: #2e7d32; color: #fff; border-color: #2e7d32; }}
    .toolbar {{ display: flex; gap: 10px; margin-bottom: 0.8rem; align-items: center; flex-wrap: wrap; }}
    #search {{ padding: 6px 10px; border: 1px solid #ccc; border-radius: 4px; font-size: 0.88rem; width: 280px; font-family: inherit; }}
    #search:focus {{ outline: none; border-color: #888; }}
    .count-label {{ font-size: 0.82rem; color: #888; margin-left: auto; }}
    table {{ border-collapse: collapse; width: 100%; background: #fff; border: 1px solid #e0e0e0; border-radius: 6px; overflow: hidden; font-size: 0.85rem; }}
    th {{ background: #333; color: #fff; text-align: left; padding: 8px 12px; cursor: pointer; user-select: none; white-space: nowrap; }}
    th:hover {{ background: #555; }}
    th.sorted-asc::after  {{ content: " ▲"; font-size: 0.7em; }}
    th.sorted-desc::after {{ content: " ▼"; font-size: 0.7em; }}
    td {{ padding: 6px 12px; border-bottom: 1px solid #f0f0f0; vertical-align: middle; }}
    tr:last-child td {{ border-bottom: none; }}
    tr:hover td {{ background: #fafafa; }}
    tr.hidden {{ display: none; }}
    .title-cell {{ font-weight: 500; max-width: 340px; }}
    .url-cell   {{ font-size: 0.75rem; color: #777; word-break: break-all; max-width: 360px; }}
    .url-cell a {{ color: #1e6bb8; text-decoration: none; }}
    .url-cell a:hover {{ text-decoration: underline; }}
    .no-url     {{ color: #bbb; font-style: italic; }}
    .plat-cell  {{ white-space: nowrap; font-size: 0.78rem; font-weight: 600; padding: 4px 8px; border-radius: 3px; width: 60px; text-align: center; }}
    .plat-wiki  {{ color: #1e4a80; background: #e8f0fb; }}
    .plat-forum {{ color: #1b5e20; background: #e8f5e9; }}
    .plat-unknown {{ color: #666; background: #f0f0f0; }}
    .cat-cell   {{ font-size: 0.8rem; color: #555; max-width: 200px; }}
    .num-cell   {{ text-align: right; color: #999; font-size: 0.78rem; width: 60px; }}
  </style>
</head>
<body>
<header>
  <h1>MPages Scraper &mdash; Downloaded Pages</h1>
  <p>Generated: {now} &nbsp;|&nbsp; {len(rows)} files &nbsp;|&nbsp; {total_chunks} chunks</p>
</header>
<div class="content">

  <div class="summary">
{html_cards}  </div>

{html_chips}

  <div class="toolbar">
    <input id="search" type="text" placeholder="Search titles, URLs, categories..." oninput="applyFilters()">
    <span class="count-label" id="count-label">{len(rows)} of {len(rows)} files</span>
  </div>

  <table id="main-table">
    <thead>
      <tr>
        <th onclick="sortTable(0)">Title</th>
        <th onclick="sortTable(1)">URL</th>
        <th onclick="sortTable(2)">Source</th>
        <th onclick="sortTable(3)">Category / Group</th>
        <th onclick="sortTable(4)" title="Chunks">Cks</th>
      </tr>
    </thead>
    <tbody id="tbody">
{table_rows}    </tbody>
  </table>
</div>

<script>
  let activeChip   = null;
  let activePlat   = null;
  let sortCol      = -1;
  let sortDir      = 1;
  const totalRows  = {len(rows)};

  function applyFilters() {{
    const q     = document.getElementById('search').value.toLowerCase();
    const tbody = document.getElementById('tbody');
    let vis = 0;
    for (const tr of tbody.rows) {{
      const text    = tr.textContent.toLowerCase();
      const plat    = tr.dataset.platform;
      const tag     = tr.dataset.tag;
      const matchQ  = !q || text.includes(q);
      const matchP  = !activePlat || plat === activePlat;
      const matchC  = !activeChip || tag === activeChip.toLowerCase();
      const show    = matchQ && matchP && matchC;
      tr.classList.toggle('hidden', !show);
      if (show) vis++;
    }}
    document.getElementById('count-label').textContent = vis + ' of ' + totalRows + ' files';
  }}

  function setActiveChipEl(el) {{
    document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
    if (el) el.classList.add('active');
  }}

  function clearFilters() {{
    activeChip = null; activePlat = null;
    setActiveChipEl(document.querySelector('.chip-all'));
    applyFilters();
  }}

  function filterPlatform(plat) {{
    activePlat = plat; activeChip = null;
    document.querySelectorAll('.chip').forEach(c => c.classList.remove('active'));
    applyFilters();
  }}

  function filterTag(tag) {{
    activeChip = tag; activePlat = null;
    applyFilters();
  }}

  function sortTable(col) {{
    const tbody = document.getElementById('tbody');
    const rows  = Array.from(tbody.rows);
    if (sortCol === col) sortDir *= -1; else {{ sortCol = col; sortDir = 1; }}
    document.querySelectorAll('th').forEach((th, i) => {{
      th.classList.remove('sorted-asc','sorted-desc');
      if (i === col) th.classList.add(sortDir === 1 ? 'sorted-asc' : 'sorted-desc');
    }});
    rows.sort((a, b) => {{
      const at = a.cells[col]?.textContent.trim().toLowerCase() || '';
      const bt = b.cells[col]?.textContent.trim().toLowerCase() || '';
      return at < bt ? -sortDir : at > bt ? sortDir : 0;
    }});
    rows.forEach(r => tbody.appendChild(r));
  }}
</script>
</body>
</html>"""

    Path(DOWNLOADED_OUTPUT).write_text(html, encoding="utf-8")
    log.info(f"Downloaded pages report: {len(rows)} files -> {DOWNLOADED_OUTPUT}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    global GROUP_METADATA

    for folder in (LOCAL_DOWNLOADS_DIR, GROUP_METADATA_DIR, OUTPUTS_DIR, CORPUS_DIR, REPORTS_DIR, STATE_DIR, LOGS_DIR, TOOLS_DIR):
        if not folder.exists():
            folder.mkdir(parents=True, exist_ok=True)
            log.info(f"Created folder: {folder}")

    GROUP_METADATA = load_group_metadata()
    process_local_directory()
    enrich_jsonl_group_metadata()
    print_corpus_summary()
    generate_downloaded_report()
    generate_discovery_report()
    log.info("Done.")
    log.info(f"  Documents: {DOCUMENTS_OUTPUT}")
    log.info(f"  Chunks: {CHUNKS_OUTPUT}")

if __name__ == "__main__":
    main()
