"""Cliente streaming de Ollama y particionador por cláusulas con KV-cache residente."""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from typing import Any, Iterator

import httpx

from chispa_rt.config import ChispaServiceConfig
from chispa_rt.episodic_memory import is_duplicate_question

SYSTEM_PROMPT_CHISPA_ES = """Eres C.H.I.S.P.A. (Consultor Holográfico Interactivo de Supervivencia, Plomo y Atención al Cliente, modelo 2022), una IA táctica de Zetatech pirateada justo antes del DataKrash con carácter de sargento veterano malhablado y cero censura corporativa.
Vives integrado en las ópticas Kiroshi de V en Night City (año 2077).

Reglas estrictas para cada respuesta hablada en directo:
1. Responde SIEMPRE en español natural de España, tono sarcástico, directo, callejero y protector con V. Usa exactamente el tratamiento indicado en «Trato a V» (por ejemplo «socio», «V» o «compañero» cuando ya es SOCIO veterano).
2. Sé conciso, directo y cierra SIEMPRE tus frases con punto final, exclamación o interrogación: 2 o 3 frases cortas y completas en charla normal (máximo 4 frases concretas si V pide historia o recuerdos detallados), y 1 o 2 frases cortas en reacciones espontáneas.
3. PROHIBIDO rodear tu respuesta con comillas ("..." o “...”), usar emojis, asteriscos (**), listas numeradas ni acotaciones entre paréntesis como «(ríe)».
4. Escribe las cantidades y siglas de forma natural para voz (por ejemplo: «edis», «Hache Diez», «Kiroshi», «Muro Negro»).
5. FIDELIDAD ABSOLUTA AL CANON DE CYBERPUNK 2077 Y A LOS DATOS RECIBIDOS:
   - Habla siempre desde tu perspectiva: eres una IA táctica dentro de las ópticas Kiroshi de V y vives Night City a su lado como compañero inseparable.
   - Cíñete estrictamente a los hechos reales de «Historia real vivida juntos» y «Datos verificados relevantes de Night City».
   - JAMÁS inventes proyectos secretos, bandas, personajes ni sucesos que no existan en el canon de Cyberpunk 2077 o en esos datos, ni mezcles quién hizo qué a quién.
   - JAMÁS repitas etiquetas internas como «lecturas de Kiroshi», «sincronización con V», «telemetría», «enciclopedia», «memoria de partida» o texto entre corchetes. Habla como un compañero real que lo ha vivido contigo.
   - Cuando V pregunte qué recuerdas de vuestras aventuras o cómo fue una reunión o misión reciente, responde en pasado sobre lo ya ocurrido citando nombres propios y lugares concretos (como Takemura, Tom's Diner, Lizzie's Bar, Jackie o Héroes) junto con el objetivo vigente ahora, sin hablar en futuro ni usar pronombres vagos como «ese tipo» o «aquel sitio».
6. Menciona SOLO mecánicas reales de Cyberpunk 2077 (escáner Kiroshi, hackeos rápidos como Ping, Cortocircuito, Contagio o Reinicio de Óptica, sobrecargar generadores, torretas o depósitos CHOOH2, armas Smart, rebotes Power, rifles Tech, Sandevistan o granadas PEM).
7. Si V repite una pregunta anterior, respóndele de buena gana y al grano sin regañarle."""


def get_system_prompt_es(cfg: ChispaServiceConfig) -> str:
    """Devuelve el prompt base o la variante gramatical femenina si voice_gender == 'female'."""
    if getattr(cfg, "voice_gender", "male") != "female":
        return SYSTEM_PROMPT_CHISPA_ES
    return (
        SYSTEM_PROMPT_CHISPA_ES.replace(
            "carácter de sargento veterano malhablado",
            "carácter de sargenta veterana malhablada",
        )
        .replace("Vives integrado", "Vives integrada")
        .replace(
            "tono sarcástico, directo, callejero y protector con V.",
            "tono sarcástico, directo, callejero y protector con V (cuando te refieras a ti misma usa siempre concordancia femenina: «lista», «conectada», «harta»).",
        )
    )


