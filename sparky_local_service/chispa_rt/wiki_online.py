"""Consulta online opcional a Cyberpunk Wiki (DESACTIVADA por defecto hasta permiso explícito del usuario)."""

from __future__ import annotations

import json
import re
import sqlite3
import time
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Callable

from chispa_rt.companion_prefs import USER_BRIDGE_DIR, CompanionPrefs, load_companion_prefs

WIKI_CACHE_PATH = USER_BRIDGE_DIR / "state" / "wiki_cache_es.sqlite"
WIKI_TTL_SECONDS = 7 * 86400

_WALKTHROUGH_TRIGGERS = (
    "como paso", "cómo paso", "como hago", "cómo hago", "como consigo", "cómo consigo",
    "donde esta", "dónde está", "donde encuentro", "dónde encuentro", "donde queda",
    "atascado", "atascada", "pista", "guia", "guía", "siguiente paso", "paso a paso",
    "clave", "codigo", "código", "puerta", "mision", "misión", "encargo", "logro",
)


def _strip_wikitext(wt: str) -> str:
    if not wt:
        return ""
    out = re.sub(r"\{\{(?:Infobox|Navbox|Quote|Transcript|Spoiler)[^}]*\}\}", " ", wt, flags=re.S | re.I)
    out = re.sub(r"\[\[(?:Archivo|File|Image|Categoría|Category):[^\]]+\]\]", " ", out, flags=re.I)
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
    """Decide si merece consultar la Wiki externa (solo si ya está permitido por el usuario)."""
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
        headers={"User-Agent": "ChispaProtocolCP2077/2.0"},
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
        headers={"User-Agent": "ChispaProtocolCP2077/2.0"},
    )
    with urllib.request.urlopen(req2, timeout=timeout_s) as resp2:
        pdata = json.loads(resp2.read().decode("utf-8", errors="ignore"))
    wt = ((pdata.get("parse") or {}).get("wikitext") or {}).get("*", "")
    if not wt:
        return "", ""

    walk_match = re.search(
        r"==+\s*(?:Tutorial|Gu[ií]a|Desarrollo|Walkthrough|Quick walkthrough)\s*==+(.*?)(?:\n==[^=]|\Z)",
        wt,
        flags=re.S | re.I,
    )
    intro = _strip_wikitext(wt[:1200])[:300]
    if walk_match:
        walk = _strip_wikitext(walk_match.group(1)[:1800])[:520]
        combined = f"{intro} | Guía: {walk}" if intro else walk
    else:
        combined = intro or _strip_wikitext(wt[:1800])[:750]
    return title, combined[:820]


def _build_search_term(player_text: str, tracked_quest_title: str = "") -> str:
    low = (player_text or "").lower()
    if tracked_quest_title and any(
        w in low for w in ("esta mision", "esta misión", "mision actual", "misión actual", "atascado", "siguiente paso")
    ):
        return tracked_quest_title.strip()
    cleaned = re.sub(
        r"\b(chispa|sparky|hey|oye|dime|como|cómo|donde|dónde|puedo|hago|esta|está|queda|encuentro|consigo|paso|exactamente|sobre|para|con|por|favor|en|la|el|los|las|una|un|cyberpunk|2077|mision|misión)\b",
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
    """Consulta Cyberpunk Wiki SOLO si prefs.enable_online_wiki es True; si no, devuelve '' sin red."""
    cur_prefs = prefs if prefs is not None else load_companion_prefs()
    if not cur_prefs.enable_online_wiki:
        return ""
    if not should_query_online(player_text, local_top_score, tracked_quest_title):
        return ""

    term = _build_search_term(player_text, tracked_quest_title)
    cache_key = f"cp77_es:{term.lower()}"
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
        title, summary = _query_fandom_api("https://cyberpunk.fandom.com/es/api.php", term)
        if not summary:
            title, summary = _query_fandom_api("https://cyberpunk.fandom.com/api.php", f"{term} Cyberpunk 2077")
    except Exception:
        return ""

    if not summary:
        return ""
    formatted = f"[ARCHIVO RED EXTERNA (NO MENCIONAR WEB) — {title}]: {summary}"
    _cache_put(cache_path, cache_key, title, formatted)
    return formatted


def run_self_test() -> None:
    """Verifica que con enable_online_wiki=False (por defecto) jamás se realiza ninguna llamada de red."""
    import tempfile
    from unittest import mock

    with tempfile.TemporaryDirectory(prefix="chispa_wiki_test_") as tmp:
        def_prefs = CompanionPrefs()
        assert def_prefs.enable_online_wiki is False, "La wiki online debe venir desactivada por defecto."

        with mock.patch("urllib.request.urlopen") as m_url:
            out = lookup_wiki_online(
                "¿Cómo paso exactamente la misión The Pickup en All Foods?",
                local_top_score=0.0,
                tracked_quest_title="The Pickup",
                prefs=def_prefs,
                cache_path=Path(tmp) / "wiki.sqlite",
            )
            assert out == ""
            assert m_url.call_count == 0, "Con enable_online_wiki=False no se puede abrir ningún socket."

        # Verificar que sí respeta la caché cuando está activada explícitamente
        cache_p = Path(tmp) / "wiki_on.sqlite"
        _cache_put(cache_p, "cp77_es:all foods", "All Foods", "[ARCHIVO RED EXTERNA] Entrada de prueba.")
        on_prefs = CompanionPrefs(enable_online_wiki=True)
        with mock.patch("urllib.request.urlopen") as m_url2:
            cached_out = lookup_wiki_online(
                "¿Dónde queda All Foods exactamente?",
                local_top_score=0.0,
                tracked_quest_title="",
                prefs=on_prefs,
                cache_path=cache_p,
            )
            assert "Entrada de prueba" in cached_out
            assert m_url2.call_count == 0
    print("=== WIKI ONLINE GATE SELF-TEST: OK ===")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Puerta de consulta online opcional para C.H.I.S.P.A.")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        run_self_test()


if __name__ == "__main__":
    main()
