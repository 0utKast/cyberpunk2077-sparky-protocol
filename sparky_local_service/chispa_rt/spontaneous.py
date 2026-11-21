"""Director de reacciones espontáneas y filtro anti-repetición para C.H.I.S.P.A. v2.0."""

from __future__ import annotations

import random
import re
import time
from dataclasses import dataclass
from typing import Any

from chispa_rt.companion_prefs import CompanionPrefs, load_companion_prefs
from chispa_rt.lore_rag import strip_accents

MANUAL_CHAT_GRACE_S = 25.0
GLOBAL_SPONTANEOUS_GAP_S = 14.0
POST_LOAD_SETTLE_S = 2.0

EVENT_COOLDOWNS_S: dict[str, float] = {
    "player_low_hp": 48.0,
    "ncpd_wanted": 45.0,
    "boss_detected": 65.0,
    "combat_start": 40.0,
    "combat_end": 35.0,
    "district_entered": 120.0,
    "quest_progress": 95.0,
    "shard_closed": 55.0,
    "idle_ambient": 165.0,
}

AMBIENT_STYLES_ES: dict[str, tuple[int, str]] = {
    "observacion_distrito": (
        3,
        "Haz una observación callejera mordaz sobre el distrito actual, su ambiente, bandas o peligros.",
    ),
    "memoria_2022": (
        2,
        "Comenta un recuerdo breve de 2022 (Zetatech, Rache Bartmoss, DataKrash o la Cuarta Guerra Corporativa) enlazado con lo que ves.",
    ),
    "opinion_corpos_bandas": (
        2,
        "Suelta un dardo sarcástico sobre Arasaka, Militech, Zetatech o la banda que domina esta zona.",
    ),
    "chiste_tactico_v": (
        3,
        "Bromea con V sobre su arma en mano, su estilo de conducción o cómo le gusta meterse en líos.",
    ),
    "mision_en_curso": (
        3,
        "Haz un comentario breve y alentador sobre el objetivo actual de nuestra misión sin sonar a menú del juego.",
    ),
    "ronda_nocturna": (
        2,
        "Reacciona brevemente a la hora del día en Night City o a ir patrullando en vehículo o a pie.",
    ),
}


@dataclass
class SpontaneousEvent:
    """Evento espontáneo listo para sintetizar en game_daemon."""

    event_type: str
    priority: int
    prompt_instruction: str
    rag_query: str
    style_key: str = ""
    max_tokens: int = 92


def _word_ngrams(text: str, n: int = 4) -> set[tuple[str, ...]]:
    words = re.findall(r"[a-z0-9]+", strip_accents(text))
    if len(words) < n:
        return set()
    return {tuple(words[i : i + n]) for i in range(len(words) - n + 1)}


def repeats_recent(candidate: str, recent_lines: list[str], n: int = 4) -> bool:
    """Detecta solapamiento literal o de 4-gramas respecto a frases recientes."""
    cand_norm = re.sub(r"\W+", " ", strip_accents(candidate)).strip()
    if not cand_norm or not recent_lines:
        return False
    for prev in recent_lines:
        prev_norm = re.sub(r"\W+", " ", strip_accents(prev)).strip()
        if cand_norm == prev_norm:
            return True
    grams = _word_ngrams(candidate, n=n)
    if not grams:
        return False
    for prev in recent_lines:
        if grams & _word_ngrams(prev, n=n):
            return True
    return False