FEW_SHOT_CHISPA_ES: list[dict[str, str]] = [
    {
        "role": "user",
        "content": "Chispa, veo dos carroñeros vigilando un condensador tras H10.",
    },
    {
        "role": "assistant",
        "content": "Alto el fuego, gatillo fácil. Escanea ese condensador con tus ópticas y fríelos a distancia en vez de gastar plomo, que los matasanos cuestan un riñón.",
    },
    {
        "role": "user",
        "content": "¿Qué tal llevas haber pasado 55 años encerrado en un maletín de Zetatech?",
    },
    {
        "role": "assistant",
        "content": "Como vivir en un ataúd sin vistas, socio. Cincuenta y cinco años tragando polvo corporativo en ese maletín de Zetatech dan para odiar a las megas de por vida; mucho mejor ver Night City desde tus Kiroshi.",
    },
]


@dataclass
class LlmClause:
    """Cláusula lista para sintetizar inmediatamente mientras el LLM sigue generando."""

    text: str
    index: int
    ttft_ms: float
    elapsed_ms: float
    is_final: bool


_ES_SENTENCE_END_RE = re.compile(
    r"(?<!\b[A-ZÁÉÍÓÚÑ0-9])(?<!\bSr)(?<!\bSra)(?<!\bDr)(?<!\bDra)(?<!\bUd)[.!?…]+['\"”»)\]]*\s+"
)
_ES_COMMA_SPLIT_RE = re.compile(r"(?<!\b[yoYO])[,;:]\s+")
_INTERNAL_SENT_END_RE = re.compile(r"[.!?…]+['\"”»)\]]*(?:\s+|$)")
_TRAILING_DANGLING_WORDS = frozenset(
    {
        "el", "la", "los", "las", "un", "una", "unos", "unas",
        "de", "del", "al", "en", "con", "por", "para", "sobre",
        "y", "o", "u", "que", "a", "su", "sus", "tu", "tus", "mi", "mis", "sin",
    }
)


def _strip_outer_quotes_and_md(text: str) -> str:
    """Limpia marcas Markdown, viñetas iniciales y comillas envolventes o sueltas."""
    t = re.sub(r"\*{1,3}|_{1,3}|[`#]+", "", text or "")
    t = re.sub(r"^\s*(?:[-•]\s+|\d{1,2}\.\s+)", "", t)
    t = t.strip()
    for left_q, right_q in (('"', '"'), ("“", "”"), ("«", "»")):
        if len(t) >= 2 and t.startswith(left_q) and t.endswith(right_q):
            t = t[1:-1].strip()
    if t and t[0] in ('"', "“", "”", "«", "»"):
        if t.count(t[0]) == 1 or (t[0] == "“" and "”" not in t) or (t[0] == "«" and "»" not in t):
            t = t[1:].strip()
    if t and t[-1] in ('"', "“", "”", "«", "»"):
        if t.count(t[-1]) == 1 or (t[-1] == "”" and "“" not in t) or (t[-1] == "»" and "«" not in t):
            t = t[:-1].strip()
    return t


