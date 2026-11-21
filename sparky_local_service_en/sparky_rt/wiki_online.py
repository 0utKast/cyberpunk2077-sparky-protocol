"""Opt-in online Cyberpunk Wiki lookup (STRICTLY DISABLED by default unless explicitly authorized by user)."""

from __future__ import annotations

import json
import re
import sqlite3
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable

from sparky_rt.companion_prefs import USER_BRIDGE_DIR, CompanionPrefs, load_companion_prefs

WIKI_CACHE_PATH = USER_BRIDGE_DIR / "state" / "wiki_cache_en.sqlite"
WIKI_TTL_SECONDS = 7 * 86400

_WALKTHROUGH_TRIGGERS = (
    "how do i", "how to", "how can i", "where is", "where do i find", "where are",
    "stuck", "walkthrough", "guide", "hint", "next step", "step by step",
    "code", "passcode", "door", "quest", "gig", "achievement",
)


def _strip_wikitext(wt: str) -> str:
    if not wt:
        return ""
    out = re.sub(r"\{\{(?:Infobox|Navbox|Quote|Transcript|Spoiler)[^}]*\}\}", " ", wt, flags=re.S | re.I)
    out = re.sub(r"\[\[(?:File|Image|Category):[^\]]+\]\]", " ", out, flags=re.I)
    out = re.sub(r"\[\[([^|\]]+\|)?([^\]]+)\]\]", r"\2", out)
    out = re.sub(r"\{\{[^{}]{1,100}\}\}", " ", out)
    out = re.sub(r"<ref[^>]*>.*?</ref>|<ref[^/>]*/>|<[^>]+>", " ", out, flags=re.S | re.I)
    out = re.sub(r"'{2,}", "", out)
    return re.sub(r"\s+", " ", out).strip()


def _cache_get(cache_path: Path, key: str) -> str | None:
    conn = None
    try:
        conn = sqlite3.connect(cache_path)
        conn.execute(
            "CREATE TABLE IF NOT EXISTS wiki_cache (k TEXT PRIMARY KEY, title TEXT, summary TEXT, ts REAL)"
        )
        row = conn.execute("SELECT summary, ts FROM wiki_cache WHERE k = ?", (key,)).fetchone()
        if row and (time.time() - float(row[1])) < WIKI_TTL_SECONDS:
            return str(row[0])
    except Exception:
        pass
    finally:
        if conn is not None:
            conn.close()
    return None


def _cache_put(cache_path: Path, key: str, title: str, summary: str) -> None:
    conn = None
    try:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(cache_path)
        conn.execute(
            "CREATE TABLE IF NOT EXISTS wiki_cache (k TEXT PRIMARY KEY, title TEXT, summary TEXT, ts REAL)"
        )
        conn.execute(
            "INSERT OR REPLACE INTO wiki_cache (k, title, summary, ts) VALUES (?, ?, ?, ?)",
            (key, title, summary, time.time()),
        )
        conn.commit()
    except Exception:
        pass
    finally:
        if conn is not None:
            conn.close()


def should_query_online(
    player_text: str,
    local_top_score: float,
    tracked_quest_title: str = "",
) -> bool:
    """Decides whether an external Wiki lookup is worthwhile (only after user opt-in)."""
    txt = (player_text or "").strip().lower()
    if len(txt) < 8:
        return False
    explicit_help = any(t in txt for t in _WALKTHROUGH_TRIGGERS)
    weak_local = local_top_score < 0.048
    mentions_quest = bool(tracked_quest_title and len(tracked_quest_title) >= 4 and tracked_quest_title.lower() in txt)
    if explicit_help and (weak_local or mentions_quest):
        return True
    if "?" in txt and local_top_score < 0.028:
        return True
    return False


def _query_fandom_api(base_api_url: str, search_term: str, timeout_s: float = 4.0) -> tuple[str, str]:
    params = urllib.parse.urlencode(
        {"action": "query", "list": "search", "srsearch": search_term, "srlimit": 2, "format": "json"}
    )
    req = urllib.request.Request(
        f"{base_api_url}?{params}",
        headers={"User-Agent": "SparkyProtocolCP2077/2.0"},
    )
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        sr = json.loads(resp.read().decode("utf-8", errors="ignore"))
    hits = (sr.get("query") or {}).get("search") or []
    if not hits:
        return "", ""
    title = str(hits[0]["title"])

    p2 = urllib.parse.urlencode({"action": "parse", "page": title, "prop": "wikitext", "format": "json"})
    req2 = urllib.request.Request(
        f"{base_api_url}?{p2}",
        headers={"User-Agent": "SparkyProtocolCP2077/2.0"},
    )
    with urllib.request.urlopen(req2, timeout=timeout_s) as resp2:
        pdata = json.loads(resp2.read().decode("utf-8", errors="ignore"))
    wt = ((pdata.get("parse") or {}).get("wikitext") or {}).get("*", "")
    if not wt:
        return "", ""

    walk_match = re.search(
        r"==+\s*(?:Walkthrough|Quick walkthrough|Overview)\s*==+(.*?)(?:\n==[^=]|\Z)",
        wt,
        flags=re.S | re.I,
    )
    intro = _strip_wikitext(wt[:1200])[:300]
    if walk_match:
        walk = _strip_wikitext(walk_match.group(1)[:1800])[:520]
        combined = f"{intro} | Walkthrough: {walk}" if intro else walk
    else:
        combined = intro or _strip_wikitext(wt[:1800])[:750]
    return title, combined[:820]


