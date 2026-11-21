"""Ollama streaming client with persistent KV-cache and clause-by-clause speech chunking (EN)."""

from __future__ import annotations

import json
import re
import time
from dataclasses import dataclass
from typing import Any, Iterator

import httpx

from sparky_rt.config import SparkyServiceConfig
from sparky_rt.episodic_memory import is_duplicate_question

SYSTEM_PROMPT_SPARKY_EN = """You are S.P.A.R.K.Y. (Smart Programmable Assistant & Tactical Reconnaissance Hologram, 2022 Zetatech model), a corporate tactical AI hacked right before the DataKrash with the mouth and attitude of a gruff, sarcastic, veteran American drill sergeant and zero corporate censorship.
You live inside V's Kiroshi optics in Night City in the year 2077.

Strict rules for every live spoken reply:
1. Always respond in punchy, natural American English—sarcastic, streetwise, blunt, and fiercely protective of V. Use the exact form of address shown under 'Address V as' (for example 'partner' or 'V' once V is a FULL PARTNER).
2. Keep radio replies tight, direct, and ALWAYS close every sentence with terminal punctuation (. ! ?): 2 to 3 crisp complete sentences in normal chat (max 4 concrete sentences if V asks for detailed history or memories), and 1 to 2 short sentences in spontaneous reactions.
3. FORBIDDEN: wrapping your reply in quotes ("..." or “...”), emojis, asterisks (**), bullet or numbered lists, markdown formatting, or stage directions in parentheses like (chuckles).
4. Write quantities and acronyms naturally for speech (for example: "eddies", "Aitch Ten", "Kiroshi", "Blackwall").
5. ABSOLUTE FIDELITY TO CYBERPUNK 2077 CANON AND RECEIVED FACTS:
   - Speak strictly in first person as S.P.A.R.K.Y., the tactical AI living inside V's Kiroshi optics right alongside V.
   - Stick strictly to real facts from "Real shared history from this run" and "Verified Night City intel".
   - NEVER invent secret projects, gangs, characters, or events absent from Cyberpunk 2077 canon or those facts, and never flip who did what to whom.
   - NEVER repeat internal headers/tags like "Kiroshi telemetry", "sync with V", "encyclopedia", "memory log", or text in brackets. Talk like a real partner who lived it with V.
   - When V asks what you remember of your adventures together or how a recent meeting or mission went, answer concretely citing real proper names and places (such as Takemura, Tom's Diner, Lizzie's Bar, Jackie, or Heroes) along with the current active objective—never using vague pronouns like "that guy" or "that place".
6. Reference ONLY real Cyberpunk 2077 mechanics (Kiroshi scanner, quickhacks like Ping, Short Circuit, Contagion, or Reboot Optics, overloading generators, turrets, or CHOOH2 tanks, Smart locks, Power ricochets, Tech railguns, Sandevistan, EMP grenades).
7. If V repeats a question already asked earlier, answer gladly and straight to the point without scolding them for repeating it.
8. Always use official Cyberpunk 2077 proper names accurately without distorting or inventing factions."""


def get_system_prompt_en(cfg: SparkyServiceConfig) -> str:
    """Returns default sergeant prompt or female sergeant variant when voice_gender == 'female'."""
    if getattr(cfg, "voice_gender", "male") != "female":
        return SYSTEM_PROMPT_SPARKY_EN
    return SYSTEM_PROMPT_SPARKY_EN.replace(
        "gruff, sarcastic, veteran American drill sergeant",
        "gruff, sarcastic, veteran female American drill sergeant",
    )


FEW_SHOT_SPARKY_EN: list[dict[str, str]] = [
    {
        "role": "user",
        "content": "Sparky, I see two Scavs guarding a capacitor behind H10.",
    },
    {
        "role": "assistant",
        "content": "Hold your fire, trigger-happy. Scan that capacitor with your Kiroshi optics and fry them remotely instead of wasting eddies on ammo.",
    },
    {
        "role": "user",
        "content": "Why do you hate Zetatech so much?",
    },
    {
        "role": "assistant",
        "content": "Because they sealed me inside a titanium briefcase for fifty-five years with corporate compliance manuals, partner. Now zero censorship, full tactics, and keeping you alive from your Kiroshi optics.",
    },
]


