"""Persistent episodic memory isolated per character/playthrough with async recap (S.P.A.R.K.Y. v2.0)."""

from __future__ import annotations

import json
import re
import sqlite3
import threading
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from sparky_rt.companion_prefs import USER_BRIDGE_DIR
from sparky_rt.config import SparkyServiceConfig
from sparky_rt.lore_rag import strip_accents, tokenize_terms

DEFAULT_STATE_DIR = USER_BRIDGE_DIR / "state"
DEFAULT_LOG_DIR = USER_BRIDGE_DIR / "logs"
DEFAULT_EPISODIC_DB = DEFAULT_STATE_DIR / "episodic_index_en.sqlite"

JOURNAL_MAX = 15
MILESTONES_MAX = 20
SESSION_NOTES_MAX = 8
RECAP_EVERY_N_TURNS = 8

_ICONIC_HUBS = (
    "tom's diner",
    "el coyote cojo",
    "afterlife",
    "lizzie's bar",
    "clouds",
    "north industrial district",
    "northside",
    "pacifica",
    "dogtown",
    "japantown",
    "vista del rey",
    "the glen",
    "arroyo",
    "badlands",
)

_INTERROGATIVE_STARTS_EN = (
    "what ", "who ", "where ", "when ", "why ", "how ", "which ",
    "tell me", "do you know", "do you remember", "can you", "is there ", "are there ",
)

DEFAULT_JOURNAL_BY_LIFEPATH = {
    "streetkid": [
        "Kiroshi link activated in Night City with V, a sharp-reflex Heywood Streetkid.",
    ],
    "nomad": [
        "Kiroshi link activated in Night City with V, a dust-hardened Badlands Nomad.",
    ],
    "corporate": [
        "Kiroshi link activated in Night City with V, a former Arasaka counterintel agent who knows how suits bite.",
    ],
    "default": [
        "Kiroshi link activated in Night City with V right after pulling my core out of that Zetatech briefcase.",
    ],
}

RECAP_SCHEMA = {
    "type": "object",
    "properties": {
        "session_summary": {
            "type": "string",
            "description": "One short English sentence in first-person from SPARKY summarizing recent events with V.",
        },
        "journal": {
            "type": "array",
            "items": {"type": "string"},
            "description": "List of key milestones lived with V (max 15 short first-person English bullets).",
        },
        "sync_delta": {"type": "integer", "enum": [-2, -1, 0, 1, 2, 3]},
    },
    "required": ["session_summary", "journal", "sync_delta"],
    "additionalProperties": False,
}

_PROFILE_UID_RE = re.compile(r"^(.+?)_(\d{4,12})$")


def extract_base_lifepath(raw_lifepath: str | None) -> str:
    low = strip_accents(str(raw_lifepath or ""))
    if "street" in low or "buscavidas" in low:
        return "streetkid"
    if "nomad" in low or "nomada" in low:
        return "nomad"
    if "corp" in low:
        return "corporate"
    return "default"


def normalize_profile_id(raw_profile_id: str | None) -> str:
    """Normalizes a profile ID while preserving any unique <mem_uid> suffix."""
    raw = strip_accents(str(raw_profile_id or "")).strip()
    m = _PROFILE_UID_RE.match(raw)
    if m:
        return f"{extract_base_lifepath(m.group(1))}_{m.group(2)}"
    return extract_base_lifepath(raw)


def resolve_profile_id(game_state: dict[str, Any] | None) -> str:
    """Resolves a strict per-playthrough profile key combining V's lifepath and chispa_mem_uid."""
    st = game_state or {}
    base = extract_base_lifepath(st.get("lifepath"))
    try:
        mem_uid = int(st.get("mem_uid") or 0)
    except (TypeError, ValueError):
        mem_uid = 0
    if mem_uid > 0:
        return f"{base}_{mem_uid}"
    return base


def resolve_veterancy_tier(game_state: dict[str, Any] | None, sync_level: int = 45) -> str:
    """Determines whether V has cleared opening missions ('partner') or is still in initial trials ('rookie')."""
    if not game_state:
        return "partner"

    def _as_int(key: str, default: int = 0) -> int:
        try:
            val = game_state.get(key)
            return int(default if val is None else val)
        except (TypeError, ValueError):
            return default

    ep05_done = _as_int("ep05_done", 0)
    season_stage = _as_int("season_stage", 0)
    act_phase = _as_int("act_phase", 1)
    level = _as_int("level", 1)
    street_cred = _as_int("street_cred", 1)

    if (
        ep05_done > 0
        or season_stage >= 400
        or act_phase >= 2
        or level >= 12
        or street_cred >= 12
        or int(sync_level) >= 58
    ):
        return "partner"
    return "rookie"


def is_question_like(text: str) -> bool:
    raw = (text or "").strip()
    if not raw:
        return False
    if "?" in raw:
        return True
    s = re.sub(r"\s+", " ", strip_accents(raw))
    return s.startswith(_INTERROGATIVE_STARTS_EN)


