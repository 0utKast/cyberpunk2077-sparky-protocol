"""Memoria episódica persistente por partida/pasado de V y resúmenes asíncronos (C.H.I.S.P.A. v2.0)."""

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

from chispa_rt.companion_prefs import USER_BRIDGE_DIR
from chispa_rt.config import ChispaServiceConfig
from chispa_rt.lore_rag import strip_accents, tokenize_terms

DEFAULT_STATE_DIR = USER_BRIDGE_DIR / "state"
DEFAULT_LOG_DIR = USER_BRIDGE_DIR / "logs"
DEFAULT_EPISODIC_DB = DEFAULT_STATE_DIR / "episodic_index_es.sqlite"

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
    "distrito industrial norte",
    "northside",
    "pacifica",
    "dogtown",
    "japantown",
    "vista del rey",
    "el glen",
    "arroyo",
    "badlands",
)

_INTERROGATIVE_STARTS_ES = (
    "que ", "qué ", "quien ", "quién ", "quienes ", "quiénes ", "donde ", "dónde ",
    "cuando ", "cuándo ", "como ", "cómo ", "por que", "por qué", "cual ", "cuál ",
    "dime", "sabes", "conoces", "recuerdas", "puedes", "hay ", "tienes ",
)

DEFAULT_JOURNAL_BY_LIFEPATH = {
    "streetkid": [
        "Enlace Kiroshi activado en Night City con V, un buscavidas de Heywood con reflejos de calle.",
    ],
    "nomad": [
        "Enlace Kiroshi activado en Night City con V, ex-nómada curtido de las Badlands.",
    ],
    "corporate": [
        "Enlace Kiroshi activado en Night City con V, ex-agente de contrainteligencia corporativa que sabe cómo muerden los trajes.",
    ],
    "default": [
        "Enlace Kiroshi activado en Night City con V tras rescatar mi núcleo del maletín Zetatech.",
    ],
}