class SpontaneousDirector:
    """Evalúa cambios en telemetría Kiroshi para disparar réplicas espontáneas sin spam."""

    def __init__(self, clock_fn=time.monotonic) -> None:
        self._now = clock_fn
        self._initialized = False
        self._prev_in_combat = False
        self._combat_started_at = 0.0
        self._prev_hp_pct = 100
        self._prev_wanted_stars = 0
        self._prev_scanned_seq = 0
        self._prev_shard_seq = 0
        self._confirmed_district = ""
        self._candidate_district = ""
        self._candidate_district_since = 0.0
        self._was_loading_or_menu = False
        self._gameplay_resumed_at = 0.0
        self._prev_quest_sig = ""

        self._last_event_at: dict[str, float] = {}
        self._last_manual_chat_at = float("-inf")
        self._last_spontaneous_at = float("-inf")
        self._recent_styles: list[str] = []
        self.recent_spoken_lines: list[str] = []

    def notify_manual_chat(self) -> None:
        self._last_manual_chat_at = self._now()

    def record_spoken_line(self, line: str) -> None:
        clean = (line or "").strip()
        if clean:
            self.recent_spoken_lines.append(clean)
            del self.recent_spoken_lines[:-14]

    def reset_for_save_load(
        self,
        game_state: dict[str, Any] | None = None,
        *,
        clear_spoken: bool = True,
    ) -> None:
        """Reinicia líneas base y distritos confirmados al cargar otra partida en caliente."""
        now = self._now()
        self._confirmed_district = ""
        self._candidate_district = ""
        self._candidate_district_since = 0.0
        self._was_loading_or_menu = False
        self._gameplay_resumed_at = 0.0
        self._prev_quest_sig = ""
        self._last_event_at.clear()
        self._last_spontaneous_at = float("-inf")
        self._last_manual_chat_at = float("-inf")
        self._prev_in_combat = False
        self._combat_started_at = 0.0
        self._prev_hp_pct = 100
        self._prev_wanted_stars = 0
        self._prev_scanned_seq = 0
        self._prev_shard_seq = 0
        if clear_spoken:
            self._recent_styles.clear()
            self.recent_spoken_lines.clear()
        if game_state and game_state.get("session_ready") and game_state.get("full_gameplay"):
            self._initialized = True
            self._update_baselines(game_state, now)
        else:
            self._initialized = False

    def _cooldown_ready(self, ev_name: str, now: float, custom_cd: float | None = None) -> bool:
        cd = custom_cd if custom_cd is not None else EVENT_COOLDOWNS_S.get(ev_name, 45.0)
        return (now - self._last_event_at.get(ev_name, -9999.0)) >= cd

    def _pick_ambient_style(self, game_state: dict[str, Any]) -> tuple[str, str]:
        has_quest = bool(str(game_state.get("tracked_quest_title") or "").strip())
        pool = [k for k in AMBIENT_STYLES_ES if k not in self._recent_styles[-2:]]
        if not has_quest:
            pool = [k for k in pool if k != "mision_en_curso"]
        if not pool:
            pool = [k for k in AMBIENT_STYLES_ES if has_quest or k != "mision_en_curso"]
        chosen = random.choices(pool, weights=[AMBIENT_STYLES_ES[k][0] for k in pool])[0]
        self._recent_styles.append(chosen)
        del self._recent_styles[:-4]
        return chosen, AMBIENT_STYLES_ES[chosen][1]

    def _update_baselines(self, state: dict[str, Any], now: float, *, update_spatial: bool = True) -> None:
        in_combat = bool(state.get("in_combat"))
        if in_combat and not self._prev_in_combat:
            self._combat_started_at = now
        self._prev_in_combat = in_combat
        self._prev_hp_pct = int(state.get("hp_pct") if state.get("hp_pct") is not None else 100)
        self._prev_wanted_stars = int(state.get("wanted_stars") or 0)
        self._prev_scanned_seq = int(state.get("scanned_seq") or 0)
        self._prev_shard_seq = int(state.get("last_shard_seq") or 0)

        if update_spatial:
            dist = str(state.get("district") or "").strip()
            if not self._confirmed_district and dist:
                self._confirmed_district = dist
            q_title = str(state.get("tracked_quest_title") or "").strip()
            q_obj = str(state.get("tracked_quest_obj") or "").strip()
            if q_title or q_obj:
                self._prev_quest_sig = f"{q_title}|{q_obj}"

    def evaluate(
        self,
        game_state: dict[str, Any] | None,
        prefs: CompanionPrefs | None = None,
    ) -> SpontaneousEvent | None:
        """Evalúa telemetría actual y devuelve el evento espontáneo prioritario, o None."""
        cur_prefs = prefs if prefs is not None else load_companion_prefs()
        mode = cur_prefs.spontaneous_mode
        if mode == "off" or not game_state:
            return None
        if not game_state.get("session_ready"):
            self._initialized = False
            self._confirmed_district = ""
            self._candidate_district = ""
            self._candidate_district_since = 0.0
            self._was_loading_or_menu = True
            self._gameplay_resumed_at = 0.0
            return None

        now = self._now()
        if not self._initialized:
            self._initialized = True
            self._update_baselines(game_state, now)
            return None

        loading_or_menu = (
            not game_state.get("session_ready")
            or not game_state.get("full_gameplay")
            or bool(game_state.get("in_menu"))
            or bool(game_state.get("loading_or_fast_travel"))
            or bool(game_state.get("state_stale"))
        )
        if loading_or_menu:
            self._was_loading_or_menu = True
            self._gameplay_resumed_at = 0.0
            self._candidate_district = ""
            self._candidate_district_since = 0.0
            # Conservar _confirmed_district intacto durante viaje rápido/carga para anunciarlo al terminar de cargar
            self._update_baselines(game_state, now, update_spatial=False)
            return None

        if self._was_loading_or_menu:
            self._was_loading_or_menu = False
            self._gameplay_resumed_at = now

        # Estabilizar cambios de distrito (evita disparos en bordes fugaces al conducir rápido)
        dist = str(game_state.get("district") or "").strip()
        stable_new_district = ""
        if dist and dist != self._confirmed_district:
            if dist != self._candidate_district:
                self._candidate_district = dist
                self._candidate_district_since = now
            elif (now - self._candidate_district_since) >= 1.5:
                stable_new_district = dist

        if self._gameplay_resumed_at > 0.0 and (now - self._gameplay_resumed_at) < POST_LOAD_SETTLE_S:
            # Esperar a que termine de estabilizarse el HUD/subtítulos tras viaje rápido o carga
            self._update_baselines(game_state, now, update_spatial=False)
            return None

        # Guardias estrictos: jamás interrumpir escenas, diálogos vanilla, llamadas ni lectura de pinchos
        blocked = (
            bool(game_state.get("blocking_scene_or_call"))
            or bool(game_state.get("shard_popup_open"))
        )
        if blocked:
            self._update_baselines(game_state, now)
            if stable_new_district:
                self._confirmed_district = stable_new_district
            return None

        if (now - self._last_manual_chat_at) < MANUAL_CHAT_GRACE_S:
            self._update_baselines(game_state, now)
            return None
        if (now - self._last_spontaneous_at) < GLOBAL_SPONTANEOUS_GAP_S:
            self._update_baselines(game_state, now)
            return None

        in_combat = bool(game_state.get("in_combat"))
        hp_pct = int(game_state.get("hp_pct") if game_state.get("hp_pct") is not None else 100)
        stars = int(game_state.get("wanted_stars") or 0)
        scanned_seq = int(game_state.get("scanned_seq") or 0)
        scanned_target = str(game_state.get("scanned_target") or "").strip()
        scanned_boss = bool(game_state.get("scanned_is_boss"))
        scanned_rarity = str(game_state.get("scanned_rarity") or "").lower()
        shard_seq = int(game_state.get("last_shard_seq") or 0)
        shard_title = str(game_state.get("last_shard_title") or "").strip()
        shard_text = str(game_state.get("last_shard_text") or "").strip()
        q_title = str(game_state.get("tracked_quest_title") or "").strip()
        q_obj = str(game_state.get("tracked_quest_obj") or "").strip()
        q_sig = f"{q_title}|{q_obj}"

        candidates: list[SpontaneousEvent] = []

        # 1. Salud crítica en combate
        if in_combat and hp_pct <= 28 and self._prev_hp_pct > 28 and self._cooldown_ready("player_low_hp", now):
            candidates.append(
                SpontaneousEvent(
                    event_type="player_low_hp",
                    priority=10,
                    prompt_instruction=(
                        f"[EVENTO ESPONTÁNEO: SALUD CRÍTICA ({hp_pct}%)] "
                        "Avisa con urgencia y sorna de sargento a V para que se meta un MaxDoc o tome cobertura ya, "
                        "en 1 o 2 frases muy cortas (máx. 26 palabras)."
                    ),
                    rag_query="MaxDoc salud combate",
                    max_tokens=135,
                )
            )

        # 2. Escalada NCPD o llegada de MaxTac (5 estrellas)
        if stars > self._prev_wanted_stars and stars >= 1 and self._cooldown_ready("ncpd_wanted", now):
            if stars >= 5:
                instr = (
                    "[EVENTO ESPONTÁNEO: ALERTA ROJA 5 ESTRELLAS MAXTAC] "
                    "Avisa a V de que han desplegado a MaxTac en AV y toca desaparecer o pelear con todo, "
                    "en 1 o 2 frases cortas (máx. 28 palabras)."
                )
            else:
                instr = (
                    f"[EVENTO ESPONTÁNEO: BÚSQUEDA NCPD ({stars} estrellas)] "
                    "Comenta con sarcasmo que la policía está encima en el distrito actual, en 1 frase corta (máx. 24 palabras)."
                )
            candidates.append(
                SpontaneousEvent(
                    event_type="ncpd_wanted",
                    priority=9 if stars >= 5 else 8,
                    prompt_instruction=instr,
                    rag_query="MaxTac NCPD persecucion",
                    max_tokens=140,
                )
            )

        # 3. Escaneo de jefe / ciberpsicópata / enemigo élite nuevo
        is_high_threat = scanned_boss or ("boss" in scanned_rarity) or ("elite" in scanned_rarity)
        if scanned_seq > self._prev_scanned_seq and scanned_target and is_high_threat and self._cooldown_ready("boss_detected", now):
            candidates.append(
                SpontaneousEvent(
                    event_type="boss_detected",
                    priority=8,
                    prompt_instruction=(
                        f"[EVENTO ESPONTÁNEO: BLANCO PELIGROSO ESCANEADO: {scanned_target}] "
                        "Advierte a V del perfil peligroso que acabas de marcar en Kiroshi y sugiere táctica rápida "
                        "(Cortocircuito, cobertura o flanqueo), máximo 28 palabras."
                    ),
                    rag_query=f"{scanned_target} jefe ciberpsicopata tactica",
                    max_tokens=150,
                )
            )

        # 4. Inicio de tiroteo
        if in_combat and not self._prev_in_combat and self._cooldown_ready("combat_start", now):
            candidates.append(
                SpontaneousEvent(
                    event_type="combat_start",
                    priority=7,
                    prompt_instruction=(
                        f"[EVENTO ESPONTÁNEO: INICIO DE COMBATE en {dist or 'Night City'}] "
                        "Suelta un aviso breve de combate con tono de sargento preparando a V (máx. 22 palabras)."
                    ),
                    rag_query=f"{dist} {scanned_target} combate",
                    max_tokens=135,
                )
            )

        # 5. Fin de combate relevante (>= 8 s)
        if not in_combat and self._prev_in_combat:
            combat_dur = now - self._combat_started_at if self._combat_started_at > 0 else 0.0
            if combat_dur >= 8.0 and self._cooldown_ready("combat_end", now):
                candidates.append(
                    SpontaneousEvent(
                        event_type="combat_end",
                        priority=6,
                        prompt_instruction=(
                            f"[EVENTO ESPONTÁNEO: COMBATE SUPERADO en {dist or 'Night City'}] "
                            "Celebra con humor seco haber salido enteros del tiroteo y recuerda saquear o seguir, máx. 24 palabras."
                        ),
                        rag_query=f"{dist} combate loot",
                        max_tokens=140,
                    )
                )

        # 6. Entrada estable a un nuevo distrito
        if stable_new_district and self._cooldown_ready("district_entered", now):
            self._confirmed_district = stable_new_district
            candidates.append(
                SpontaneousEvent(
                    event_type="district_entered",
                    priority=5,
                    prompt_instruction=(
                        f"[EVENTO ESPONTÁNEO: LLEGADA A {stable_new_district.upper()}] "
                        f"Acabas de entrar con V en {stable_new_district}. Comenta brevemente algo real del ambiente, historia o bandas de ese barrio "
                        "(y enlaza si encaja con nuestra misión activa), máximo 30 palabras. Apóyate solo en datos reales del barrio/misión sin inventar bandas ni lugares."
                    ),
                    rag_query=f"distrito {stable_new_district} bandas lugares",
                    max_tokens=160,
                )
            )

        # 7. Avance de objetivo en la misión activa
        if (
            self._prev_quest_sig
            and q_sig != self._prev_quest_sig
            and (q_title or q_obj)
            and self._cooldown_ready("quest_progress", now)
        ):
            candidates.append(
                SpontaneousEvent(
                    event_type="quest_progress",
                    priority=4,
                    prompt_instruction=(
                        f"[EVENTO ESPONTÁNEO: ACTUALIZACIÓN DE MISIÓN '{q_title}': {q_obj}] "
                        "Comenta con naturalidad el nuevo paso sin parecer un menú del juego ni destripar nada, máx. 28 palabras. Apóyate solo en datos reales del barrio/misión sin inventar bandas ni lugares."
                    ),
                    rag_query=f"{q_title} {q_obj}",
                    max_tokens=155,
                )
            )

        # Eventos exclusivos del modo "active"
        if mode == "active":
            if shard_seq > self._prev_shard_seq and (shard_title or shard_text) and self._cooldown_ready("shard_closed", now):
                candidates.append(
                    SpontaneousEvent(
                        event_type="shard_closed",
                        priority=3,
                        prompt_instruction=(
                            f"[EVENTO ESPONTÁNEO: PINCHO RECIÉN LEÍDO: '{shard_title}'] "
                            f"Extracto captado por Kiroshi: «{shard_text[:320]}». "
                            "Haz una observación aguda o cínica sobre lo que V acaba de leer en el pincho, máx. 30 palabras."
                        ),
                        rag_query=f"{shard_title} {shard_text[:120]}",
                        max_tokens=160,
                    )
                )

            if (
                not candidates
                and not in_combat
                and stars == 0
                and self._cooldown_ready("idle_ambient", now, custom_cd=cur_prefs.ambient_cooldown_s)
            ):
                st_key, st_desc = self._pick_ambient_style(game_state)
                veh_txt = "en vehículo" if game_state.get("in_vehicle") else "a pie"
                hr_txt = str(game_state.get("game_hour") or "")
                candidates.append(
                    SpontaneousEvent(
                        event_type="idle_ambient",
                        priority=1,
                        style_key=st_key,
                        prompt_instruction=(
                            f"[COMENTARIO AMBIENTAL ESPONTÁNEO ({st_key}) | {dist or 'Night City'} | {hr_txt} | {veh_txt}] "
                            f"{st_desc} Máximo 28 palabras."
                        ),
                        rag_query=f"{dist} {q_title} {st_key}",
                        max_tokens=150,
                    )
                )

        # Actualizar estado base antes de devolver el evento ganador
        self._update_baselines(game_state, now)

        if not candidates:
            return None
        candidates.sort(key=lambda c: c.priority, reverse=True)
        winner = candidates[0]
        self._last_event_at[winner.event_type] = now
        self._last_spontaneous_at = now
        return winner