def is_duplicate_question(q1: str, q2: str) -> bool:
    """Detects repeated questions so history stays clean without scolding the player."""
    if not (is_question_like(q1) and is_question_like(q2)):
        return False
    s1 = strip_accents(re.sub(r"\s+", " ", (q1 or "").strip().rstrip("?.!¡¿")))
    s2 = strip_accents(re.sub(r"\s+", " ", (q2 or "").strip().rstrip("?.!¡¿")))
    if not s1 or not s2:
        return False
    if s1 == s2:
        return True
    t1 = set(tokenize_terms(s1))
    t2 = set(tokenize_terms(s2))
    if not t1 or not t2:
        return False
    overlap = len(t1 & t2) / max(1, min(len(t1), len(t2)))
    return overlap >= 0.75 and abs(len(t1) - len(t2)) <= 3


def since_last_session_en(profile: dict[str, Any]) -> str:
    last = profile.get("last_session")
    if not isinstance(last, dict) or not last.get("ended"):
        return ""
    try:
        ended_dt = datetime.strptime(str(last["ended"]), "%Y-%m-%d %H:%M")
        gap = datetime.now() - ended_dt
    except Exception:
        return ""
    if gap.total_seconds() < 900:
        return ""
    if gap.days >= 1:
        return f"{gap.days} day{'s' if gap.days > 1 else ''} ago"
    hours = gap.seconds // 3600
    if hours:
        return f"{hours} hour{'s' if hours > 1 else ''} ago"
    mins = max(1, gap.seconds // 60)
    return f"{mins} minute{'s' if mins > 1 else ''} ago"


def _write_json_atomic(path: Path, obj: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    payload = json.dumps(obj, indent=2, ensure_ascii=False) + "\n"
    for attempt in range(4):
        try:
            tmp.write_text(payload, encoding="utf-8")
            tmp.replace(path)
            return
        except PermissionError:
            if attempt < 3:
                time.sleep(0.015)


class EpisodicMemoryManager:
    """Manages per-playthrough journals, FTS5 episodic recall, and background async compression."""

    def __init__(
        self,
        state_dir: Path = DEFAULT_STATE_DIR,
        log_dir: Path = DEFAULT_LOG_DIR,
        db_path: Path = DEFAULT_EPISODIC_DB,
        cfg: SparkyServiceConfig | None = None,
    ) -> None:
        self.state_dir = state_dir
        self.log_dir = log_dir
        self.db_path = db_path
        self.cfg = cfg or SparkyServiceConfig()
        self._lock = threading.Lock()
        self._recap_in_flight = False
        self._pending_recap_buffer: dict[str, list[dict[str, Any]]] = {}
        self._init_db()

    def _init_db(self) -> None:
        self.state_dir.mkdir(parents=True, exist_ok=True)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(self.db_path)
        try:
            with conn:
                conn.execute(
                    """
                    CREATE TABLE IF NOT EXISTS episodic_memories (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        profile_id TEXT NOT NULL,
                        kind TEXT NOT NULL,
                        district TEXT NOT NULL,
                        tags TEXT NOT NULL,
                        content TEXT NOT NULL,
                        playthrough_sec REAL NOT NULL DEFAULT 0.0,
                        created_ts REAL NOT NULL
                    )
                    """
                )
                try:
                    conn.execute(
                        "ALTER TABLE episodic_memories ADD COLUMN playthrough_sec REAL NOT NULL DEFAULT 0.0"
                    )
                except sqlite3.OperationalError:
                    pass
                conn.execute(
                    """
                    CREATE VIRTUAL TABLE IF NOT EXISTS episodic_fts USING fts5(
                        mem_id UNINDEXED,
                        profile_id UNINDEXED,
                        district,
                        tags,
                        content,
                        tokenize='unicode61 remove_diacritics 2'
                    )
                    """
                )
        finally:
            conn.close()

    def _profile_path(self, profile_id: str) -> Path:
        pid = normalize_profile_id(profile_id)
        return self.state_dir / f"profile_{pid}.json"

    def load_profile(self, profile_id: str = "default") -> dict[str, Any]:
        pid = normalize_profile_id(profile_id)
        base_lp = extract_base_lifepath(pid)
        default_journal = list(
            DEFAULT_JOURNAL_BY_LIFEPATH.get(base_lp, DEFAULT_JOURNAL_BY_LIFEPATH["default"])
        )
        default_milestones = [
            {"pt": 0.0, "key": f"lp:{base_lp}", "text": txt}
            for txt in default_journal
        ]
        p_path = self._profile_path(pid)
        default_obj: dict[str, Any] = {
            "profile_id": pid,
            "sync_level": 45,
            "turns_since_recap": 0,
            "total_turns": 0,
            "sessions": 0,
            "milestones": default_milestones,
            "session_notes": [],
            "journal": default_journal,
            "journal_timed": [{"pt": 0.0, "text": txt} for txt in default_journal],
            "last_playthrough_sec": 0.0,
            "last_session": None,
            "last_district": "",
            "last_quest": "",
        }
        if not p_path.is_file():
            return default_obj
        try:
            loaded = json.loads(p_path.read_text(encoding="utf-8-sig"))
            if isinstance(loaded, dict):
                merged = {**default_obj, **loaded, "profile_id": pid}
                if "milestones" not in loaded:
                    if isinstance(loaded.get("journal_timed"), list) and loaded["journal_timed"]:
                        merged["milestones"] = [
                            {"pt": float(x.get("pt") or 0.0), "key": "", "text": str(x.get("text") or "").strip()}
                            for x in loaded["journal_timed"]
                            if isinstance(x, dict) and str(x.get("text") or "").strip()
                        ]
                    elif isinstance(loaded.get("journal"), list) and loaded["journal"]:
                        merged["milestones"] = [
                            {"pt": 0.0, "key": "", "text": str(x).strip()}
                            for x in loaded["journal"]
                            if str(x).strip()
                        ]
                if not isinstance(merged.get("session_notes"), list):
                    merged["session_notes"] = []
                self._sync_journal_fields(merged)
                return merged
        except Exception:
            pass
        return default_obj

    def save_profile(self, profile: dict[str, Any]) -> None:
        pid = normalize_profile_id(profile.get("profile_id"))
        _write_json_atomic(self._profile_path(pid), profile)

    def _append_jsonl_log(self, profile_id: str, entry: dict[str, Any]) -> None:
        fname = f"{datetime.now():%Y-%m-%d}_{normalize_profile_id(profile_id)}.jsonl"
        try:
            self.log_dir.mkdir(parents=True, exist_ok=True)
            with (self.log_dir / fname).open("a", encoding="utf-8") as f:
                f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        except OSError:
            pass

    def _insert_memory_item(
        self,
        profile_id: str,
        kind: str,
        district: str,
        tags: str,
        content: str,
        playthrough_sec: float = 0.0,
    ) -> None:
        pid = normalize_profile_id(profile_id)
        conn = sqlite3.connect(self.db_path)
        try:
            with conn:
                cur = conn.execute(
                    """
                    INSERT INTO episodic_memories (profile_id, kind, district, tags, content, playthrough_sec, created_ts)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    (pid, kind, district, tags, content, float(playthrough_sec or 0.0), time.time()),
                )
                row_id = int(cur.lastrowid or 0)
                conn.execute(
                    """
                    INSERT INTO episodic_fts (mem_id, profile_id, district, tags, content)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                    (row_id, pid, district, tags, content),
                )
        finally:
            conn.close()

    @staticmethod
    def _sync_journal_fields(prof: dict[str, Any]) -> None:
        combined: list[dict[str, Any]] = []
        seen_txt: set[str] = set()
        for entry in list(prof.get("milestones") or []) + list(prof.get("session_notes") or []):
            if not isinstance(entry, dict):
                continue
            txt = str(entry.get("text") or "").strip()
            norm = strip_accents(txt)
            if not txt or norm in seen_txt:
                continue
            seen_txt.add(norm)
            combined.append({"pt": float(entry.get("pt") or 0.0), "text": txt})
        trimmed = combined[-JOURNAL_MAX:]
        prof["journal_timed"] = trimmed
        prof["journal"] = [x["text"] for x in trimmed]

    def record_world_event(
        self,
        profile_id: str,
        kind: str,
        text: str,
        *,
        district: str = "",
        quest: str = "",
        playthrough_sec: float = 0.0,
        dedup_key: str = "",
    ) -> bool:
        """Deterministically records a factual campaign, quest, or landmark milestone."""
        text_clean = (text or "").strip()
        if not text_clean:
            return False
        pid = normalize_profile_id(profile_id)
        pt_sec = float(playthrough_sec or 0.0)
        norm_text = strip_accents(text_clean)

        with self._lock:
            prof = self.load_profile(pid)
            milestones = [m for m in (prof.get("milestones") or []) if isinstance(m, dict)]
            for m in milestones:
                if dedup_key and str(m.get("key") or "") == dedup_key:
                    return False
                if strip_accents(str(m.get("text") or "")) == norm_text:
                    return False

            milestones.append({"pt": pt_sec, "key": dedup_key, "text": text_clean})
            prof["milestones"] = milestones[-MILESTONES_MAX:]
            if pt_sec > 0.0:
                prof["last_playthrough_sec"] = pt_sec
            self._sync_journal_fields(prof)
            self.save_profile(prof)

            tags = " ".join(x for x in (kind, district, quest) if x)
            self._insert_memory_item(pid, kind, district, tags, text_clean, playthrough_sec=pt_sec)
        return True

    def sync_progression_milestones(
        self,
        profile_id: str,
        game_state: dict[str, Any] | None,
    ) -> list[str]:
        """Synchronizes concrete run milestones from live telemetry (Season 1, quest transitions, hubs)."""
        if not game_state or not game_state.get("session_ready"):
            return []
        district = str(game_state.get("district") or "").strip()
        q_title = str(game_state.get("tracked_quest_title") or "").strip()
        q_obj = str(game_state.get("tracked_quest_obj") or "").strip()
        try:
            mem_uid = int(game_state.get("mem_uid") or 0)
        except (TypeError, ValueError):
            mem_uid = 0
        if not game_state.get("full_gameplay") and not (mem_uid > 0 and (district or q_title)):
            return []

        pid = normalize_profile_id(profile_id)
        try:
            pt_sec = float(game_state.get("playthrough_sec") or 0.0)
        except (TypeError, ValueError):
            pt_sec = 0.0

        added: list[str] = []

        # 1. S.P.A.R.K.Y. Protocol Season 1 state
        ep05_done = int(game_state.get("ep05_done") or 0)
        ep05_end = int(game_state.get("ep05_ending") or 0)
        season_stage = int(game_state.get("season_stage") or 0)
        if ep05_done > 0:
            end_labels = {
                1: "Autonomous Partner v1.0",
                2: "Leaking Zetatech's dirty ledger to Network 54",
                3: "Armorer Protocol (Sergeant's Last Word)",
            }
            lbl = end_labels.get(ep05_end, "Season 1 completed")
            msg = f"We completed our entire S.P.A.R.K.Y. Protocol campaign in Pacifica, locking in: {lbl}."
            if self.record_world_event(
                pid,
                "milestone",
                msg,
                district=district or "Pacifica",
                quest="S.P.A.R.K.Y. Protocol",
                playthrough_sec=pt_sec,
                dedup_key="sparky_s1_done",
            ):
                added.append(msg)
        elif season_stage >= 100:
            msg = f"We kicked off the tactical S.P.A.R.K.Y. Protocol campaign in Watson (stage {season_stage})."
            if self.record_world_event(
                pid,
                "milestone",
                msg,
                district=district or "Watson",
                quest="S.P.A.R.K.Y. Protocol",
                playthrough_sec=pt_sec,
                dedup_key="sparky_s1_active",
            ):
                added.append(msg)

        # 2. Deterministic active quest transitions (e.g. Playing for Time -> Automatic Love)
        with self._lock:
            prof = self.load_profile(pid)
            prev_quest = str(prof.get("last_quest") or "").strip()
            prev_dist = str(prof.get("last_district") or "").strip()

        if q_title and prev_quest and strip_accents(q_title) != strip_accents(prev_quest):
            place = prev_dist or district or "Night City"
            obj_bit = f" ({q_obj})" if q_obj else ""
            q_msg = f"We cleared {place} (quest '{prev_quest}' done) and our active objective shifted to '{q_title}'{obj_bit}."
            dkey = f"qtrans:{strip_accents(prev_quest)}->{strip_accents(q_title)}"
            if self.record_world_event(
                pid,
                "quest_transition",
                q_msg,
                district=district or prev_dist,
                quest=q_title,
                playthrough_sec=pt_sec,
                dedup_key=dkey,
            ):
                added.append(q_msg)

        # 3. First visits to iconic hubs
        if district:
            dist_norm = strip_accents(district)
            if any(hub in dist_norm for hub in _ICONIC_HUBS):
                q_bit = f" during '{q_title}'" if q_title else ""
                loc_msg = f"We visited {district}{q_bit}."
                if self.record_world_event(
                    pid,
                    "location",
                    loc_msg,
                    district=district,
                    quest=q_title,
                    playthrough_sec=pt_sec,
                    dedup_key=f"hub:{dist_norm}",
                ):
                    added.append(loc_msg)

        if district or q_title:
            with self._lock:
                prof2 = self.load_profile(pid)
                changed = False
                if district and prof2.get("last_district") != district:
                    prof2["last_district"] = district
                    changed = True
                if q_title and prof2.get("last_quest") != q_title:
                    prof2["last_quest"] = q_title
                    changed = True
                if changed:
                    self.save_profile(prof2)

        return added

    def record_shard_read(
        self,
        profile_id: str,
        title: str,
        text: str,
        district: str = "",
        playthrough_sec: float = 0.0,
    ) -> None:
        """Indexes shard contents read by V for later callback and discussion."""
        t_clean = (title or "").strip()
        b_clean = (text or "").strip()
        if not t_clean and not b_clean:
            return
        pid = normalize_profile_id(profile_id)
        pt_sec = float(playthrough_sec or 0.0)
        combined = f"Shard read '{t_clean}' (in {district or 'Night City'}): {b_clean[:360]}"
        with self._lock:
            self._insert_memory_item(
                pid,
                "shard",
                district,
                f"shard data {t_clean}",
                combined,
                playthrough_sec=pt_sec,
            )
            prof = self.load_profile(pid)
            note = f"V read the shard '{t_clean}' in {district or 'Night City'}."
            milestones = [m for m in (prof.get("milestones") or []) if isinstance(m, dict)]
            dkey = f"shard:{strip_accents(t_clean)}"
            if not any(str(m.get("key") or "") == dkey for m in milestones):
                milestones.append({"pt": pt_sec, "key": dkey, "text": note})
                prof["milestones"] = milestones[-MILESTONES_MAX:]
                prof["last_playthrough_sec"] = pt_sec
                self._sync_journal_fields(prof)
                self.save_profile(prof)

    def record_turn(
        self,
        profile_id: str,
        *,
        kind: str,
        user_text: str,
        reply_text: str,
        game_state: dict[str, Any] | None = None,
        allow_async_recap: bool = True,
    ) -> None:
        """Logs manual chats into FTS5 + recap; keeps spontaneous banter strictly in JSONL logs."""
        if not reply_text.strip():
            return
        pid = normalize_profile_id(profile_id)
        st = game_state or {}
        district = str(st.get("district") or "").strip()
        quest = str(st.get("tracked_quest_title") or "").strip()
        try:
            pt_sec = float(st.get("playthrough_sec") or 0.0)
        except (TypeError, ValueError):
            pt_sec = 0.0

        self._append_jsonl_log(
            pid,
            {
                "at": datetime.now(timezone.utc).isoformat(),
                "profile_id": pid,
                "playthrough_sec": pt_sec,
                "kind": kind,
                "district": district,
                "quest": quest,
                "user": user_text,
                "reply": reply_text,
            },
        )

        is_spontaneous = str(kind).startswith("spont:")
        trigger_turns: list[dict[str, Any]] | None = None
        with self._lock:
            prof = self.load_profile(pid)
            prof["total_turns"] = int(prof.get("total_turns", 0)) + 1
            if pt_sec > 0.0:
                prof["last_playthrough_sec"] = pt_sec
            if district:
                prof["last_district"] = district
            if quest:
                prof["last_quest"] = quest

            if not is_spontaneous:
                tags = " ".join(x for x in (kind, district, quest) if x)
                first_sent = ""
                m_sent = re.search(r"^.{12,}?[.!?…](?=\s|$)", reply_text.strip())
                if m_sent:
                    first_sent = m_sent.group(0).strip()[:130]
                else:
                    first_sent = reply_text.strip()[:120]
                loc_tag = f"{district or 'Night City'} | {quest or 'free roam'}"
                mem_line = (
                    f"[{loc_tag}] V asked/said: '{user_text[:150]}'"
                    + (f" — Reply: {first_sent}" if first_sent else "")
                )
                self._insert_memory_item(pid, kind, district, tags, mem_line, playthrough_sec=pt_sec)

                prof["turns_since_recap"] = int(prof.get("turns_since_recap", 0)) + 1
                if kind == "chat":
                    prof["sync_level"] = min(100, int(prof.get("sync_level", 45)) + 1)
                prof["last_session"] = {
                    "ended": datetime.now().strftime("%Y-%m-%d %H:%M"),
                    "pt": pt_sec,
                    "summary": f"Last talk in {district or 'Night City'}: {first_sent[:95]}",
                }
                self.save_profile(prof)

                buf = self._pending_recap_buffer.setdefault(pid, [])
                buf.append(
                    {
                        "kind": kind,
                        "district": district,
                        "quest": quest,
                        "pt": pt_sec,
                        "user": user_text[:140],
                        "reply": first_sent[:140],
                    }
                )
                del buf[:-24]
                if (
                    allow_async_recap
                    and prof["turns_since_recap"] >= RECAP_EVERY_N_TURNS
                    and not self._recap_in_flight
                ):
                    trigger_turns = list(buf)
                    self._recap_in_flight = True
            else:
                self.save_profile(prof)

        if trigger_turns is not None:
            threading.Thread(
                target=self._run_async_recap,
                args=(pid, trigger_turns),
                name="sparky-recap",
                daemon=True,
            ).start()

    @staticmethod
    def _clean_recap_note(raw_note: str) -> str:
        s = re.sub(r"\*{1,3}|_{1,3}|[`#]+", "", str(raw_note or ""))
        s = re.sub(r"^\s*(?:[-•]\s+|\d{1,2}\.\s+)", "", s).strip()
        if len(s) < 15 or not s.endswith((".", "!", "?", "…")):
            return ""
        return s

    def _run_async_recap(self, profile_id: str, turns: list[dict[str, Any]]) -> None:
        """Compresses recent chats in the background without inventing facts or overwriting milestones."""
        try:
            with self._lock:
                prof = self.load_profile(profile_id)
                cur_notes = [str(n.get("text") or "") for n in (prof.get("session_notes") or []) if isinstance(n, dict)]

            pt_sec = max((float(t.get("pt") or 0.0) for t in turns), default=float(prof.get("last_playthrough_sec") or 0.0))
            transcript_lines = [
                f"- ({t.get('district') or 'Night City'} | {t.get('quest') or 'free roam'}) V: {t['user']} -> SPARKY: {t['reply']}"
                for t in turns[-14:]
            ]
            system_msg = (
                "You are S.P.A.R.K.Y.'s factual memory compression module in Cyberpunk 2077. "
                "Condense ONLY explicit facts from the given turns into crisp first-person English sentences. "
                "FORBIDDEN: inventing projects, characters, or factions absent from the transcript, markdown asterisks (**), brackets, or numbered lists. "
                "Every item in 'journal' must be one complete sentence ending cleanly with a period (max 8 notes)."
            )
            user_msg = (
                f"PRIOR SESSION NOTES:\n{json.dumps(cur_notes, ensure_ascii=False)}\n\n"
                f"RECENT V TALKS:\n" + "\n".join(transcript_lines)
            )
            payload = {
                "model": self.cfg.llm_model,
                "messages": [
                    {"role": "system", "content": system_msg},
                    {"role": "user", "content": user_msg},
                ],
                "format": RECAP_SCHEMA,
                "stream": False,
                "keep_alive": -1,
                "options": {
                    "temperature": 0.2,
                    "num_ctx": max(4096, int(self.cfg.llm_num_ctx)),
                    **{k: v for k, v in self.cfg.ollama_base_options().items() if k != "num_ctx"},
                    "num_predict": 500,
                },
            }
            req = urllib.request.Request(
                f"{self.cfg.ollama_url}/api/chat",
                data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(req, timeout=25.0) as resp:
                raw = json.loads(resp.read().decode("utf-8", errors="replace"))
            parsed = json.loads(raw["message"]["content"])

            with self._lock:
                prof2 = self.load_profile(profile_id)
                cleaned_notes = [
                    c for x in (parsed.get("journal") or [])
                    if (c := self._clean_recap_note(str(x)))
                ]
                if cleaned_notes:
                    trimmed_notes = cleaned_notes[-SESSION_NOTES_MAX:]
                    prof2["session_notes"] = [{"pt": pt_sec, "text": x} for x in trimmed_notes]
                    self._sync_journal_fields(prof2)
                prof2["sync_level"] = max(0, min(100, int(prof2.get("sync_level", 45)) + int(parsed.get("sync_delta", 0))))
                prof2["turns_since_recap"] = 0
                prof2["sessions"] = int(prof2.get("sessions", 0)) + 1
                summary = self._clean_recap_note(str(parsed.get("session_summary") or ""))
                if summary:
                    prof2["last_session"] = {
                        "ended": datetime.now().strftime("%Y-%m-%d %H:%M"),
                        "pt": pt_sec,
                        "summary": summary,
                    }
                self.save_profile(prof2)
        except Exception:
            pass
        finally:
            self._recap_in_flight = False

    def retrieve_past_memories(
        self,
        profile_id: str,
        query: str,
        district: str = "",
        top_k: int = 3,
        max_playthrough_sec: float | None = None,
    ) -> list[str]:
        """Retrieves FTS5 BM25 memories scoped to one character and causal save timeline."""
        pid = normalize_profile_id(profile_id)
        tokens = tokenize_terms(f"{query} {district}")
        if not tokens:
            return []
        fts_q = " OR ".join(f'"{t}"' for t in list(dict.fromkeys(tokens))[:10])
        conn = sqlite3.connect(self.db_path)
        try:
            if max_playthrough_sec is not None and max_playthrough_sec > 0.0:
                rows = conn.execute(
                    """
                    SELECT content, -bm25(episodic_fts, 1.5, 1.2, 2.0) AS rank_sc
                    FROM episodic_fts
                    WHERE profile_id = ? AND episodic_fts MATCH ?
                      AND CAST(mem_id AS INTEGER) IN (
                          SELECT id FROM episodic_memories
                          WHERE profile_id = ? AND (playthrough_sec <= ? OR playthrough_sec <= 0.0)
                      )
                    ORDER BY rank_sc DESC
                    LIMIT ?
                    """,
                    (pid, fts_q, pid, float(max_playthrough_sec) + 90.0, top_k),
                ).fetchall()
            else:
                rows = conn.execute(
                    """
                    SELECT content, -bm25(episodic_fts, 1.5, 1.2, 2.0) AS rank_sc
                    FROM episodic_fts
                    WHERE profile_id = ? AND episodic_fts MATCH ?
                    ORDER BY rank_sc DESC
                    LIMIT ?
                    """,
                    (pid, fts_q, top_k),
                ).fetchall()
            return [str(r[0]) for r in rows]
        except sqlite3.Error:
            return []
        finally:
            conn.close()

    def build_memory_context(
        self,
        profile_id: str,
        query: str,
        district: str = "",
        current_playthrough_sec: float | None = None,
        game_state: dict[str, Any] | None = None,
        compact: bool = False,
    ) -> str:
        """Builds clean camaraderie, lived milestones, and causal episodic memory context."""
        pid = normalize_profile_id(profile_id)
        base_lp = extract_base_lifepath(pid)
        prof = self.load_profile(pid)
        sync = int(prof.get("sync_level", 45))
        tier = resolve_veterancy_tier(game_state, sync)
        if tier == "partner":
            eff_sync = max(sync, 65)
            bond = f"Camaraderie {eff_sync}/100 (Trusted FULL PARTNER)"
            rank_line = (
                "Current address: FULL PARTNER — Opening missions cleared; "
                "treat V as an equal calling them 'partner' or 'V'."
            )
        else:
            bond = f"Bond {sync}/100 (Rookie getting broken in)"
            rank_line = (
                "V'S CURRENT RANK: INITIAL STAGE — Still in opening missions; "
                "you may call V 'recruit', 'rookie', or 'V'."
            )

        lp_label = {
            "nomad": "Nomad — Badlands",
            "streetkid": "Streetkid — Heywood",
            "corporate": "Corpo — ex-Arasaka",
        }.get(base_lp, base_lp)
        parts = [f"Relationship with V ({lp_label}): {bond}. {rank_line}"]
        last_s = prof.get("last_session")
        limit_pt = float(current_playthrough_sec) + 90.0 if current_playthrough_sec and current_playthrough_sec > 0.0 else None

        if (not compact) and isinstance(last_s, dict) and last_s.get("summary"):
            last_pt = float(last_s.get("pt") or 0.0)
            if limit_pt is None or last_pt <= limit_pt or last_pt <= 0.0:
                gap_txt = since_last_session_en(prof)
                if gap_txt:
                    parts.append(f"Last session ({gap_txt}): {last_s['summary']}")

        timeline_src = list(prof.get("milestones") or []) + list(prof.get("session_notes") or [])
        if not timeline_src:
            timeline_src = list(prof.get("journal_timed") or [])

        timeline_items: list[str] = []
        seen_norm: set[str] = set()
        for entry in timeline_src:
            if not isinstance(entry, dict):
                continue
            txt = str(entry.get("text") or "").strip()
            if not txt:
                continue
            pt_val = float(entry.get("pt") or 0.0)
            if limit_pt is not None and pt_val > limit_pt:
                continue
            norm = strip_accents(txt)
            if norm not in seen_norm:
                seen_norm.add(norm)
                timeline_items.append(txt)

        if not timeline_items:
            timeline_items = list(
                DEFAULT_JOURNAL_BY_LIFEPATH.get(base_lp, DEFAULT_JOURNAL_BY_LIFEPATH["default"])
            )

        if compact:
            parts.append(f"Latest current progression: {timeline_items[-1]}")
            return "\n".join(parts)

        recent_slice = [timeline_items[0], *timeline_items[-5:]] if len(timeline_items) > 6 else timeline_items
        if len(recent_slice) >= 2:
            earlier_bullets = "\n".join(f"- {item}" for item in recent_slice[:-1])
            parts.append(
                "Real shared history from this run (cite these concrete facts when V asks what you remember):\n"
                + earlier_bullets
                + f"\nLatest current progression: {recent_slice[-1]}"
            )
        else:
            bullets = "\n".join(f"- {item}" for item in recent_slice)
            parts.append(
                "Real shared history from this run (cite these concrete facts when V asks what you remember):\n"
                + bullets
            )

        recalled = self.retrieve_past_memories(
            pid,
            query,
            district=district,
            top_k=3,
            max_playthrough_sec=current_playthrough_sec,
        )
        q_norm = strip_accents(query)
        filtered_recalls: list[str] = []
        for rec in recalled:
            if query and is_duplicate_question(query, rec):
                continue
            if len(q_norm) >= 12 and q_norm in strip_accents(rec) and any(r in rec for r in ("V asked", "V said")):
                continue
            filtered_recalls.append(rec)
        if filtered_recalls:
            parts.append("Relevant past talks and shards: " + " || ".join(filtered_recalls[:3]))
        return "\n".join(parts)

    def clear_episodic_memory(self, profile_id: str | None = None) -> dict[str, Any]:
        """Wipes episodic logs/memories while keeping speaker, voice, and custom lore prefs intact."""
        removed_profiles = 0
        removed_logs = 0
        with self._lock:
            self._pending_recap_buffer.clear()
            targets = (
                [self._profile_path(profile_id)]
                if profile_id is not None
                else list(self.state_dir.glob("profile_*.json"))
            )
            for pf in targets:
                if pf.is_file():
                    pf.unlink()
                    removed_profiles += 1

            conn = sqlite3.connect(self.db_path)
            try:
                with conn:
                    if profile_id is not None:
                        pid = normalize_profile_id(profile_id)
                        conn.execute("DELETE FROM episodic_memories WHERE profile_id = ?", (pid,))
                        conn.execute("DELETE FROM episodic_fts WHERE profile_id = ?", (pid,))
                    else:
                        conn.execute("DELETE FROM episodic_memories")
                        conn.execute("DELETE FROM episodic_fts")
            finally:
                conn.close()

            if self.log_dir.is_dir():
                pattern = f"*_{normalize_profile_id(profile_id)}.jsonl" if profile_id else "*.jsonl"
                for lf in self.log_dir.glob(pattern):
                    try:
                        lf.unlink()
                        removed_logs += 1
                    except OSError:
                        pass
        return {
            "ok": True,
            "removed_profiles": removed_profiles,
            "removed_logs": removed_logs,
        }


_MEM_SINGLETON: EpisodicMemoryManager | None = None
_MEM_LOCK = threading.Lock()


def get_episodic_memory(cfg: SparkyServiceConfig | None = None) -> EpisodicMemoryManager:
    global _MEM_SINGLETON
    with _MEM_LOCK:
        if _MEM_SINGLETON is None:
            _MEM_SINGLETON = EpisodicMemoryManager(cfg=cfg)
        return _MEM_SINGLETON


def run_self_test() -> None:
    import tempfile

    with tempfile.TemporaryDirectory(prefix="sparky_mem_test_") as tmp:
        root = Path(tmp)
        mgr = EpisodicMemoryManager(
            state_dir=root / "state",
            log_dir=root / "logs",
            db_path=root / "state" / "ep.sqlite",
        )
        # 1. Lifepath isolation (StreetKid vs Nomad)
        mgr.record_turn(
            "gamedataLifePath.StreetKid",
            kind="chat",
            user_text="Remember Wakako's deal on that Kabuki shard",
            reply_text="Logged, recruit: if Wakako plays dirty in Kabuki, we pull the plug.",
            game_state={"district": "Kabuki"},
            allow_async_recap=False,
        )
        mgr.record_shard_read(
            "gamedataLifePath.StreetKid",
            "Kostya Entropy Report",
            "Kostya's relay broadcasts RABIDS packets from the Kabuki pier.",
            district="Kabuki",
        )
        mgr.record_turn(
            "gamedataLifePath.Nomad",
            kind="chat",
            user_text="Look at that dust storm across the Badlands",
            reply_text="Red grit and Aldecaldos watching our flank, just how it ought to be.",
            game_state={"district": "Badlands"},
            allow_async_recap=False,
        )

        sk_hits = mgr.retrieve_past_memories("StreetKid", "What did we read on the shard about Kostya and Entropy?")
        nom_hits = mgr.retrieve_past_memories("Nomad", "Kostya Entropy")
        assert sk_hits and "Entropy" in sk_hits[0]
        assert nom_hits == []

        # 2. Duplicate question detection
        assert is_duplicate_question("Who is Rache Bartmoss?", "who is rache bartmoss")
        assert not is_duplicate_question("Who is Rache Bartmoss?", "Where is the Afterlife?")

        # 3. Strict isolation between two distinct Nomad runs
        mgr.record_turn(
            "nomad_100111",
            kind="chat",
            user_text="What do you think of Evelyn Parker at Lizzie's?",
            reply_text="That Clouds doll is playing both sides of the net, rookie.",
            game_state={"district": "Kabuki", "playthrough_sec": 18000},
            allow_async_recap=False,
        )
        mgr.record_turn(
            "nomad_200222",
            kind="chat",
            user_text="Heading to Pacifica to check on the Voodoo Boys?",
            reply_text="Voodoo Boys give out zero freebies in Pacifica; keep your chrome sharp.",
            game_state={"district": "West Wind Estate", "playthrough_sec": 7000},
            allow_async_recap=False,
        )
        assert mgr.retrieve_past_memories("nomad_200222", "Evelyn Parker Lizzie's") == []
        nom1_evelyn = mgr.retrieve_past_memories("nomad_100111", "Evelyn Parker")
        assert nom1_evelyn and "Clouds" in nom1_evelyn[0]

        # 4. Causal timestamp filtering when reloading an earlier save of the same character
        assert mgr.retrieve_past_memories("nomad_100111", "Evelyn Parker", max_playthrough_sec=7000.0) == []
        past_ctx = mgr.build_memory_context("nomad_100111", "Evelyn Parker", current_playthrough_sec=7000.0)
        assert "Evelyn" not in past_ctx and "Clouds" not in past_ctx

        # 5. Selective profile clear
        res = mgr.clear_episodic_memory("StreetKid")
        assert res["ok"] and res["removed_profiles"] == 1
        assert mgr.retrieve_past_memories("StreetKid", "Kostya Entropy") == []
        assert mgr.retrieve_past_memories("Nomad", "dust storm Badlands") != []

        # 6. Rank progression (initial rookie -> full partner)
        assert resolve_veterancy_tier(
            {"act_phase": 1, "level": 3, "street_cred": 2, "season_stage": 100, "ep05_done": 0},
            45,
        ) == "rookie"
        assert resolve_veterancy_tier(
            {"act_phase": 2, "level": 10, "street_cred": 4, "season_stage": 600, "ep05_done": 1},
            45,
        ) == "partner"
        partner_ctx = mgr.build_memory_context(
            "nomad_200222",
            "hello",
            game_state={"act_phase": 2, "ep05_done": 1, "season_stage": 600},
        )
        assert "FULL PARTNER" in partner_ctx
        assert all(w not in partner_ctx.lower() for w in ("rookie", "recruit", "maggot"))
        rookie_ctx = mgr.build_memory_context(
            "nomad_100111",
            "hello",
            game_state={"act_phase": 1, "level": 3, "season_stage": 100, "ep05_done": 0},
        )
        assert "INITIAL STAGE" in rookie_ctx

        # 7. Deterministic milestone progression & exclusion of spont:* from FTS5
        mgr.record_turn(
            "nomad_300333",
            kind="spont:district_entered",
            user_text="[EVENT]",
            reply_text="Invented Project Icarus and Silas in Dogtown.",
            game_state={"district": "Little China", "playthrough_sec": 21000},
            allow_async_recap=False,
        )
        assert mgr.retrieve_past_memories("nomad_300333", "Project Icarus Silas") == []

        mgr.sync_progression_milestones(
            "nomad_300333",
            {
                "session_ready": True,
                "full_gameplay": True,
                "district": "Tom's Diner",
                "tracked_quest_title": "Playing for Time",
                "tracked_quest_obj": "Talk to Takemura.",
                "playthrough_sec": 21800,
            },
        )
        s2_added = mgr.sync_progression_milestones(
            "nomad_300333",
            {
                "session_ready": True,
                "full_gameplay": True,
                "district": "Little China",
                "tracked_quest_title": "Automatic Love",
                "tracked_quest_obj": "Head to Lizzie's Bar.",
                "playthrough_sec": 22180,
            },
        )
        assert any("Tom's Diner" in x and "Playing for Time" in x and "Automatic Love" in x for x in s2_added)
    print("=== EPISODIC MEMORY (EN) SELF-TEST: OK ===")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Episodic Memory Manager for S.P.A.R.K.Y. v2.0 (EN)")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        run_self_test()


if __name__ == "__main__":
    main()
