"""Persistent companion preferences shared between the live service and SPARKY Studio (English Edition)."""

from __future__ import annotations

import json
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

USER_BRIDGE_DIR = Path.home() / ".sparky_ai_bridge_en"
PREFS_FILE = USER_BRIDGE_DIR / "companion_prefs.json"

VALID_SPONTANEOUS_MODES = ("off", "tactical", "active")
VALID_REPLY_LENGTHS = ("concise", "balanced", "detailed")

_LOCK = threading.RLock()
_CACHED_MTIME_NS: int = -1
_CACHED_PREFS: CompanionPrefs | None = None


@dataclass
class CompanionPrefs:
    """Behavior and privacy preferences for S.P.A.R.K.Y. v2.0."""

    # Privacy: online Cyberpunk Wiki lookup is ALWAYS disabled by default.
    enable_online_wiki: bool = False
    spontaneous_mode: str = "tactical"  # "off" | "tactical" | "active"
    reply_length: str = "balanced"  # "concise" | "balanced" | "detailed"
    ambient_cooldown_s: float = 165.0

    def normalized(self) -> CompanionPrefs:
        mode = str(self.spontaneous_mode or "tactical").strip().lower()
        if mode not in VALID_SPONTANEOUS_MODES:
            mode = "tactical"
        rlen = str(self.reply_length or "balanced").strip().lower()
        if rlen not in VALID_REPLY_LENGTHS:
            rlen = "balanced"
        try:
            amb = max(45.0, min(600.0, float(self.ambient_cooldown_s)))
        except (TypeError, ValueError):
            amb = 165.0
        return CompanionPrefs(
            enable_online_wiki=bool(self.enable_online_wiki),
            spontaneous_mode=mode,
            reply_length=rlen,
            ambient_cooldown_s=amb,
        )


def _write_atomic(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    payload = json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    for attempt in range(5):
        try:
            tmp.write_text(payload, encoding="utf-8")
            tmp.replace(path)
            return
        except PermissionError:
            if attempt < 4:
                time.sleep(0.015)
            else:
                raise


def ensure_prefs_file(path: Path = PREFS_FILE) -> Path:
    """Creates companion_prefs.json with safe defaults if it does not exist yet."""
    if path.is_file():
        return path
    with _LOCK:
        if not path.is_file():
            path.parent.mkdir(parents=True, exist_ok=True)
            _write_atomic(path, asdict(CompanionPrefs()))
    return path


def load_companion_prefs(path: Path = PREFS_FILE, force_reload: bool = False) -> CompanionPrefs:
    """Loads preferences with automatic mtime-based hot reload."""
    global _CACHED_MTIME_NS, _CACHED_PREFS
    ensure_prefs_file(path)
    use_default_cache = path == PREFS_FILE
    try:
        mtime_ns = int(path.stat().st_mtime_ns) if path.is_file() else 0
    except OSError:
        mtime_ns = 0

    if use_default_cache and not force_reload and _CACHED_PREFS is not None and mtime_ns == _CACHED_MTIME_NS:
        return _CACHED_PREFS

    loaded: dict[str, Any] = {}
    if path.is_file():
        for attempt in range(3):
            try:
                raw = json.loads(path.read_text(encoding="utf-8-sig"))
                if isinstance(raw, dict):
                    loaded = raw
                break
            except PermissionError:
                if attempt < 2:
                    time.sleep(0.01)
            except Exception:
                break

    prefs = CompanionPrefs(
        enable_online_wiki=bool(loaded.get("enable_online_wiki", False)),
        spontaneous_mode=str(loaded.get("spontaneous_mode", "tactical")),
        reply_length=str(loaded.get("reply_length", "balanced")),
        ambient_cooldown_s=float(loaded.get("ambient_cooldown_s", 165.0) or 165.0),
    ).normalized()

    if use_default_cache:
        _CACHED_MTIME_NS = mtime_ns
        _CACHED_PREFS = prefs
    return prefs


def save_companion_prefs(
    prefs: CompanionPrefs | None = None,
    *,
    path: Path = PREFS_FILE,
    **updates: Any,
) -> CompanionPrefs:
    """Atomically writes full or partial preference updates."""
    global _CACHED_MTIME_NS, _CACHED_PREFS
    with _LOCK:
        cur = prefs if prefs is not None else load_companion_prefs(path=path, force_reload=True)
        merged = asdict(cur.normalized())
        for k, v in updates.items():
            if k in merged and v is not None:
                merged[k] = v
        clean = CompanionPrefs(**merged).normalized()
        _write_atomic(path, asdict(clean))
        if path == PREFS_FILE:
            try:
                _CACHED_MTIME_NS = int(path.stat().st_mtime_ns)
            except OSError:
                _CACHED_MTIME_NS = -1
            _CACHED_PREFS = clean
        return clean