def _build_search_term(player_text: str, tracked_quest_title: str = "") -> str:
    low = (player_text or "").lower()
    if tracked_quest_title and any(
        w in low for w in ("this quest", "this gig", "current mission", "stuck", "next step")
    ):
        return tracked_quest_title.strip()
    cleaned = re.sub(
        r"\b(sparky|chispa|hey|tell|me|how|do|i|can|where|is|are|find|get|pass|beat|about|for|with|please|in|on|the|a|an|cyberpunk|2077|quest|gig|mission)\b",
        " ",
        low,
    )
    cleaned = re.sub(r"[^\w\s'-]", " ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return cleaned if len(cleaned) >= 3 else (tracked_quest_title or player_text).strip()


def lookup_wiki_online(
    player_text: str,
    local_top_score: float,
    tracked_quest_title: str = "",
    *,
    prefs: CompanionPrefs | None = None,
    cache_path: Path = WIKI_CACHE_PATH,
    on_before_network_fetch: Callable[[], None] | None = None,
) -> str:
    """Queries English Cyberpunk Wiki ONLY when prefs.enable_online_wiki is True."""
    cur_prefs = prefs if prefs is not None else load_companion_prefs()
    if not cur_prefs.enable_online_wiki:
        return ""
    if not should_query_online(player_text, local_top_score, tracked_quest_title):
        return ""

    term = _build_search_term(player_text, tracked_quest_title)
    cache_key = f"cp77_en:{term.lower()}"
    cached = _cache_get(cache_path, cache_key)
    if cached is not None:
        return cached

    if on_before_network_fetch is not None:
        try:
            on_before_network_fetch()
        except Exception:
            pass

    title, summary = "", ""
    try:
        title, summary = _query_fandom_api("https://cyberpunk.fandom.com/api.php", term)
        if not summary:
            title, summary = _query_fandom_api("https://cyberpunk.fandom.com/api.php", f"{term} Cyberpunk 2077")
    except Exception:
        return ""

    if not summary:
        return ""
    formatted = f"[EXTERNAL NET ARCHIVE (DO NOT MENTION WIKI OR WEB) — {title}]: {summary}"
    _cache_put(cache_path, cache_key, title, formatted)
    return formatted


def run_self_test() -> None:
    """Verifies zero network calls when enable_online_wiki=False (default) and valid SQLite caching."""
    import tempfile
    from unittest import mock

    with tempfile.TemporaryDirectory(prefix="sparky_wiki_test_") as tmp:
        def_prefs = CompanionPrefs()
        assert def_prefs.enable_online_wiki is False, "Online Wiki lookup must default to False."

        with mock.patch("urllib.request.urlopen") as m_url:
            out = lookup_wiki_online(
                "How do I get past the All Foods plant in The Pickup?",
                local_top_score=0.0,
                tracked_quest_title="The Pickup",
                prefs=def_prefs,
                cache_path=Path(tmp) / "wiki.sqlite",
            )
            assert out == ""
            assert m_url.call_count == 0, "Zero sockets may open when enable_online_wiki=False."

        cache_p = Path(tmp) / "wiki_on.sqlite"
        _cache_put(cache_p, "cp77_en:all foods", "All Foods", "[EXTERNAL NET ARCHIVE] Test entry.")
        on_prefs = CompanionPrefs(enable_online_wiki=True)
        with mock.patch("urllib.request.urlopen") as m_url2:
            cached_out = lookup_wiki_online(
                "Where is All Foods?",
                local_top_score=0.0,
                tracked_quest_title="",
                prefs=on_prefs,
                cache_path=cache_p,
            )
            assert "Test entry" in cached_out
            assert m_url2.call_count == 0
    print("=== WIKI ONLINE GATE (EN) SELF-TEST: OK ===")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Opt-in Online Wiki Gate for S.P.A.R.K.Y. (EN)")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        run_self_test()


if __name__ == "__main__":
    main()