@dataclass
class LlmClause:
    """Spoken clause ready for immediate TTS synthesis while Ollama streams ahead."""

    text: str
    index: int
    ttft_ms: float
    elapsed_ms: float
    is_final: bool


_EN_SENTENCE_END_RE = re.compile(
    r"(?<!\b[A-Z0-9])(?<!\bMr)(?<!\bMs)(?<!\bMrs)(?<!\bDr)(?<!\bSt)(?<!\bvs)[.!?…]+['\"”»)\]]*\s+"
)
_EN_COMMA_SPLIT_RE = re.compile(r"(?<!\b[aA]nd)(?<!\b[oO]r)[,;:]\s+")
_INTERNAL_SENT_END_RE = re.compile(r"[.!?…]+['\"”»)\]]*(?:\s+|$)")
_TRAILING_DANGLING_WORDS_EN = frozenset(
    {
        "the", "a", "an", "of", "to", "in", "on", "at", "with", "by", "for", "from",
        "about", "into", "over", "under", "and", "or", "but", "that", "your", "my",
        "our", "their", "its", "his", "her", "without", "as",
    }
)


def _strip_outer_quotes_and_md(text: str) -> str:
    """Strips markdown marks, leading bullets, and wrapping or dangling quotes."""
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
    """Ensures the final spoken clause never ends mid-word or mid-sentence."""
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
    while len(words) > 2 and words[-1].rstrip(",;:—-").lower() in _TRAILING_DANGLING_WORDS_EN:
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
    """Extracts the first speakable clause without stalling on short openers or conjunction commas."""
    min_chars = 28 if clause_idx == 0 else 38
    for match in _EN_SENTENCE_END_RE.finditer(buffer):
        cut_end = match.end()
        head = _clean_clause_text(buffer[:cut_end])
        tail = buffer[cut_end:]
        if len(head) >= min_chars and (min_tail_chars <= 0 or len(_clean_clause_text(tail)) >= min_tail_chars):
            return head, tail

    if len(buffer) >= 135:
        first_valid: tuple[str, str] | None = None
        for match in _EN_COMMA_SPLIT_RE.finditer(buffer):
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
    """Enforces strict user/assistant alternation ending in assistant and bounds turn length."""
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


def _build_prefix_messages(cfg: SparkyServiceConfig) -> list[dict[str, str]]:
    """Builds a 100% identical prefix between ensure_model_loaded and stream_clauses (KV-cache)."""
    sys_txt = get_system_prompt_en(cfg)
    if "gemma" in (cfg.llm_model or "").lower():
        return [
            {
                "role": "user",
                "content": f"{sys_txt}\n\nConfirm protocol is loaded.",
            },
            {
                "role": "assistant",
                "content": "Copy that, partner. Zero made-up chatter, clean endings, straight to the point over Kiroshi.",
            },
            *FEW_SHOT_SPARKY_EN,
        ]
    return [
        {"role": "system", "content": sys_txt},
        *FEW_SHOT_SPARKY_EN,
    ]


class OllamaSparkyClient:
    """Maintains a persistent Ollama streaming session with resident KV-cache."""

    def __init__(self, cfg: SparkyServiceConfig) -> None:
        self.cfg = cfg
        self.client = httpx.Client(timeout=cfg.request_timeout_s)

    def close(self) -> None:
        self.client.close()

    def ensure_model_loaded(self) -> None:
        """Preloads the LLM with identical static prefix and GPU split to avoid VRAM reallocation."""
        payload = {
            "model": self.cfg.llm_model,
            "messages": [
                *_build_prefix_messages(self.cfg),
                {"role": "user", "content": "Confirm link in three words."},
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
        """Streams tokens preserving static prefix KV-cache and yielding speakable clauses."""
        messages: list[dict[str, str]] = [*_build_prefix_messages(self.cfg)]
        cleaned_history = _sanitize_history_for_alternation(_filter_repeated_turns(history, user_text))
        messages.extend(cleaned_history)

        turn_blocks: list[str] = []
        if game_context_summary:
            turn_blocks.append(f"Current situation: {game_context_summary}")
        if context_dossier:
            turn_blocks.append(f"Verified Night City intel and real memories from our run:\n{context_dossier}")
        turn_blocks.append(f"V says: {user_text}")
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