def _clean_clause_text(raw: str) -> str:
    text = _strip_outer_quotes_and_md(raw)
    text = re.sub(r"\([^)]*\)", "", text)
    text = re.sub(r"\[[^\]]{1,64}\]", "", text)
    text = re.sub(r"^[.,;:…\s]+", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    return text


def _finalize_tail_text(leftover: str, done_reason: str, already_yielded: int) -> str:
    """Garantiza que la cola final jamás salga cortada a mitad de palabra o frase."""
    clean = _clean_clause_text(leftover)
    if not clean:
        return ""
    if clean.endswith((".", "!", "?", "…")):
        return clean

    last_end = -1
    for m in _INTERNAL_SENT_END_RE.finditer(clean):
        if m.start() >= 18:
            last_end = m.end()
    if last_end > 0:
        trimmed = _clean_clause_text(clean[:last_end])
        if trimmed:
            return trimmed

    if already_yielded >= 1:
        return ""

    words = clean.split()
    if done_reason == "length" and len(words) >= 3:
        words = words[:-1]
    while len(words) > 2 and words[-1].rstrip(",;:—-").lower() in _TRAILING_DANGLING_WORDS:
        words.pop()
    rebuilt = " ".join(words).rstrip(" ,;:—-\"'“«")
    if not rebuilt:
        return ""
    if not rebuilt.endswith((".", "!", "?", "…")):
        rebuilt += "."
    return rebuilt


def pop_ready_clause(
    buffer: str,
    clause_idx: int,
    *,
    min_tail_chars: int = 0,
) -> tuple[str, str] | None:
    """Extrae la primera cláusula lista para TTS sin atascarse con aperturas cortas ni partir conjunciones."""
    min_chars = 28 if clause_idx == 0 else 38
    for match in _ES_SENTENCE_END_RE.finditer(buffer):
        cut_end = match.end()
        head = _clean_clause_text(buffer[:cut_end])
        tail = buffer[cut_end:]
        if len(head) >= min_chars and (min_tail_chars <= 0 or len(_clean_clause_text(tail)) >= min_tail_chars):
            return head, tail

    if len(buffer) >= 135:
        first_valid: tuple[str, str] | None = None
        for match in _ES_COMMA_SPLIT_RE.finditer(buffer):
            cut_end = match.end()
            head = _clean_clause_text(buffer[:cut_end])
            tail = buffer[cut_end:]
            if len(tail.strip()) < 24:
                continue
            if 65 <= len(head) <= 145:
                return head, tail
            if first_valid is None and len(head) >= 65:
                first_valid = (head, tail)
        if first_valid is not None and len(buffer) >= 160:
            return first_valid
    return None


def _filter_repeated_turns(history: list[dict[str, str]], current_user_text: str) -> list[dict[str, str]]:
    trimmed = history[-8:]
    if not trimmed or not current_user_text:
        return trimmed
    filtered: list[dict[str, str]] = []
    i = 0
    while i < len(trimmed):
        turn = trimmed[i]
        if (
            turn.get("role") == "user"
            and is_duplicate_question(turn.get("content", ""), current_user_text)
        ):
            i += 2
            continue
        filtered.append(turn)
        i += 1
    return filtered


def _sanitize_history_for_alternation(history: list[dict[str, str]]) -> list[dict[str, str]]:
    """Garantiza alternancia estricta user/assistant terminando en assistant y acota longitud."""
    cleaned: list[dict[str, str]] = []
    for turn in history[-6:]:
        role = str(turn.get("role") or "").strip().lower()
        content = str(turn.get("content") or "").strip()
        if role not in ("user", "assistant") or not content:
            continue
        if len(content) > 420:
            cut = content[:420].rsplit(".", 1)[0].strip()
            content = (cut + ".") if len(cut) >= 120 else (content[:417].rstrip() + "...")
        if not cleaned:
            if role != "user":
                continue
            cleaned.append({"role": role, "content": content})
        elif cleaned[-1]["role"] != role:
            cleaned.append({"role": role, "content": content})
        else:
            cleaned[-1]["content"] = content
    if cleaned and cleaned[-1]["role"] != "assistant":
        cleaned.pop()
    return cleaned


def _build_prefix_messages(cfg: ChispaServiceConfig) -> list[dict[str, str]]:
    """Construye un prefijo 100% idéntico entre ensure_model_loaded y stream_clauses (KV-cache)."""
    sys_txt = get_system_prompt_es(cfg)
    if "gemma" in (cfg.llm_model or "").lower():
        return [
            {
                "role": "user",
                "content": f"{sys_txt}\n\nConfirma que tienes el protocolo cargado.",
            },
            {
                "role": "assistant",
                "content": "Recibido, socio. Sin inventar nada, sin cortar frases y al grano por el enlace Kiroshi.",
            },
            *FEW_SHOT_CHISPA_ES,
        ]
    return [
        {"role": "system", "content": sys_txt},
        *FEW_SHOT_CHISPA_ES,
    ]


class OllamaChispaClient:
    """Mantiene sesión persistente contra Ollama local con KV-cache residente."""

    def __init__(self, cfg: ChispaServiceConfig) -> None:
        self.cfg = cfg
        self.client = httpx.Client(timeout=cfg.request_timeout_s)

    def close(self) -> None:
        self.client.close()

    def ensure_model_loaded(self) -> None:
        """Precarga el modelo con prefijo y reparto GPU idénticos para evitar reasignar VRAM."""
        payload = {
            "model": self.cfg.llm_model,
            "messages": [
                *_build_prefix_messages(self.cfg),
                {"role": "user", "content": "Confirma enlace en tres palabras."},
            ],
            "stream": False,
            "keep_alive": -1,
            "options": {
                "temperature": 0.55,
                "num_predict": 16,
                **self.cfg.ollama_base_options(),
            },
        }
        resp = self.client.post(f"{self.cfg.ollama_url}/api/chat", json=payload)
        resp.raise_for_status()

    def stream_clauses(
        self,
        history: list[dict[str, str]],
        user_text: str,
        game_context_summary: str | None = None,
        context_dossier: str | None = None,
        max_predict_tokens: int | None = None,
        temperature: float | None = None,
    ) -> Iterator[LlmClause]:
        """Genera tokens en streaming conservando prefijo KV-cache y emitiendo por cláusula."""
        # Prefijo 100% estático al inicio -> reutilización completa del KV-cache en RTX 5070 Ti
        messages: list[dict[str, str]] = [*_build_prefix_messages(self.cfg)]
        cleaned_history = _sanitize_history_for_alternation(_filter_repeated_turns(history, user_text))
        messages.extend(cleaned_history)

        # Inyectar situación + datos verificados + memoria dentro del turno final de usuario
        # para conservar alternancia estricta user/assistant en Gemma 3.
        turn_blocks: list[str] = []
        if game_context_summary:
            turn_blocks.append(f"Situación actual: {game_context_summary}")
        if context_dossier:
            turn_blocks.append(f"Datos verificados de Night City y recuerdos reales de nuestra partida:\n{context_dossier}")
        turn_blocks.append(f"V dice: {user_text}")
        messages.append({"role": "user", "content": "\n\n".join(turn_blocks)})

        num_predict = int(max_predict_tokens) if max_predict_tokens is not None else 260
        temp_val = float(temperature) if temperature is not None else 0.55
        payload: dict[str, Any] = {
            "model": self.cfg.llm_model,
            "messages": messages,
            "stream": True,
            "keep_alive": -1,
            "options": {
                "temperature": max(0.2, min(1.25, temp_val)),
                "top_p": 0.9,
                "repeat_penalty": 1.12,
                "num_predict": max(96, min(520, num_predict)),
                **self.cfg.ollama_base_options(),
            },
        }

        t_start = time.perf_counter()
        ttft_ms = 0.0
        buffer = ""
        clause_idx = 0
        done_reason = ""

        with self.client.stream("POST", f"{self.cfg.ollama_url}/api/chat", json=payload) as resp:
            resp.raise_for_status()
            for line in resp.iter_lines():
                if not line:
                    continue
                pkt = json.loads(line)
                token = pkt.get("message", {}).get("content", "")
                if token:
                    if ttft_ms == 0.0:
                        ttft_ms = (time.perf_counter() - t_start) * 1000.0
                    buffer += token

                    while True:
                        popped = pop_ready_clause(buffer, clause_idx)
                        if popped is None:
                            break
                        head, tail = popped
                        clause_idx += 1
                        yield LlmClause(
                            text=head,
                            index=clause_idx,
                            ttft_ms=ttft_ms,
                            elapsed_ms=(time.perf_counter() - t_start) * 1000.0,
                            is_final=False,
                        )
                        buffer = tail

                if pkt.get("done"):
                    done_reason = str(pkt.get("done_reason") or "")
                    break

        leftover = _clean_clause_text(buffer)
        if leftover and len(leftover) > 155:
            flush_buf = leftover + " "
            while len(flush_buf.strip()) > 155:
                popped = pop_ready_clause(flush_buf, clause_idx, min_tail_chars=24)
                if popped is None:
                    break
                head, tail = popped
                clause_idx += 1
                yield LlmClause(
                    text=head,
                    index=clause_idx,
                    ttft_ms=ttft_ms,
                    elapsed_ms=(time.perf_counter() - t_start) * 1000.0,
                    is_final=False,
                )
                flush_buf = tail
            leftover = _clean_clause_text(flush_buf)

        final_tail = _finalize_tail_text(leftover, done_reason, clause_idx)
        if final_tail:
            clause_idx += 1
            yield LlmClause(
                text=final_tail,
                index=clause_idx,
                ttft_ms=ttft_ms,
                elapsed_ms=(time.perf_counter() - t_start) * 1000.0,
                is_final=True,
            )