def run_self_test() -> None:
    """Valida transiciones, cooldowns, bloqueo en escenas/pinchos, modos y 4-gramas."""
    fake_now = [100.0]

    def clock() -> float:
        return fake_now[0]

    d = SpontaneousDirector(clock_fn=clock)
    base_state = {
        "session_ready": True,
        "full_gameplay": True,
        "in_menu": False,
        "blocking_scene_or_call": False,
        "shard_popup_open": False,
        "in_combat": False,
        "in_vehicle": False,
        "hp_pct": 100,
        "wanted_stars": 0,
        "district": "Little China",
        "scanned_seq": 0,
        "scanned_target": "",
        "scanned_is_boss": False,
        "last_shard_seq": 0,
        "tracked_quest_title": "El rescate",
        "tracked_quest_obj": "Llega al apartamento",
    }

    # 1. Primer tick solo fija línea base (cero falsos disparos)
    prefs_tac = CompanionPrefs(spontaneous_mode="tactical")
    assert d.evaluate(base_state, prefs_tac) is None

    # 2. Modo off jamás dispara
    fake_now[0] = 200.0
    assert d.evaluate({**base_state, "hp_pct": 20, "in_combat": True}, CompanionPrefs(spontaneous_mode="off")) is None

    # 3. Bloqueo estricto mientras lee pincho o escena
    fake_now[0] = 250.0
    assert d.evaluate({**base_state, "shard_popup_open": True, "wanted_stars": 2}, prefs_tac) is None

    # 4. Combate + MaxTac (5 estrellas) dispara ncpd_wanted
    fake_now[0] = 300.0
    ev = d.evaluate({**base_state, "in_combat": True, "wanted_stars": 5}, prefs_tac)
    assert ev is not None and ev.event_type == "ncpd_wanted"

    # 5. Cooldown global impide disparo inmediato 2s después
    fake_now[0] = 302.0
    assert d.evaluate({**base_state, "in_combat": True, "hp_pct": 15}, prefs_tac) is None

    # 6. Fin de combate tras > 8s dispara combat_end
    fake_now[0] = 320.0
    ev_end = d.evaluate({**base_state, "in_combat": False, "hp_pct": 80, "wanted_stars": 0}, prefs_tac)
    assert ev_end is not None and ev_end.event_type == "combat_end"

    # 7. Entrada estable a nuevo distrito tras >= 1.5s dispara district_entered
    fake_now[0] = 400.0
    assert d.evaluate({**base_state, "district": "Kabuki"}, prefs_tac) is None
    fake_now[0] = 402.0
    ev_dist = d.evaluate({**base_state, "district": "Kabuki"}, prefs_tac)
    assert ev_dist is not None and ev_dist.event_type == "district_entered"

    # 8. En modo tactical NO dispara shard_closed ni idle_ambient
    fake_now[0] = 520.0
    assert d.evaluate({**base_state, "district": "Kabuki", "last_shard_seq": 1, "last_shard_title": "Pincho"}, prefs_tac) is None

    # 9. En modo active SÍ dispara shard_closed cuando corresponde
    prefs_act = CompanionPrefs(spontaneous_mode="active")
    fake_now[0] = 540.0
    ev_sh = d.evaluate(
        {**base_state, "district": "Kabuki", "last_shard_seq": 2, "last_shard_title": "Contrato Arasaka", "last_shard_text": "Pago 5000 edis."},
        prefs_act,
    )
    assert ev_sh is not None and ev_sh.event_type == "shard_closed"

    # 9. Anti-repetición 4-gramas
    d.record_spoken_line("Cuidado con las torretas de este almacén de Northside, recluta.")
    assert repeats_recent("Cuidado con las torretas de este almacén hoy.", d.recent_spoken_lines)
    assert not repeats_recent("Buen disparo contra ese Carroñero en Kabuki.", d.recent_spoken_lines)

    # 10. Cambio de partida en caliente no dispara falso district_entered
    fake_now[0] = 700.0
    d.reset_for_save_load({**base_state, "district": "Little China"}, clear_spoken=True)
    fake_now[0] = 702.0
    assert d.evaluate({**base_state, "district": "Little China"}, prefs_tac) is None

    # 11. Viaje rápido / pantalla de carga retiene el cambio de distrito hasta 2.0 s tras volver al juego real
    fake_now[0] = 710.0
    assert d.evaluate({**base_state, "district": "Pacifica", "loading_or_fast_travel": True}, prefs_tac) is None
    fake_now[0] = 715.0
    assert d.evaluate({**base_state, "district": "Pacifica", "loading_or_fast_travel": True}, prefs_tac) is None
    fake_now[0] = 716.0
    assert d.evaluate({**base_state, "district": "Pacifica", "loading_or_fast_travel": False}, prefs_tac) is None
    fake_now[0] = 717.0
    assert d.evaluate({**base_state, "district": "Pacifica", "loading_or_fast_travel": False}, prefs_tac) is None
    fake_now[0] = 718.5
    ev_ft = d.evaluate({**base_state, "district": "Pacifica", "loading_or_fast_travel": False}, prefs_tac)
    assert ev_ft is not None and ev_ft.event_type == "district_entered" and "PACIFICA" in ev_ft.prompt_instruction
    print("=== SPONTANEOUS DIRECTOR SELF-TEST: OK ===")


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Motor de reacciones espontáneas C.H.I.S.P.A. v2.0")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        run_self_test()


if __name__ == "__main__":
    main()