RECAP_SCHEMA = {
    "type": "object",
    "properties": {
        "session_summary": {
            "type": "string",
            "description": "1 frase corta en español en primera persona de CHISPA resumiendo los últimos sucesos con V.",
        },
        "journal": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Lista de hitos clave vividos con V (máx. 15 frases cortas en primera persona).",
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
    """Normaliza un perfil conservando el sufijo único de partida (<lifepath>_<mem_uid>)."""
    raw = strip_accents(str(raw_profile_id or "")).strip()
    m = _PROFILE_UID_RE.match(raw)
    if m:
        return f"{extract_base_lifepath(m.group(1))}_{m.group(2)}"
    return extract_base_lifepath(raw)


def resolve_profile_id(game_state: dict[str, Any] | None) -> str:
    """Resuelve el identificador único de partida combinando pasado de V y chispa_mem_uid."""
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
    """Determina si V ya superó las misiones iniciales ('partner') o sigue en etapa inicial ('rookie')."""
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
    if "?" in raw or "¿" in raw:
        return True
    s = re.sub(r"\s+", " ", strip_accents(raw))
    return s.startswith(_INTERROGATIVE_STARTS_ES)


def is_duplicate_question(q1: str, q2: str) -> bool:
    """Detecta si el jugador repitió la misma pregunta (para filtrar historial sin regañar)."""
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


def since_last_session_es(profile: dict[str, Any]) -> str:
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
        return f"hace {gap.days} día{'s' if gap.days > 1 else ''}"
    hours = gap.seconds // 3600
    if hours:
        return f"hace {hours} hora{'s' if hours > 1 else ''}"
    mins = max(1, gap.seconds // 60)
    return f"hace {mins} minuto{'s' if mins > 1 else ''}"


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
    """Gestiona diarios por pasado de V, búsqueda histórica FTS5 y resúmenes asíncronos."""

    def __init__(
        self,
        state_dir: Path = DEFAULT_STATE_DIR,
        log_dir: Path = DEFAULT_LOG_DIR,
        db_path: Path = DEFAULT_EPISODIC_DB,
        cfg: ChispaServiceConfig | None = None,
    ) -> None:
        self.state_dir = state_dir
        self.log_dir = log_dir
        self.db_path = db_path
        self.cfg = cfg or ChispaServiceConfig()
        self._lock = threading.Lock()
        self._recap_in_flight = False
        self._pending_recap_buffer: dict[str, list[dict[str, str]]] = {}
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
        p_path = self._profile_path(pid)
        default_obj: dict[str, Any] = {
            "profile_id": pid,
            "sync_level": 45,
            "turns_since_recap": 0,
            "total_turns": 0,
            "sessions": 0,
            "milestones": [{"pt": 0.0, "key": f"lp:{base_lp}", "text": txt} for txt in default_journal],
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
                if "journal_timed" not in loaded and isinstance(loaded.get("journal"), list):
                    merged["journal_timed"] = [
                        {"pt": 0.0, "text": str(x).strip()}
                        for x in loaded["journal"]
                        if str(x).strip()
                    ]
                if "milestones" not in loaded:
                    jt_src = merged.get("journal_timed") or []
                    ms: list[dict[str, Any]] = []
                    for i, item in enumerate(jt_src):
                        if isinstance(item, dict) and str(item.get("text") or "").strip():
                            ms.append(
                                {
                                    "pt": float(item.get("pt") or 0.0),
                                    "key": f"legacy:{i}",
                                    "text": str(item["text"]).strip(),
                                }
                            )
                    if not ms:
                        ms = list(default_obj["milestones"])
                    merged["milestones"] = ms[-MILESTONES_MAX:]
                if "session_notes" not in loaded or not isinstance(merged.get("session_notes"), list):
                    merged["session_notes"] = []
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
        """Registra determinísticamente un hito factual de campaña, misión o enclave sin depender del LLM."""
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
        """Sincroniza hitos reales desde la telemetría (Temporada 1, cambios de misión y lugares clave)."""
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

        # 1. Estado de la Temporada 1 de C.H.I.S.P.A.
        ep05_done = int(game_state.get("ep05_done") or 0)
        ep05_end = int(game_state.get("ep05_ending") or 0)
        season_stage = int(game_state.get("season_stage") or 0)
        if ep05_done > 0:
            end_labels = {
                1: "Socio Autónomo v1.0",
                2: "Filtración del archivo de Zetatech a Network 54",
                3: "Protocolo Armero (Última Palabra de Sargento)",
            }
            lbl = end_labels.get(ep05_end, "Temporada 1 completada")
            msg = f"Completamos toda nuestra campaña del Protocolo C.H.I.S.P.A. en Pacifica eligiendo: {lbl}."
            if self.record_world_event(
                pid,
                "milestone",
                msg,
                district=district or "Pacifica",
                quest="Protocolo C.H.I.S.P.A.",
                playthrough_sec=pt_sec,
                dedup_key="chispa_s1_done",
            ):
                added.append(msg)
        elif season_stage >= 100:
            msg = f"Arrancamos juntos la campaña táctica del Protocolo C.H.I.S.P.A. en Watson (fase {season_stage})."
            if self.record_world_event(
                pid,
                "milestone",
                msg,
                district=district or "Watson",
                quest="Protocolo C.H.I.S.P.A.",
                playthrough_sec=pt_sec,
                dedup_key="chispa_s1_active",
            ):
                added.append(msg)

        # 2. Transición determinista de misión activa (ej. Bailaré sobre tu tumba -> Al calor del amor en un bar)
        with self._lock:
            prof = self.load_profile(pid)
            prev_quest = str(prof.get("last_quest") or "").strip()
            prev_dist = str(prof.get("last_district") or "").strip()

        if q_title and prev_quest and strip_accents(q_title) != strip_accents(prev_quest):
            place = prev_dist or district or "Night City"
            obj_bit = f" ({q_obj})" if q_obj else ""
            q_msg = f"Ya completamos la fase en {place} (misión «{prev_quest}» superada) y nuestro objetivo actual pasó a ser «{q_title}»{obj_bit}."
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

        # 3. Primer paso por enclaves icónicos
        if district:
            dist_norm = strip_accents(district)
            if any(hub in dist_norm for hub in _ICONIC_HUBS):
                q_bit = f" durante «{q_title}»" if q_title else ""
                loc_msg = f"Visitamos {district}{q_bit}."
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
        """Indexa el texto de un pincho leído por V para poder comentarlo luego."""
        t_clean = (title or "").strip()
        b_clean = (text or "").strip()
        if not t_clean and not b_clean:
            return
        pid = normalize_profile_id(profile_id)
        pt_sec = float(playthrough_sec or 0.0)
        combined = f"Pincho leído '{t_clean}' (en {district or 'Night City'}): {b_clean[:360]}"
        with self._lock:
            self._insert_memory_item(
                pid,
                "shard",
                district,
                f"pincho shard {t_clean}",
                combined,
                playthrough_sec=pt_sec,
            )
            prof = self.load_profile(pid)
            note = f"V leyó el pincho «{t_clean}» en {district or 'Night City'}."
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
        """Registra chat real en memoria y logs; guarda espontáneos solo en JSONL sin contaminar FTS5."""
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
                loc_tag = f"{district or 'Night City'} | {quest or 'libre'}"
                mem_line = (
                    f"[{loc_tag}] V preguntó/comentó: «{user_text[:150]}»"
                    + (f" — Respuesta: {first_sent}" if first_sent else "")
                )
                self._insert_memory_item(pid, kind, district, tags, mem_line, playthrough_sec=pt_sec)

                prof["turns_since_recap"] = int(prof.get("turns_since_recap", 0)) + 1
                if kind == "chat":
                    prof["sync_level"] = min(100, int(prof.get("sync_level", 45)) + 1)
                prof["last_session"] = {
                    "ended": datetime.now().strftime("%Y-%m-%d %H:%M"),
                    "pt": pt_sec,
                    "summary": f"Última charla en {district or 'Night City'}: {first_sent[:95]}",
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
                name="chispa-recap",
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
        """Comprime los últimos turnos en segundo plano sin inventar hechos ni sobrescribir hitos."""
        try:
            with self._lock:
                prof = self.load_profile(profile_id)
                cur_notes = [str(n.get("text") or "") for n in (prof.get("session_notes") or []) if isinstance(n, dict)]

            pt_sec = max((float(t.get("pt") or 0.0) for t in turns), default=float(prof.get("last_playthrough_sec") or 0.0))
            transcript_lines = [
                f"- ({t.get('district') or 'Night City'} | {t.get('quest') or 'libre'}) V: {t['user']} -> CHISPA: {t['reply']}"
                for t in turns[-14:]
            ]
            system_msg = (
                "Eres el módulo de memoria factual de C.H.I.S.P.A. en Cyberpunk 2077. "
                "Condensa ÚNICAMENTE hechos explícitos de los turnos entregados en español y primera persona. "
                "PROHIBIDO inventar proyectos, personajes o facciones que no aparezcan en el texto. "
                "PROHIBIDO usar asteriscos (**), corchetes o numeración (1. 2.). "
                "Cada elemento de 'journal' debe ser una frase completa cerrada con punto final (máx. 8 notas)."
            )
            user_msg = (
                f"NOTAS PREVIAS:\n{json.dumps(cur_notes, ensure_ascii=False)}\n\n"
                f"CHARLAS RECIENTES DE V:\n" + "\n".join(transcript_lines)
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
        """Recupera recuerdos específicos de chat/hitos/pinchos por FTS5 BM25 y causalidad temporal."""
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
                          WHERE profile_id = ?
                            AND kind NOT LIKE 'spont:%'
                            AND (playthrough_sec <= ? OR playthrough_sec <= 0.0)
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
                      AND CAST(mem_id AS INTEGER) IN (
                          SELECT id FROM episodic_memories
                          WHERE profile_id = ? AND kind NOT LIKE 'spont:%'
                      )
                    ORDER BY rank_sc DESC
                    LIMIT ?
                    """,
                    (pid, fts_q, pid, top_k),
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
        """Devuelve bloque limpio de relación, hitos vividos y recuerdos causales de esa partida."""
        pid = normalize_profile_id(profile_id)
        base_lp = extract_base_lifepath(pid)
        prof = self.load_profile(pid)
        sync = int(prof.get("sync_level", 45))
        tier = resolve_veterancy_tier(game_state, sync)
        if tier == "partner":
            eff_sync = max(sync, 65)
            bond = f"Camaradería {eff_sync}/100 (SOCIO veterano de confianza)"
            rank_line = (
                "Trato actual: SOCIO veterano — Ya superó las misiones iniciales; "
                "trátale de igual a igual llamándole «socio», «V» o «compañero»."
            )
        else:
            bond = f"Camaradería {sync}/100 (Recluta en rodaje)"
            rank_line = (
                "Rango actual: ETAPA INICIAL — Aún en las misiones iniciales; "
                "puedes llamarle «recluta», «novato» o «V»."
            )

        lp_label = {
            "Nomad": "Nómada — Badlands",
            "StreetKid": "Buscavidas — Heywood",
            "Corpo": "Corporativo — ex Arasaka",
        }.get(base_lp, base_lp)
        parts = [f"Relación con V ({lp_label}): {bond}. {rank_line}"]
        last_s = prof.get("last_session")
        limit_pt = float(current_playthrough_sec) + 90.0 if current_playthrough_sec and current_playthrough_sec > 0.0 else None

        if (not compact) and isinstance(last_s, dict) and last_s.get("summary"):
            last_pt = float(last_s.get("pt") or 0.0)
            if limit_pt is None or last_pt <= limit_pt or last_pt <= 0.0:
                gap_txt = since_last_session_es(prof)
                if gap_txt:
                    parts.append(f"Última sesión ({gap_txt}): {last_s['summary']}")

        # Combinar hitos deterministas + notas de sesión respetando causalidad temporal
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
            parts.append(f"Último avance actual: {timeline_items[-1]}")
            return "\n".join(parts)

        if len(timeline_items) >= 2:
            earlier_bullets = "\n".join(f"- {item}" for item in timeline_items[-6:-1])
            parts.append(
                "Historia real vivida juntos en esta partida (usa estos hechos concretos cuando V pregunte por vuestras andanzas):\n"
                + earlier_bullets
                + f"\nÚltimo avance actual: {timeline_items[-1]}"
            )
        else:
            bullets = "\n".join(f"- {item}" for item in timeline_items[-6:])
            parts.append(
                "Historia real vivida juntos en esta partida (usa estos hechos concretos cuando V pregunte por vuestras andanzas):\n"
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
            if len(q_norm) >= 12 and q_norm in strip_accents(rec) and any(r in rec for r in ("V preguntó", "V dijo")):
                continue
            filtered_recalls.append(rec)
        if filtered_recalls:
            parts.append("Conversaciones y pinchos anteriores relevantes: " + " || ".join(filtered_recalls[:3]))
        return "\n".join(parts)

    def clear_episodic_memory(self, profile_id: str | None = None) -> dict[str, Any]:
        """Limpia memoria episódica y logs conservando ajustes, voz y lore personalizado."""
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


def get_episodic_memory(cfg: ChispaServiceConfig | None = None) -> EpisodicMemoryManager:
    global _MEM_SINGLETON
    with _MEM_LOCK:
        if _MEM_SINGLETON is None:
            _MEM_SINGLETON = EpisodicMemoryManager(cfg=cfg)
        return _MEM_SINGLETON


def run_self_test() -> None:
    import tempfile

    with tempfile.TemporaryDirectory(prefix="chispa_mem_test_") as tmp:
        root = Path(tmp)
        mgr = EpisodicMemoryManager(
            state_dir=root / "state",
            log_dir=root / "logs",
            db_path=root / "state" / "ep.sqlite",
        )
        # 1. Aislamiento por pasado de V (Buscavidas vs Nómada)
        mgr.record_turn(
            "gamedataLifePath.StreetKid",
            kind="chat",
            user_text="Recuerda el acuerdo con Wakako sobre el chip de Kabuki",
            reply_text="Anotado, recluta: si Wakako se pasa de lista en Kabuki cortamos el cable.",
            game_state={"district": "Kabuki"},
            allow_async_recap=False,
        )
        mgr.record_shard_read(
            "gamedataLifePath.StreetKid",
            "Informe de Kostya sobre Entropy",
            "El repetidor de Kostya transmite paquetes RABIDS desde el muelle.",
            district="Kabuki",
        )
        mgr.record_turn(
            "gamedataLifePath.Nomad",
            kind="chat",
            user_text="Mira esa tormenta en las Badlands",
            reply_text="Polvo rojo y Aldecaldos cubriendo el flanco, como debe ser.",
            game_state={"district": "Badlands"},
            allow_async_recap=False,
        )

        sk_hits = mgr.retrieve_past_memories("StreetKid", "¿Qué leímos en el pincho sobre Kostya y Entropy?")
        nom_hits = mgr.retrieve_past_memories("Nomad", "Kostya Entropy")
        assert sk_hits and "Entropy" in sk_hits[0], f"Esperaba recuerdo en StreetKid: {sk_hits}"
        assert nom_hits == [], f"No debería filtrarse memoria de StreetKid a Nomad: {nom_hits}"

        # 2. Detección de preguntas repetidas
        assert is_duplicate_question("¿Quién es Rache Bartmoss?", "quien es rache bartmoss")
        assert not is_duplicate_question("¿Quién es Rache Bartmoss?", "¿Dónde está el Afterlife?")

        # 3. Aislamiento estricto entre dos partidas distintas del MISMO lifepath (ej. dos Nómadas)
        mgr.record_turn(
            "nomad_100111",
            kind="chat",
            user_text="¿Qué opinas de Evelyn Parker en el Lizzie's?",
            reply_text="Esa muñeca de Clouds juega a dos bandas, recluta. Ojo con su trato.",
            game_state={"district": "Kabuki", "playthrough_sec": 18000},
            allow_async_recap=False,
        )
        mgr.record_turn(
            "nomad_200222",
            kind="chat",
            user_text="¿Vamos a Pacifica a buscar a los Vudús?",
            reply_text="En Pacifica los Vudús no regalan nada; prepara el cromo.",
            game_state={"district": "West Wind Estate", "playthrough_sec": 7000},
            allow_async_recap=False,
        )
        assert mgr.retrieve_past_memories("nomad_200222", "Evelyn Parker Lizzie's") == []
        nom1_evelyn = mgr.retrieve_past_memories("nomad_100111", "Evelyn Parker")
        assert nom1_evelyn and "Clouds" in nom1_evelyn[0]

        # 4. Filtro de causalidad temporal al cargar un guardado anterior del mismo Nómada
        assert mgr.retrieve_past_memories("nomad_100111", "Evelyn Parker", max_playthrough_sec=7000.0) == []
        past_ctx = mgr.build_memory_context("nomad_100111", "Evelyn Parker", current_playthrough_sec=7000.0)
        assert "Evelyn" not in past_ctx and "Clouds" not in past_ctx

        # 5. Limpieza selectiva de perfil sin romper el resto
        res = mgr.clear_episodic_memory("StreetKid")
        assert res["ok"] and res["removed_profiles"] == 1
        assert mgr.retrieve_past_memories("StreetKid", "Kostya Entropy") == []
        assert mgr.retrieve_past_memories("Nomad", "tormenta Badlands") != []

        # 6. Progresión de rango (recluta inicial -> socio tras misiones iniciales)
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
            "hola",
            game_state={"act_phase": 2, "ep05_done": 1, "season_stage": 600},
        )
        assert "SOCIO veterano" in partner_ctx
        assert "novato" not in partner_ctx.lower() and "recluta" not in partner_ctx.lower()
        rookie_ctx = mgr.build_memory_context(
            "nomad_100111",
            "hola",
            game_state={"act_phase": 1, "level": 3, "season_stage": 100, "ep05_done": 0},
        )
        assert "ETAPA INICIAL" in rookie_ctx

        # 7. Seguimiento determinista de hitos (Tom's Diner -> Al calor del amor en un bar) y exclusión de spont:*
        mgr.record_turn(
            "nomad_300333",
            kind="spont:district_entered",
            user_text="[EVENTO]",
            reply_text="Proyecto ficticio Xylo inventado en Dogtown.",
            game_state={"district": "Little China", "playthrough_sec": 21000},
            allow_async_recap=False,
        )
        assert mgr.retrieve_past_memories("nomad_300333", "Xylo Dogtown") == []
        s1_added = mgr.sync_progression_milestones(
            "nomad_300333",
            {
                "session_ready": True,
                "full_gameplay": True,
                "mem_uid": 300333,
                "lifepath": "Nomad",
                "ep05_done": 1,
                "ep05_ending": 1,
                "district": "Tom's Diner",
                "tracked_quest_title": "Bailaré sobre tu tumba",
                "playthrough_sec": 21200,
            },
        )
        assert any("Socio Autónomo" in x for x in s1_added)
        s2_added = mgr.sync_progression_milestones(
            "nomad_300333",
            {
                "session_ready": True,
                "full_gameplay": True,
                "mem_uid": 300333,
                "lifepath": "Nomad",
                "ep05_done": 1,
                "ep05_ending": 1,
                "district": "Little China",
                "tracked_quest_title": "Al calor del amor en un bar",
                "tracked_quest_obj": "Ve a Lizzie's Bar.",
                "playthrough_sec": 22000,
            },
        )
        assert any("Bailaré sobre tu tumba" in x and "Al calor del amor en un bar" in x for x in s2_added)
    print("=== EPISODIC MEMORY SELF-TEST: OK ===")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Memoria episódica C.H.I.S.P.A. v2.0")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        run_self_test()


if __name__ == "__main__":
    main()
