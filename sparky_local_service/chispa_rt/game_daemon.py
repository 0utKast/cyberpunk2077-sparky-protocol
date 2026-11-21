"""Demonio puente en tiempo real entre Cyberpunk 2077 (CET IPC) y la IA local de C.H.I.S.P.A."""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import queue
import re
import sys
import tempfile
import threading
import time
from pathlib import Path
from typing import Any, Callable

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

import numpy as np

from chispa_rt.audio_player import (
    WASAPIStreamPlayer,
    list_output_devices,
    load_audio_prefs,
    resolve_default_output_index,
)
from chispa_rt.companion_prefs import CompanionPrefs, load_companion_prefs
from chispa_rt.config import ChispaServiceConfig, get_gpu_vram_status
from chispa_rt.episodic_memory import (
    EpisodicMemoryManager,
    get_episodic_memory,
    normalize_profile_id,
    resolve_profile_id,
    resolve_veterancy_tier,
)
from chispa_rt.llm_ollama import OllamaChispaClient
from chispa_rt.lore_rag import (
    HybridCyberpunkRAG,
    format_rag_dossier,
    get_hybrid_rag,
    strip_accents,
)
from chispa_rt.spontaneous import (
    SpontaneousDirector,
    SpontaneousEvent,
    repeats_recent,
)
from chispa_rt.tts_backends import TTSBackend, create_tts_backend
from chispa_rt.wiki_online import lookup_wiki_online

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

WORKSPACE_ROOT = Path(__file__).resolve().parent.parent.parent
TACTICAL_AUTO_PROMPT = (
    "Analiza brevemente mi situación actual según la telemetría Kiroshi en vivo "
    "(distrito, misión activa, combate, salud, arma o blanco escaneado) y dame una réplica táctica directa."
)


def _detect_vk186_is_acute() -> bool:
    """Detecta si VK_OEM_1 (186) corresponde a tilde aguda (teclado ES-LA frente a ES-ES)."""
    if sys.platform != "win32":
        return False
    try:
        import ctypes

        mapped = int(ctypes.windll.user32.MapVirtualKeyW(186, 2))
        return bool(mapped & 0x80000000) and (mapped & 0xFFFF) == 0x00B4
    except Exception:
        return False


def _is_cp2077_dir(path: Path) -> bool:
    """Comprueba si un directorio corresponde a la raíz real de Cyberpunk 2077."""
    try:
        return (path / "bin" / "x64" / "Cyberpunk2077.exe").is_file()
    except OSError:
        return False


