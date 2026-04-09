"""
Manage ignored missing-page links.

Usage:
    python Outputs/Tools/manage_missing_links.py ignore <url> [--reason "not relevant"]
    python Outputs/Tools/manage_missing_links.py unignore <url>
    python Outputs/Tools/manage_missing_links.py list
"""

import argparse
import json
import re
from datetime import datetime
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parents[2]
STATE_DIR = BASE_DIR / "Outputs" / "State"
IGNORED_LINKS_FILE = STATE_DIR / "ignored_links.json"


def normalize_url(url: str) -> str:
    url = (url or "").strip()
    url = re.sub(r"[#?].*$", "", url).rstrip("/")
    url = re.sub(r"^http://", "https://", url, flags=re.IGNORECASE)
    url = re.sub(
        r"^https://wiki\.cerner\.com/display/public/",
        "https://wiki.cerner.com/display/",
        url,
        flags=re.IGNORECASE,
    )
    return url


def load_state() -> dict[str, dict]:
    if not IGNORED_LINKS_FILE.exists():
        return {}
    loaded = json.loads(IGNORED_LINKS_FILE.read_text(encoding="utf-8"))
    if not isinstance(loaded, dict):
        return {}
    return {normalize_url(url): meta for url, meta in loaded.items() if normalize_url(url)}


def save_state(state: dict[str, dict]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    IGNORED_LINKS_FILE.write_text(json.dumps(dict(sorted(state.items())), indent=2, sort_keys=True), encoding="utf-8")


def ignore_url(url: str, reason: str) -> None:
    state = load_state()
    norm = normalize_url(url)
    if not norm:
        raise SystemExit("URL is required.")
    entry = state.get(norm, {"url": norm})
    entry["url"] = norm
    entry["ignored_at"] = datetime.now().strftime("%Y-%m-%d %H:%M")
    if reason:
        entry["reason"] = reason
    state[norm] = entry
    save_state(state)
    print(f"Ignored: {norm}")


def unignore_url(url: str) -> None:
    state = load_state()
    norm = normalize_url(url)
    if norm in state:
        del state[norm]
        save_state(state)
        print(f"Removed from ignored: {norm}")
    else:
        print(f"Not currently ignored: {norm}")


def list_urls() -> None:
    state = load_state()
    if not state:
        print("No ignored URLs.")
        return
    for url, meta in sorted(state.items(), key=lambda item: item[1].get("ignored_at", ""), reverse=True):
        reason = meta.get("reason", "")
        ignored_at = meta.get("ignored_at", "")
        print(f"{ignored_at}  {url}")
        if reason:
            print(f"  reason: {reason}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Manage ignored missing-page links")
    subparsers = parser.add_subparsers(dest="command", required=True)

    ignore_parser = subparsers.add_parser("ignore", help="Ignore a URL on future missing-page runs")
    ignore_parser.add_argument("url")
    ignore_parser.add_argument("--reason", default="")

    unignore_parser = subparsers.add_parser("unignore", help="Restore a previously ignored URL")
    unignore_parser.add_argument("url")

    subparsers.add_parser("list", help="List currently ignored URLs")

    args = parser.parse_args()
    if args.command == "ignore":
        ignore_url(args.url, args.reason)
    elif args.command == "unignore":
        unignore_url(args.url)
    else:
        list_urls()


if __name__ == "__main__":
    main()