def _discover_cp2077_game_dir() -> Path | None:
    """Detecta Cyberpunk 2077 de forma autónoma (override, carpeta relativa, Steam, GOG, Epic)."""
    service_root = Path(__file__).resolve().parent.parent

    # 1. Variable de entorno explícita
    env_game = os.environ.get("CP2077_GAME_DIR", "").strip().strip('"')
    if env_game:
        cand = Path(env_game)
        if _is_cp2077_dir(cand):
            return cand

    # 2. Archivo de ruta personalizada ~/.chispa_ai_bridge/game_path.txt
    override_txt = Path.home() / ".chispa_ai_bridge" / "game_path.txt"
    if override_txt.is_file():
        try:
            raw = override_txt.read_text(encoding="utf-8-sig").strip().splitlines()
            if raw:
                cand = Path(raw[0].strip().strip('"'))
                if _is_cp2077_dir(cand):
                    return cand
        except OSError:
            pass

    # 3. Instalado dentro o junto a la carpeta del juego
    for cand in (service_root.parent, service_root):
        if _is_cp2077_dir(cand):
            return cand

    # 4. Registro de Windows: Steam + libraryfolders.vdf
    steam_roots: list[Path] = []
    if sys.platform == "win32":
        try:
            import winreg

            for hkey, subkey, valname in (
                (winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam", "SteamPath"),
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Valve\Steam", "InstallPath"),
                (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Valve\Steam", "InstallPath"),
            ):
                try:
                    with winreg.OpenKey(hkey, subkey) as k:
                        val, _ = winreg.QueryValueEx(k, valname)
                        if val:
                            sp = Path(str(val))
                            if sp not in steam_roots:
                                steam_roots.append(sp)
                except OSError:
                    continue

            # 5. Registro de Windows: GOG Galaxy
            for gog_subkey in (
                r"SOFTWARE\WOW6432Node\GOG.com\Games\1423049311",
                r"SOFTWARE\GOG.com\Games\1423049311",
                r"SOFTWARE\WOW6432Node\GOG.com\Games\2093619782",
                r"SOFTWARE\GOG.com\Games\2093619782",
            ):
                try:
                    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, gog_subkey) as k:
                        for vname in ("path", "PATH"):
                            try:
                                val, _ = winreg.QueryValueEx(k, vname)
                                if val and _is_cp2077_dir(Path(str(val))):
                                    return Path(str(val))
                            except OSError:
                                continue
                except OSError:
                    continue
        except ImportError:
            pass

    default_steam = Path(r"C:\Program Files (x86)\Steam")
    if default_steam not in steam_roots:
        steam_roots.append(default_steam)

    steam_libs: list[Path] = []
    for sp in steam_roots:
        if sp not in steam_libs:
            steam_libs.append(sp)
        vdf = sp / "steamapps" / "libraryfolders.vdf"
        if vdf.is_file():
            try:
                vdf_text = vdf.read_text(encoding="utf-8", errors="replace")
                for m in re.finditer(r'"path"\s+"([^"]+)"', vdf_text):
                    lib = Path(m.group(1).replace("\\\\", "\\"))
                    if lib not in steam_libs:
                        steam_libs.append(lib)
            except OSError:
                pass

    for lib in steam_libs:
        cand = lib / "steamapps" / "common" / "Cyberpunk 2077"
        if _is_cp2077_dir(cand):
            return cand
        acf = lib / "steamapps" / "appmanifest_1091500.acf"
        if acf.is_file():
            try:
                m = re.search(r'"installdir"\s+"([^"]+)"', acf.read_text(encoding="utf-8", errors="replace"))
                if m:
                    cand_acf = lib / "steamapps" / "common" / m.group(1)
                    if _is_cp2077_dir(cand_acf):
                        return cand_acf
            except OSError:
                pass

    # 6. Manifiestos de Epic Games Launcher
    prog_data = Path(os.environ.get("ProgramData", r"C:\ProgramData"))
    epic_dir = prog_data / "Epic" / "EpicGamesLauncher" / "Data" / "Manifests"
    if epic_dir.is_dir():
        for item_file in sorted(epic_dir.glob("*.item")):
            try:
                meta = json.loads(item_file.read_text(encoding="utf-8", errors="replace"))
                if "cyberpunk 2077" in str(meta.get("DisplayName", "")).lower():
                    loc = Path(str(meta.get("InstallLocation", "")))
                    if _is_cp2077_dir(loc):
                        return loc
            except Exception:
                continue

    # 7. Búsqueda en unidades comunes (C: a H:)
    for drv in "CDEFGH":
        for rel in (
            r"Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077",
            r"Steam\steamapps\common\Cyberpunk 2077",
            r"SteamLibrary\steamapps\common\Cyberpunk 2077",
            r"GOG Games\Cyberpunk 2077",
            r"Program Files (x86)\GOG Galaxy\Games\Cyberpunk 2077",
            r"Games\Cyberpunk 2077",
            r"Program Files\Epic Games\Cyberpunk2077",
        ):
            cand = Path(f"{drv}:\\{rel}")
            if _is_cp2077_dir(cand):
                return cand

    # 8. Respaldo opcional dentro del workspace de desarrollo
    try:
        if (WORKSPACE_ROOT / "scripts" / "cp2077_config.py").is_file():
            if str(WORKSPACE_ROOT) not in sys.path:
                sys.path.insert(0, str(WORKSPACE_ROOT))
            from scripts import cp2077_config as cp_cfg  # type: ignore[import-not-found]

            info = cp_cfg.discover_steam_cp2077()
            gd = info.get("game_dir")
            if info.get("found") and gd and _is_cp2077_dir(Path(str(gd))):
                return Path(str(gd))
    except Exception:
        pass
    return None


def discover_ipc_dir(explicit_dir: str | None = None) -> Path:
    """Localiza o crea la carpeta ipc/ dentro de CET Mods/ChispaNC en Cyberpunk 2077."""
    raw_explicit = explicit_dir or os.environ.get("CHISPA_IPC_DIR", "").strip()
    if raw_explicit:
        ipc = Path(raw_explicit.strip('"'))
        ipc.mkdir(parents=True, exist_ok=True)
        return ipc

    game_dir = _discover_cp2077_game_dir()
    if game_dir is None:
        override_hint = Path.home() / ".chispa_ai_bridge" / "game_path.txt"
        raise FileNotFoundError(
            "No se localizó automáticamente Cyberpunk 2077. "
            f"Pasa '--ipc-dir <ruta>' o guarda la ruta raíz del juego en: {override_hint}"
        )
    ipc = (
        game_dir
        / "bin"
        / "x64"
        / "plugins"
        / "cyber_engine_tweaks"
        / "mods"
        / "ChispaNC"
        / "ipc"
    )
    ipc.mkdir(parents=True, exist_ok=True)
    return ipc


def _read_json_safe(path: Path) -> dict[str, Any] | None:
    """Lee un archivo JSON tolerando contención transitoria en Windows."""
    if not path.is_file():
        return None
    for attempt in range(4):
        try:
            raw = path.read_text(encoding="utf-8")
            if not raw.strip():
                return None
            obj = json.loads(raw)
            return obj if isinstance(obj, dict) else None
        except PermissionError:
            if attempt < 3:
                time.sleep(0.01)
        except Exception:
            return None
    return None


def _write_json_atomic(path: Path, data: dict[str, Any]) -> None:
    """Escribe JSON de forma atómica con MoveFileExW (Path.replace) en Windows."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    payload = json.dumps(data, ensure_ascii=False)
    for attempt in range(5):
        try:
            tmp.write_text(payload, encoding="utf-8")
            tmp.replace(path)
            return
        except PermissionError:
            if attempt < 4:
                time.sleep(0.012)
            else:
                raise


def _lifepath_label(raw_lp: str | None) -> str:
    pid = normalize_profile_id(raw_lp)
    return {
        "streetkid": "Buscavidas",
        "nomad": "Nómada",
        "corporate": "Corporativo",
    }.get(pid, "")


def format_telemetry_summary(state: dict[str, Any] | None) -> str:
    """Convierte state.json de Redscript en un resumen táctico conciso para Ollama."""
    if not state:
        return "Sin telemetría reciente del HUD."

    parts: list[str] = []
    lp_label = _lifepath_label(state.get("lifepath"))
    lvl = state.get("level")
    sc = state.get("street_cred")
    if lp_label or lvl:
        bio_bits = [lp_label] if lp_label else []
        if lvl:
            bio_bits.append(f"Niv.{lvl}")
        if sc:
            bio_bits.append(f"Cred.{sc}")
        parts.append("V (" + " ".join(bio_bits) + ")")

    district = str(state.get("district") or "").strip()
    hour = str(state.get("game_hour") or "").strip()
    if district:
        parts.append(f"Distrito: {district}" + (f" ({hour})" if hour else ""))
    elif hour:
        parts.append(f"Hora: {hour}")

    hp = state.get("hp_pct")
    if hp is not None:
        parts.append(f"Salud: {hp}%")

    parts.append("En combate activo" if state.get("in_combat") else "Fuera de combate")
    if state.get("in_vehicle"):
        parts.append("En vehículo")

    stars = int(state.get("wanted_stars") or 0)
    if stars >= 5:
        parts.append("ALERTA MAXTAC (5 estrellas)")
    elif stars > 0:
        parts.append(f"Alerta NCPD: {stars} estrellas")

    weapon = str(state.get("weapon") or "").strip()
    if weapon:
        parts.append(f"Arma: {weapon}")

    scanned = str(state.get("scanned_target") or "").strip()
    if scanned:
        boss_tag = " [JEFE/ÉLITE]" if state.get("scanned_is_boss") else ""
        parts.append(f"Escaneado: {scanned}{boss_tag}")

    q_title = str(state.get("tracked_quest_title") or "").strip()
    q_obj = str(state.get("tracked_quest_obj") or "").strip()
    if q_title:
        q_str = f"Misión activa: {q_title}"
        if q_obj:
            q_str += f" -> {q_obj}"
        parts.append(q_str)

    sh_title = str(state.get("last_shard_title") or "").strip()
    if sh_title:
        parts.append(f"Último pincho leído: {sh_title}")

    if int(state.get("ep05_done") or 0) > 0:
        ending = int(state.get("ep05_ending") or 0)
        parts.append(f"Campaña CHISPA Temp.1 completada (final={ending})")
    else:
        st = int(state.get("season_stage") or 0)
        if st > 0:
            parts.append(f"Campaña CHISPA fase {st}")

    tier = resolve_veterancy_tier(state)
    if tier == "partner":
        parts.append("Trato a V: socio veterano (llámale «socio», «V» o «compañero»)")
    else:
        parts.append("Trato a V: etapa inicial (recluta/novato)")

    return " | ".join(parts)


def build_user_prompt(action: str, raw_text: str) -> str:
    """Traduce la acción de jugador/hotkey a la entrada real de Ollama."""
    txt = raw_text.strip()
    if action == "tactical" or txt == "[AUTO_SITUACION]":
        return TACTICAL_AUTO_PROMPT
    return txt


class ChispaGameDaemon:
    """Bucle de escucha IPC, RAG Híbrido, Memoria Episódica, Espontaneidad y Audio/HUD."""

    def __init__(
        self,
        cfg: ChispaServiceConfig,
        ipc_dir: Path,
        ollama_factory: Callable[[ChispaServiceConfig], Any] = OllamaChispaClient,
        tts_factory: Callable[[str, ChispaServiceConfig], TTSBackend] = create_tts_backend,
        player: Any | None = None,
        speaker_label: str | None = None,
        rag: HybridCyberpunkRAG | None = None,
        memory: EpisodicMemoryManager | None = None,
        spontaneous: SpontaneousDirector | None = None,
        prefs_loader: Callable[[], CompanionPrefs] = load_companion_prefs,
    ) -> None:
        self.cfg = cfg
        self.ipc_dir = ipc_dir
        self.state_path = ipc_dir / "state.json"
        self.req_path = ipc_dir / "player_req.json"
        self.inbox_path = ipc_dir / "inbox.json"
        self.heartbeat_path = ipc_dir / "heartbeat.json"

        prefs = load_audio_prefs()
        saved_tts = str(prefs.get("tts_engine") or cfg.tts_engine)
        if saved_tts not in ("f5_clone", "f5_clean", "kokoro_sergeant", "kokoro_onnx", "qwen3_clone"):
            saved_tts = cfg.tts_engine
        self.tts_name = saved_tts

        if player is None:
            out_devs = list_output_devices()
            def_out_idx = resolve_default_output_index(out_devs)
            def_dev = next((d for d in out_devs if d.index == def_out_idx), None)
            self.speaker_label = speaker_label or (def_dev.name if def_dev else "WASAPI Default")
            self.player = WASAPIStreamPlayer(sample_rate=cfg.sample_rate, device_index=def_out_idx)
        else:
            self.speaker_label = speaker_label or "Custom Audio"
            self.player = player

        self.ollama = ollama_factory(cfg)
        self.tts: TTSBackend = tts_factory(self.tts_name, cfg)
        self.rag = rag if rag is not None else get_hybrid_rag(cfg)
        self.memory = memory if memory is not None else get_episodic_memory(cfg)
        self.spontaneous = spontaneous if spontaneous is not None else SpontaneousDirector()
        self._load_companion_prefs = prefs_loader

        self.session_id = f"{os.getpid()}_{int(time.time() * 1000)}"
        self.msg_id = 0
        self.reply_seq = 0
        self.last_cet_session = ""
        self.last_req_id = 0
        self._indexed_shard_seq = 0
        self._active_profile_id = ""
        self._last_session_load_seq = 0
        self._last_playthrough_sec = 0.0
        self._history_by_profile: dict[str, list[dict[str, str]]] = {}
        self.history: list[dict[str, str]] = []
        self._stop_event = threading.Event()
        self._heartbeat_thread: threading.Thread | None = None

    def _sync_session_and_profile(self, game_state: dict[str, Any] | None) -> str:
        """Aísla RAM, cursores y espontaneidad al detectar cambio de partida o personaje en caliente."""
        if not game_state:
            return self._active_profile_id or "default"
        if not game_state.get("session_ready") or not game_state.get("full_gameplay"):
            return self._active_profile_id or resolve_profile_id(game_state)

        pid = resolve_profile_id(game_state)
        load_seq = int(game_state.get("session_load_seq") or 0)
        try:
            pt_sec = float(game_state.get("playthrough_sec") or 0.0)
        except (TypeError, ValueError):
            pt_sec = 0.0

        if self._active_profile_id and pid != self._active_profile_id:
            self._history_by_profile[self._active_profile_id] = list(self.history[-12:])
            self.history = list(self._history_by_profile.get(pid, []))
            self.player.interrupt()
            self._indexed_shard_seq = int(game_state.get("last_shard_seq") or 0)
            self.spontaneous.reset_for_save_load(game_state, clear_spoken=True)
            print(f"[CHISPA v2.0] Cambio de partida detectado -> Perfil de memoria aislado: {pid}")
        elif self._active_profile_id == pid:
            save_reloaded = (
                self._last_session_load_seq > 0
                and load_seq > 0
                and load_seq != self._last_session_load_seq
            )
            time_rewound = (
                self._last_playthrough_sec > 0.0
                and pt_sec > 0.0
                and (pt_sec + 180.0) < self._last_playthrough_sec
            )
            if save_reloaded or time_rewound:
                if time_rewound:
                    self.history = []
                    self._history_by_profile[pid] = []
                self._indexed_shard_seq = int(game_state.get("last_shard_seq") or 0)
                self.spontaneous.reset_for_save_load(game_state, clear_spoken=False)

        self._active_profile_id = pid
        if load_seq > 0:
            self._last_session_load_seq = load_seq
        if pt_sec > 0.0:
            self._last_playthrough_sec = pt_sec
        return pid

    def warmup(self) -> None:
        """Precarga Ollama, RAG Híbrido (0 MB VRAM) y TTS; sincroniza cursores iniciales."""
        print(f"[CHISPA v2.0] IPC: {self.ipc_dir}")
        print(f"[CHISPA v2.0] Salida WASAPI: {self.speaker_label}")
        print(
            f"[CHISPA v2.0] Enciclopedia RAG: {self.rag.doc_count} fichas "
            f"(Vectores CPU: {'ACTIVOS' if self.rag.vectors_active else 'solo FTS5'}, 0 MB VRAM)"
        )
        cp = self._load_companion_prefs()
        print(
            f"[CHISPA v2.0] Espontaneidad: {cp.spontaneous_mode} | "
            f"Wiki Online: {'ACTIVADA por usuario' if cp.enable_online_wiki else 'DESACTIVADA (solo local)'}"
        )
        ollama_opts = self.cfg.ollama_base_options()
        gpu_txt = f"híbrido num_gpu={ollama_opts['num_gpu']}" if "num_gpu" in ollama_opts else "100% GPU"
        print(f"[CHISPA v2.0] Precargando LLM ({self.cfg.llm_model} | ctx={ollama_opts['num_ctx']}, {gpu_txt})...")
        self.ollama.ensure_model_loaded()
        print(f"[CHISPA v2.0] Precargando TTS ({self.tts_name})...")
        t_tts = self.tts.warmup()
        print(f"[CHISPA v2.0] TTS listo ({self.tts.device_label}, warmup={t_tts:.2f}s)")

        existing_req = _read_json_safe(self.req_path)
        if existing_req:
            self.last_cet_session = str(existing_req.get("cet_session") or "")
            self.last_req_id = int(existing_req.get("req_id") or 0)

        existing_state = _read_json_safe(self.state_path)
        if existing_state:
            pid0 = self._sync_session_and_profile(existing_state)
            self._indexed_shard_seq = int(existing_state.get("last_shard_seq") or 0)
            self.memory.sync_progression_milestones(pid0, existing_state)
            self.spontaneous.evaluate(existing_state, prefs=cp)

        self._publish_inbox(state=0, subtitle="", duration=0.0, full_reply="", reply_seq=0)
        st = get_gpu_vram_status()
        if st.nvml_ok:
            print(f"[CHISPA v2.0] VRAM GPU: {st.used_mib}/{st.total_mib} MiB (libre: {st.free_mib} MiB)")

    def _publish_inbox(
        self,
        state: int,
        subtitle: str,
        duration: float,
        full_reply: str = "",
        reply_seq: int = 0,
    ) -> None:
        self.msg_id += 1
        _write_json_atomic(
            self.inbox_path,
            {
                "session_id": self.session_id,
                "msg_id": self.msg_id,
                "state": int(state),
                "subtitle": subtitle,
                "duration": round(float(duration), 2),
                "full_reply": full_reply,
                "reply_seq": int(reply_seq),
                "ts": round(time.time(), 3),
            },
        )

    def _heartbeat_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                _write_json_atomic(
                    self.heartbeat_path,
                    {
                        "session_id": self.session_id,
                        "ts": int(time.time()),
                        "llm": self.cfg.llm_model,
                        "tts": self.tts_name,
                        "speaker": self.speaker_label,
                        "vk186_acute": _detect_vk186_is_acute(),
                    },
                )
            except Exception:
                pass
            self._stop_event.wait(1.0)

    def start_heartbeat(self) -> None:
        if self._heartbeat_thread is None or not self._heartbeat_thread.is_alive():
            self._heartbeat_thread = threading.Thread(
                target=self._heartbeat_loop, name="chispa-heartbeat", daemon=True
            )
            self._heartbeat_thread.start()

    def _poll_new_request(self) -> dict[str, Any] | None:
        req = _read_json_safe(self.req_path)
        if not req:
            return None
        cet_sess = str(req.get("cet_session") or "")
        req_id = int(req.get("req_id") or 0)
        if req_id <= 0:
            return None
        if cet_sess != self.last_cet_session:
            return req
        if req_id > self.last_req_id:
            return req
        return None

    def _commit_request_seen(self, req: dict[str, Any]) -> None:
        self.last_cet_session = str(req.get("cet_session") or "")
        self.last_req_id = int(req.get("req_id") or 0)

    def _sync_shards_from_state(self, game_state: dict[str, Any] | None) -> None:
        if not game_state:
            return
        sh_seq = int(game_state.get("last_shard_seq") or 0)
        if sh_seq > self._indexed_shard_seq:
            self._indexed_shard_seq = sh_seq
            sh_title = str(game_state.get("last_shard_title") or "").strip()
            sh_text = str(game_state.get("last_shard_text") or "").strip()
            if sh_title or sh_text:
                pid = resolve_profile_id(game_state)
                self.memory.record_shard_read(
                    pid,
                    sh_title,
                    sh_text,
                    district=str(game_state.get("district") or ""),
                    playthrough_sec=float(game_state.get("playthrough_sec") or 0.0),
                )

    def _read_live_state_with_staleness(self, max_age_s: float = 2.6) -> dict[str, Any] | None:
        state = _read_json_safe(self.state_path)
        if not state:
            return None
        try:
            age_s = max(0.0, time.time() - float(self.state_path.stat().st_mtime))
        except OSError:
            age_s = 0.0
        if age_s > max_age_s:
            state["state_stale"] = True
        return state

    def _should_abort_playback(self, *, is_spontaneous: bool = False) -> tuple[bool, dict[str, Any] | None]:
        if self._stop_event.is_set():
            return True, None
        nxt = self._poll_new_request()
        if nxt is not None:
            return True, nxt
        game_state = self._read_live_state_with_staleness()
        if game_state:
            if (
                not game_state.get("session_ready", True)
                or bool(game_state.get("blocking_scene_or_call"))
                or bool(game_state.get("loading_or_fast_travel"))
            ):
                return True, None
            if is_spontaneous and (
                not game_state.get("full_gameplay", True)
                or bool(game_state.get("in_menu"))
                or bool(game_state.get("shard_popup_open"))
                or bool(game_state.get("state_stale"))
            ):
                return True, None
        return False, None

    def _assemble_context_dossier(
        self,
        query: str,
        game_state: dict[str, Any] | None,
        prefs: CompanionPrefs,
        *,
        is_spontaneous: bool = False,
        allow_wiki: bool = True,
    ) -> str:
        st = game_state or {}
        profile_id = resolve_profile_id(st)
        district = str(st.get("district") or "").strip()
        tracked_title = str(st.get("tracked_quest_title") or "").strip()
        try:
            pt_sec = float(st.get("playthrough_sec") or 0.0)
        except (TypeError, ValueError):
            pt_sec = 0.0

        prev_user_q = ""
        for turn in reversed(self.history):
            if turn.get("role") == "user":
                prev_user_q = str(turn.get("content") or "")
                break

        q_norm = strip_accents(query)
        is_memory_query = any(
            h in q_norm
            for h in ("recuerdas", "hemos vivido", "vivido juntos", "nuestra historia", "hemos hecho", "andanzas", "aventuras")
        )
        top_k = 2 if (is_spontaneous or is_memory_query) else 4
        rag_docs = self.rag.retrieve(
            query=query,
            prev_query="" if is_spontaneous else prev_user_q,
            game_state=st,
            top_k=top_k,
        )
        blocks: list[str] = []
        mem_txt = self.memory.build_memory_context(
            profile_id,
            query,
            district=district,
            current_playthrough_sec=pt_sec if pt_sec > 0.0 else None,
            game_state=game_state,
            compact=is_spontaneous,
        )
        if mem_txt:
            blocks.append(mem_txt)

        rag_txt = format_rag_dossier(
            rag_docs,
            max_total_chars=800 if is_memory_query else (1050 if is_spontaneous else 1750),
        )
        if rag_txt:
            blocks.append("Datos verificados relevantes de Night City:\n" + rag_txt)

        if allow_wiki and not is_spontaneous and prefs.enable_online_wiki:
            wiki_txt = lookup_wiki_online(
                query,
                local_top_score=self.rag.last_top_score,
                tracked_quest_title=tracked_title,
                prefs=prefs,
            )
            if wiki_txt:
                blocks.append(wiki_txt)

        if is_spontaneous and self.spontaneous.recent_spoken_lines:
            recent_ban = " | ".join(self.spontaneous.recent_spoken_lines[-5:])
            blocks.append(f"PROHIBIDO REPETIR ESTAS FRASES RECIENTES: {recent_ban}")

        return "\n".join(blocks)

    def _stream_llm_and_speak(
        self,
        *,
        user_prompt: str,
        game_state: dict[str, Any] | None,
        telemetry_summary: str,
        context_dossier: str,
        max_predict_tokens: int,
        temperature: float | None = None,
        is_spontaneous: bool = False,
        spont_event_type: str = "",
        raw_user_text: str = "",
    ) -> dict[str, Any] | None:
        t0 = time.perf_counter()
        clause_q: queue.Queue[str | None | BaseException] = queue.Queue()
        cancel_llm = threading.Event()
        llm_stats: dict[str, float] = {"ttft_ms": 0.0}
        history_for_turn = self.history[-6:] if is_spontaneous else self.history

        def _llm_producer() -> None:
            try:
                kwargs: dict[str, Any] = {
                    "game_context_summary": telemetry_summary,
                }
                if context_dossier:
                    kwargs["context_dossier"] = context_dossier
                kwargs["max_predict_tokens"] = max_predict_tokens
                if temperature is not None:
                    kwargs["temperature"] = temperature
                try:
                    stream = self.ollama.stream_clauses(history_for_turn, user_prompt, **kwargs)
                except TypeError:
                    # Respaldo limpio para mocks mínimos en pruebas unitarias
                    stream = self.ollama.stream_clauses(
                        history_for_turn,
                        user_prompt,
                        game_context_summary=telemetry_summary,
                    )
                for clause in stream:
                    if cancel_llm.is_set():
                        break
                    if llm_stats["ttft_ms"] == 0.0:
                        llm_stats["ttft_ms"] = clause.ttft_ms
                    clause_q.put(clause.text)
            except BaseException as exc:
                clause_q.put(exc)
            finally:
                clause_q.put(None)

        threading.Thread(target=_llm_producer, name="chispa-llm-stream", daemon=True).start()

        clauses: list[str] = []
        aborted = False
        pending_next: dict[str, Any] | None = None
        first_audio_ms: float | None = None

        def _poll_next_clause_nonblocking(llm_finished: bool) -> tuple[str | None, bool, BaseException | None]:
            if llm_finished:
                return None, True, None
            try:
                item = clause_q.get_nowait()
            except queue.Empty:
                return None, False, None
            if isinstance(item, BaseException):
                return None, True, item
            if item is None:
                return None, True, None
            return item, False, None

        def _wait_next_clause_blocking(
            llm_finished: bool,
        ) -> tuple[str | None, bool, BaseException | None, bool, dict[str, Any] | None]:
            while not llm_finished:
                abort_now, req_now = self._should_abort_playback()
                if abort_now:
                    return None, True, None, True, req_now
                try:
                    item = clause_q.get(timeout=0.04)
                except queue.Empty:
                    continue
                if isinstance(item, BaseException):
                    return None, True, item, False, None
                if item is None:
                    return None, True, None, False, None
                return item, False, None, False, None
            return None, True, None, False, None

        with concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="chispa-tts") as tts_pool:
            def _synth(txt: str) -> tuple[str, np.ndarray, int]:
                wav, sr = self.tts.synthesize(txt)
                return txt, wav, sr

            first_item, llm_done, err, aborted, pending_next = _wait_next_clause_blocking(False)
            if err is not None:
                raise RuntimeError(f"Error en Ollama: {err}") from err

            next_future: concurrent.futures.Future[tuple[str, np.ndarray, int]] | None = None
            if first_item is not None and not aborted:
                next_future = tts_pool.submit(_synth, first_item)

            idx = 0
            while next_future is not None and not aborted:
                while not next_future.done():
                    aborted, pending_next = self._should_abort_playback()
                    if aborted:
                        break
                    time.sleep(0.015)

                if aborted:
                    cancel_llm.set()
                    next_future.cancel()
                    break

                c_text, wav, sr = next_future.result()
                next_future = None
                clauses.append(c_text)
                idx += 1

                if not llm_done:
                    nxt_txt, llm_done, err = _poll_next_clause_nonblocking(llm_done)
                    if err is not None:
                        cancel_llm.set()
                        raise RuntimeError(f"Error en Ollama: {err}") from err
                    if nxt_txt is not None:
                        next_future = tts_pool.submit(_synth, nxt_txt)

                dur_s = float(wav.size) / float(sr) if sr > 0 and wav.size > 0 else 2.5
                if wav.size > 0:
                    if first_audio_ms is None:
                        first_audio_ms = (time.perf_counter() - t0) * 1000.0
                    self.player.enqueue(wav)

                self._publish_inbox(
                    state=1 if idx == 1 else 2,
                    subtitle=c_text,
                    duration=max(2.5, dur_s + 0.8),
                )
                print(f"  [CHISPA #{idx}] {c_text} ({dur_s:.2f}s)")

                while not self.player.wait_until_done(timeout=0.04):
                    aborted, pending_next = self._should_abort_playback()
                    if aborted:
                        self.player.interrupt()
                        break
                    if next_future is None and not llm_done:
                        nxt_txt, llm_done, err = _poll_next_clause_nonblocking(llm_done)
                        if err is not None:
                            cancel_llm.set()
                            raise RuntimeError(f"Error en Ollama: {err}") from err
                        if nxt_txt is not None:
                            next_future = tts_pool.submit(_synth, nxt_txt)

                if aborted:
                    cancel_llm.set()
                    if next_future is not None:
                        next_future.cancel()
                    break

                if next_future is None and not llm_done:
                    nxt_txt, llm_done, err, aborted, pending_next = _wait_next_clause_blocking(llm_done)
                    if err is not None:
                        cancel_llm.set()
                        raise RuntimeError(f"Error en Ollama: {err}") from err
                    if aborted:
                        cancel_llm.set()
                        break
                    if nxt_txt is not None:
                        next_future = tts_pool.submit(_synth, nxt_txt)

        full_reply = " ".join(clauses).strip()
        if full_reply and not aborted:
            pid = resolve_profile_id(game_state)
            if is_spontaneous and repeats_recent(full_reply, self.spontaneous.recent_spoken_lines):
                print("  [ANTI-DUP] Réplica espontánea solapada descartada de memoria.")
            else:
                self.spontaneous.record_spoken_line(full_reply)
                if not is_spontaneous:
                    self.history.append({"role": "user", "content": raw_user_text or user_prompt})
                    self.history.append({"role": "assistant", "content": full_reply})
                self.memory.record_turn(
                    pid,
                    kind=f"spont:{spont_event_type}" if is_spontaneous else "chat",
                    user_text=raw_user_text or user_prompt,
                    reply_text=full_reply,
                    game_state=game_state,
                    allow_async_recap=True,
                )

            self.reply_seq += 1
            self._publish_inbox(
                state=0,
                subtitle="",
                duration=0.0,
                full_reply=full_reply,
                reply_seq=self.reply_seq,
            )
            print(
                f"  [OK] TTFT: {llm_stats['ttft_ms']:.0f} ms | "
                f"TTFA (1.ª voz): {first_audio_ms or 0:.0f} ms"
            )
        else:
            self.player.interrupt()
            self._publish_inbox(state=0, subtitle="", duration=0.0)
            if aborted:
                print("  [INTERRUMPIDO] Escena, menú o nueva orden prioritaria de V.")

        return pending_next

    def handle_request(self, req: dict[str, Any]) -> dict[str, Any] | None:
        """Procesa una petición manual ([Y]/[U]); devuelve una nueva si interrumpió la actual."""
        self._commit_request_seen(req)
        action = str(req.get("action") or "chat").strip().lower()
        raw_text = str(req.get("text") or "").strip()

        if action == "stop":
            self.player.interrupt()
            self._publish_inbox(state=0, subtitle="", duration=0.0)
            print("[TURNO] Silenciado manualmente.")
            return None

        user_prompt = build_user_prompt(action, raw_text)
        if not user_prompt:
            return None

        self.spontaneous.notify_manual_chat()
        prefs = self._load_companion_prefs()
        game_state = _read_json_safe(self.state_path)
        pid = self._sync_session_and_profile(game_state)
        self._sync_shards_from_state(game_state)
        self.memory.sync_progression_milestones(pid, game_state)
        telemetry_summary = format_telemetry_summary(game_state)

        rag_query = (
            f"{(game_state or {}).get('district', '')} {(game_state or {}).get('tracked_quest_title', '')} "
            f"{(game_state or {}).get('scanned_target', '')}".strip()
            if action == "tactical"
            else user_prompt
        )
        dossier = self._assemble_context_dossier(
            rag_query or user_prompt,
            game_state,
            prefs,
            is_spontaneous=False,
            allow_wiki=True,
        )

        max_tok = 180 if prefs.reply_length == "concise" else (380 if prefs.reply_length == "detailed" else 260)
        if action == "tactical":
            max_tok = min(max_tok, 190)

        print(f"\n[V -> CHISPA] {user_prompt}")
        print(f"  Telemetría: {telemetry_summary}")
        return self._stream_llm_and_speak(
            user_prompt=user_prompt,
            game_state=game_state,
            telemetry_summary=telemetry_summary,
            context_dossier=dossier,
            max_predict_tokens=max_tok,
            temperature=0.55,
            is_spontaneous=False,
            raw_user_text=raw_text or user_prompt,
        )

    def _collect_spontaneous_clauses(
        self,
        *,
        user_prompt: str,
        telemetry_summary: str,
        context_dossier: str,
        max_predict_tokens: int,
        temperature: float,
    ) -> tuple[list[str], float, bool, dict[str, Any] | None]:
        """Recolecta cláusulas breves de reacción espontánea en memoria para validar 0% repetición antes de hablar."""
        history_for_turn = self.history[-6:]
        kwargs: dict[str, Any] = {
            "game_context_summary": telemetry_summary,
            "max_predict_tokens": max_predict_tokens,
            "temperature": temperature,
        }
        if context_dossier:
            kwargs["context_dossier"] = context_dossier
        try:
            stream = self.ollama.stream_clauses(history_for_turn, user_prompt, **kwargs)
        except TypeError:
            stream = self.ollama.stream_clauses(
                history_for_turn,
                user_prompt,
                game_context_summary=telemetry_summary,
            )
        collected: list[str] = []
        ttft_ms = 0.0
        for clause in stream:
            aborted, pending_next = self._should_abort_playback(is_spontaneous=True)
            if aborted:
                return [], ttft_ms, True, pending_next
            if ttft_ms == 0.0:
                ttft_ms = float(clause.ttft_ms)
            if clause.text:
                collected.append(clause.text)
        return collected, ttft_ms, False, None

    def _speak_collected_clauses(
        self,
        clauses: list[str],
        *,
        ttft_ms: float,
        t0: float,
    ) -> tuple[bool, dict[str, Any] | None]:
        """Sintetiza y reproduce una lista ya validada de cláusulas permitiendo corte inmediato si V habla."""
        aborted = False
        pending_next: dict[str, Any] | None = None
        first_audio_ms: float | None = None

        with concurrent.futures.ThreadPoolExecutor(max_workers=1, thread_name_prefix="chispa-tts") as tts_pool:
            def _synth(txt: str) -> tuple[str, np.ndarray, int]:
                wav, sr = self.tts.synthesize(txt)
                return txt, wav, sr

            next_future = tts_pool.submit(_synth, clauses[0]) if clauses else None
            idx = 0
            while next_future is not None and not aborted:
                while not next_future.done():
                    aborted, pending_next = self._should_abort_playback(is_spontaneous=True)
                    if aborted:
                        break
                    time.sleep(0.015)
                if aborted:
                    next_future.cancel()
                    break

                c_text, wav, sr = next_future.result()
                next_future = None
                idx += 1
                if idx < len(clauses):
                    next_future = tts_pool.submit(_synth, clauses[idx])

                dur_s = float(wav.size) / float(sr) if sr > 0 and wav.size > 0 else 2.5
                if wav.size > 0:
                    if first_audio_ms is None:
                        first_audio_ms = (time.perf_counter() - t0) * 1000.0
                    self.player.enqueue(wav)

                self._publish_inbox(
                    state=1 if idx == 1 else 2,
                    subtitle=c_text,
                    duration=max(2.5, dur_s + 0.8),
                )
                print(f"  [CHISPA #{idx}] {c_text} ({dur_s:.2f}s)")

                while not self.player.wait_until_done(timeout=0.04):
                    aborted, pending_next = self._should_abort_playback(is_spontaneous=True)
                    if aborted:
                        self.player.interrupt()
                        break

                if aborted:
                    if next_future is not None:
                        next_future.cancel()
                    break

        if aborted:
            return True, pending_next
        print(
            f"  [OK] TTFT: {ttft_ms:.0f} ms | "
            f"TTFA (1.ª voz): {first_audio_ms or 0:.0f} ms"
        )
        return False, None

    def handle_spontaneous_event(
        self,
        spont: SpontaneousEvent,
        game_state: dict[str, Any],
        prefs: CompanionPrefs,
    ) -> dict[str, Any] | None:
        """Lanza un comentario espontáneo con anti-repetición preventivo y corte prioritario para V."""
        self._sync_session_and_profile(game_state)
        telemetry_summary = format_telemetry_summary(game_state)
        dossier = self._assemble_context_dossier(
            spont.rag_query,
            game_state,
            prefs,
            is_spontaneous=True,
            allow_wiki=False,
        )
        print(f"\n[ESPONTÁNEO: {spont.event_type}] {telemetry_summary}")
        t0 = time.perf_counter()
        clauses, ttft_ms, aborted, pending_next = self._collect_spontaneous_clauses(
            user_prompt=spont.prompt_instruction,
            telemetry_summary=telemetry_summary,
            context_dossier=dossier,
            max_predict_tokens=spont.max_tokens,
            temperature=0.62,
        )
        if aborted:
            return pending_next

        candidate = " ".join(clauses).strip()
        if candidate and repeats_recent(candidate, self.spontaneous.recent_spoken_lines):
            print("  [ANTI-DUP] Solapamiento detectado; reintentando espontáneo con temperature=0.78...")
            ban_extra = f"\nPROHIBIDO REPETIR ESTE BORRADOR: {candidate}"
            clauses, ttft_ms, aborted, pending_next = self._collect_spontaneous_clauses(
                user_prompt=spont.prompt_instruction,
                telemetry_summary=telemetry_summary,
                context_dossier=(dossier + ban_extra).strip(),
                max_predict_tokens=spont.max_tokens,
                temperature=0.78,
            )
            if aborted:
                return pending_next
            candidate = " ".join(clauses).strip()

        if not candidate or repeats_recent(candidate, self.spontaneous.recent_spoken_lines):
            print("  [ANTI-DUP] Descartada réplica espontánea repetida en silencio.")
            return None

        aborted, pending_next = self._speak_collected_clauses(clauses, ttft_ms=ttft_ms, t0=t0)
        if aborted:
            self.player.interrupt()
            self._publish_inbox(state=0, subtitle="", duration=0.0)
            print("  [INTERRUMPIDO] Escena, menú o nueva orden prioritaria de V.")
            return pending_next

        pid = resolve_profile_id(game_state)
        self.spontaneous.record_spoken_line(candidate)
        self.memory.record_turn(
            pid,
            kind=f"spont:{spont.event_type}",
            user_text=spont.prompt_instruction,
            reply_text=candidate,
            game_state=game_state,
            allow_async_recap=True,
        )
        self.reply_seq += 1
        self._publish_inbox(
            state=0,
            subtitle="",
            duration=0.0,
            full_reply=candidate,
            reply_seq=self.reply_seq,
        )
        return None

    def run_forever(self) -> None:
        """Mantiene vivo el puente hasta Ctrl+C combinando chat prioritario y reacciones espontáneas."""
        self.warmup()
        self.start_heartbeat()
        print(
            "[CHISPA v2.0] Enlace activo. Pulsa [Y] para hablar, [U] para táctica rápida "
            "o deja el servicio en segundo plano (Ctrl+C para salir)."
        )

        queued_req: dict[str, Any] | None = None
        last_state_poll = 0.0
        try:
            while not self._stop_event.is_set():
                req = queued_req or self._poll_new_request()
                queued_req = None
                if req is not None:
                    queued_req = self.handle_request(req)
                    continue

                now = time.monotonic()
                if (now - last_state_poll) >= 0.25:
                    last_state_poll = now
                    game_state = self._read_live_state_with_staleness()
                    if game_state:
                        pid = self._sync_session_and_profile(game_state)
                        self._sync_shards_from_state(game_state)
                        self.memory.sync_progression_milestones(pid, game_state)
                        cur_prefs = self._load_companion_prefs()
                        spont_ev = self.spontaneous.evaluate(game_state, prefs=cur_prefs)
                        if spont_ev is not None:
                            queued_req = self.handle_spontaneous_event(spont_ev, game_state, cur_prefs)
                            continue
                time.sleep(0.05)
        except KeyboardInterrupt:
            print("\n[CHISPA v2.0] Cerrando puente local...")
        finally:
            self.close()

    def close(self) -> None:
        self._stop_event.set()
        try:
            self._publish_inbox(state=0, subtitle="", duration=0.0)
        except Exception:
            pass
        self.player.close()
        self.ollama.close()


def run_self_test() -> None:
    """Valida extremo a extremo IPC, RAG híbrido, memoria episódica, espontaneidad y cortes."""
    from chispa_rt.llm_ollama import LlmClause

    class _DummyOllama:
        def __init__(self, _cfg: ChispaServiceConfig) -> None:
            self.last_ctx: str | None = None
            self.last_dossier: str | None = None
            self.calls = 0

        def ensure_model_loaded(self) -> None:
            return None

        def close(self) -> None:
            return None

        def stream_clauses(
            self,
            history: list[dict[str, str]],
            user_text: str,
            game_context_summary: str | None = None,
            context_dossier: str | None = None,
            **_kwargs: Any,
        ):
            self.calls += 1
            self.last_ctx = game_context_summary
            self.last_dossier = context_dossier
            if self.calls == 1:
                yield LlmClause("Cuidado con ese tiroteo en Watson.", 1, 12.0, 15.0, False)
                yield LlmClause("Escanea el depósito rojo con Kiroshi.", 2, 12.0, 28.0, True)
            else:
                yield LlmClause("Alerta roja, recluta: viene un AV de MaxTac.", 1, 10.0, 14.0, False)
                yield LlmClause("Busca techo o despídete del cromo.", 2, 10.0, 25.0, True)

    class _DummyTTS:
        name = "dummy"
        device_label = "CPU mock"

        def __init__(self, _name: str, _cfg: ChispaServiceConfig) -> None:
            pass

        def warmup(self) -> float:
            return 0.0

        def synthesize(self, text: str) -> tuple[np.ndarray, int]:
            return np.zeros(1200, dtype=np.float32), 24000

    class _DummyPlayer:
        def __init__(self) -> None:
            self.chunks = 0
            self.interrupted = False

        def enqueue(self, wav: np.ndarray) -> None:
            self.chunks += 1

        def wait_until_done(self, timeout: float | None = None) -> bool:
            return True

        def interrupt(self) -> None:
            self.interrupted = True

        def close(self) -> None:
            pass

    cfg = ChispaServiceConfig()
    with tempfile.TemporaryDirectory(prefix="chispa_ipc_test_") as tmp_dir:
        tmp_root = Path(tmp_dir)
        ipc = tmp_root / "ipc"
        rag = HybridCyberpunkRAG(db_path=tmp_root / "lore_test.sqlite", enable_vectors=False)
        mem = EpisodicMemoryManager(
            state_dir=tmp_root / "mem_state",
            log_dir=tmp_root / "mem_logs",
            db_path=tmp_root / "ep_test.sqlite",
        )
        fake_now = [100.0]
        spont = SpontaneousDirector(clock_fn=lambda: fake_now[0])

        _write_json_atomic(ipc / "player_req.json", {"cet_session": "old", "req_id": 9, "action": "chat", "text": "vieja"})
        _write_json_atomic(
            ipc / "state.json",
            {
                "session_ready": True,
                "full_gameplay": True,
                "in_menu": False,
                "blocking_scene_or_call": False,
                "shard_popup_open": False,
                "in_combat": True,
                "hp_pct": 42,
                "wanted_stars": 2,
                "district": "Kabuki",
                "weapon": "Shingen Mark V",
                "scanned_target": "Garra de Tigre",
                "lifepath": "gamedataLifePath.StreetKid",
                "level": 14,
                "street_cred": 22,
                "act_phase": 1,
                "tracked_quest_id": "q005",
                "tracked_quest_title": "El Golpe",
                "tracked_quest_obj": "Reúnete con Jackie en el Afterlife",
            },
        )

        dummy_player = _DummyPlayer()
        daemon = ChispaGameDaemon(
            cfg,
            ipc_dir=ipc,
            ollama_factory=_DummyOllama,
            tts_factory=_DummyTTS,
            player=dummy_player,
            speaker_label="SAMSUNG TEST",
            rag=rag,
            memory=mem,
            spontaneous=spont,
            prefs_loader=lambda: CompanionPrefs(enable_online_wiki=False, spontaneous_mode="tactical"),
        )
        daemon.warmup()
        assert daemon._poll_new_request() is None, "La petición previa al arranque debió ignorarse."

        # 1. Turno táctico con RAG + Memoria + Telemetría enriquecida
        _write_json_atomic(
            ipc / "player_req.json",
            {"cet_session": "live1", "req_id": 1, "action": "tactical", "text": "[AUTO_SITUACION]"},
        )
        req = daemon._poll_new_request()
        assert req is not None
        daemon.handle_request(req)
        inbox = _read_json_safe(ipc / "inbox.json")
        assert inbox is not None
        assert inbox["state"] == 0 and inbox["reply_seq"] == 1
        assert "Watson" in inbox["full_reply"] and "Kiroshi" in inbox["full_reply"]
        assert "Kabuki" in (daemon.ollama.last_ctx or "")
        assert "El Golpe" in (daemon.ollama.last_ctx or "")
        assert daemon.ollama.last_dossier and (
            "datos 2077" in daemon.ollama.last_dossier
            or "recuerdo de 2022" in daemon.ollama.last_dossier
            or "Historia vivida juntos" in daemon.ollama.last_dossier
        )
        assert mem.load_profile("streetkid")["total_turns"] == 1

        # 2. Evento espontáneo tras pasar la ventana de gracia tras chat manual
        fake_now[0] = 200.0
        state_boss = _read_json_safe(ipc / "state.json") or {}
        state_boss["wanted_stars"] = 5
        sp_ev = daemon.spontaneous.evaluate(state_boss, prefs=CompanionPrefs(spontaneous_mode="tactical"))
        assert sp_ev is not None and sp_ev.event_type == "ncpd_wanted"
        daemon.handle_spontaneous_event(sp_ev, state_boss, CompanionPrefs(spontaneous_mode="tactical"))
        assert daemon.ollama.calls == 2
        assert mem.load_profile("streetkid")["total_turns"] == 2

        # 3. Verificar bloqueo por llamada/escena vanilla durante reproducción
        _write_json_atomic(ipc / "state.json", {"blocking_scene_or_call": True})
        _write_json_atomic(
            ipc / "player_req.json",
            {"cet_session": "live1", "req_id": 2, "action": "chat", "text": "Hola Chispa"},
        )
        req2 = daemon._poll_new_request()
        assert req2 is not None
        daemon.handle_request(req2)
        assert dummy_player.interrupted is True

        # 4. Verificar aislamiento en caliente entre dos Nómadas distintos (mem_uid diferente)
        save1 = {
            "session_ready": True,
            "session_load_seq": 1,
            "mem_uid": 111111,
            "playthrough_sec": 7000,
            "full_gameplay": True,
            "in_menu": False,
            "blocking_scene_or_call": False,
            "shard_popup_open": False,
            "lifepath": "Nomad",
            "district": "Urbanización West Wind",
        }
        _write_json_atomic(ipc / "state.json", save1)
        _write_json_atomic(
            ipc / "player_req.json",
            {"cet_session": "live1", "req_id": 3, "action": "chat", "text": "¿Qué opinas de Evelyn Parker?"},
        )
        req3 = daemon._poll_new_request()
        assert req3 is not None
        daemon.handle_request(req3)
        assert len(daemon.history) == 2
        assert mem.load_profile("nomad_111111")["total_turns"] == 1

        fake_now[0] = 500.0
        save2 = {
            **save1,
            "session_load_seq": 2,
            "mem_uid": 222222,
            "playthrough_sec": 17372,
            "district": "Little China",
        }
        _write_json_atomic(ipc / "state.json", save2)
        resolved = daemon._sync_session_and_profile(save2)
        assert resolved == "nomad_222222"
        assert daemon.history == [], "La RAM del chat debe quedar limpia al cambiar de partida."
        assert daemon.spontaneous.evaluate(save2, CompanionPrefs(spontaneous_mode="tactical")) is None
        mem_s2 = mem.build_memory_context(
            "nomad_222222",
            "Evelyn Parker Little China",
            district="Little China",
            current_playthrough_sec=17372.0,
            game_state=save2,
        )
        assert "Evelyn" not in mem_s2 and "MaxTac" not in mem_s2, f"Fuga en memoria entre Nómadas: {mem_s2}"
        dossier_s2 = daemon._assemble_context_dossier(
            "Evelyn Parker Little China",
            save2,
            CompanionPrefs(enable_online_wiki=False),
            allow_wiki=False,
        )
        assert "MaxTac" not in dossier_s2 and "Conversaciones y pinchos" not in dossier_s2, (
            f"Fuga detectada entre Nómadas: {dossier_s2}"
        )
        daemon.close()
    print("=== GAME DAEMON SELF-TEST: OK ===")


def main() -> None:
    parser = argparse.ArgumentParser(description="Servicio local en vivo C.H.I.S.P.A. v2.0 para Cyberpunk 2077")
    parser.add_argument("--self-test", action="store_true", help="Valida el puente IPC sin depender del juego abierto")
    parser.add_argument("--ipc-dir", default=None, help="Ruta manual a bin/.../mods/ChispaNC/ipc")
    parser.add_argument("--model", default=ChispaServiceConfig().llm_model, help="Modelo Ollama local")
    parser.add_argument(
        "--tts",
        default="f5_clean",
        choices=["f5_clean", "f5_clone", "kokoro_sergeant", "kokoro_onnx", "qwen3_clone"],
        help="Motor TTS por defecto si no hay preferencia guardada",
    )
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
        return

    ipc_dir = discover_ipc_dir(args.ipc_dir)
    cfg = ChispaServiceConfig(llm_model=args.model, tts_engine=args.tts)
    daemon = ChispaGameDaemon(cfg, ipc_dir=ipc_dir)
    daemon.run_forever()


if __name__ == "__main__":
    main()
