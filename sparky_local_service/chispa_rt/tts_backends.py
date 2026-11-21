"""Motores TTS locales para CHISPA v2.0 (F5-Spanish Clonado, Kokoro Sargento/Base y Qwen3)."""

from __future__ import annotations

import contextlib
import io
import logging
import re
import time
import urllib.request
from pathlib import Path
from typing import Any, Protocol

import numpy as np
import soundfile as sf

from chispa_rt.config import ChispaServiceConfig
from chispa_rt.dsp import CyberAiDSP

KOKORO_RELEASE_BASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
KOKORO_FILES = (
    "kokoro-v1.0.onnx",
    "voices-v1.0.bin",
)


_ES_UNITS = (
    "cero", "uno", "dos", "tres", "cuatro", "cinco", "seis", "siete", "ocho", "nueve",
    "diez", "once", "doce", "trece", "catorce", "quince", "dieciséis", "diecisiete",
    "dieciocho", "diecinueve",
)
_ES_TWENTIES = (
    "veinte", "veintiuno", "veintidós", "veintitrés", "veinticuatro", "veinticinco",
    "veintiséis", "veintisiete", "veintiocho", "veintinueve",
)
_ES_TENS = ("", "", "", "treinta", "cuarenta", "cincuenta", "sesenta", "setenta", "ochenta", "noventa")
_ES_HUNDREDS = (
    "", "ciento", "doscientos", "trescientos", "cuatrocientos",
    "quinientos", "seiscientos", "setecientos", "ochocientos", "novecientos",
)

_ES_YEAR_MAP = {
    "2022": "dos mil veintidós",
    "2023": "dos mil veintitrés",
    "2045": "dos mil cuarenta y cinco",
    "2077": "dos mil setenta y siete",
}

_CYBER_LOANWORDS_ES: tuple[tuple[str, str], ...] = (
    (r"\bnight\s+city\b", "nait siti"),
    (r"\bdatakrash\b", "datacrash"),
    (r"\br\.?\s*a\.?\s*b\.?\s*i\.?\s*d\.?\s*s\b\.?", "rábids"),
    (r"\bmaxtac\b", "máxtac"),
    (r"\bdogtown\b", "dogtaun"),
    (r"\bedgerunners\b", "edchraners"),
    (r"\bbraindance\b", "breindans"),
    (r"\bblack\s+sapphire\b", "blak safáier"),
    (r"\bnetwatch\b", "netguoch"),
    (r"\bmaelstrom\b", "melstrom"),
    (r"\bchooh2\b", "chú dos"),
    (r"\btyger\s+claws\b", "garras de tigre"),
    (r"\bblackwall\b", "muro negro"),
    (r"\bquickhacks\b", "hackeos rápidos"),
    (r"\bquickhack\b", "hackeo rápido"),
    (r"\bripperdocs\b", "matasanos"),
    (r"\bripperdoc\b", "matasanos"),
    (r"\bsmart\s+link\b", "enlace esmart"),
    (r"\bsandevistan\b", "sandevistán"),
    (r"\branyons?\b", "ranyon"),
    (r"\brayons?\b", "ranyon"),
    (r"\bcoastview\b", "coustviu"),
    (r"\bwest\s+wind\b", "güest güind"),
    (r"\bwestbrook\b", "güestbruk"),
    (r"\bclouds\b", "clauds"),
    (r"\bcyberware\b", "sáiberguer"),
    (r"\bpacifica\b", "pacífica"),
    (r"\bafterlife\b", "áfterlaif"),
    (r"\blizzie's\b", "lisis"),
)


def _int_0_99_to_es(n: int) -> str:
    if n < 20:
        return _ES_UNITS[n]
    if n < 30:
        return _ES_TWENTIES[n - 20]
    ten, unit = divmod(n, 10)
    if unit == 0:
        return _ES_TENS[ten]
    return f"{_ES_TENS[ten]} y {_ES_UNITS[unit]}"


def _int_to_es(n: int) -> str:
    if n < 0:
        return f"menos {_int_to_es(-n)}"
    if n < 100:
        return _int_0_99_to_es(n)
    if n == 100:
        return "cien"
    if n < 1000:
        hundred, rem = divmod(n, 100)
        if rem == 0:
            return _ES_HUNDREDS[hundred]
        return f"{_ES_HUNDREDS[hundred]} {_int_0_99_to_es(rem)}"
    if n < 1_000_000:
        thousands, rem = divmod(n, 1000)
        if thousands == 1:
            prefix = "mil"
        else:
            th_txt = _int_to_es(thousands)
            if th_txt.endswith("veintiuno"):
                prefix = f"{th_txt[:-3]}ún mil"
            elif th_txt.endswith(" uno"):
                prefix = f"{th_txt[:-1]} mil"
            else:
                prefix = f"{th_txt} mil"
        if rem == 0:
            return prefix
        return f"{prefix} {_int_to_es(rem)}"
    return str(n)


def sanitize_text_for_tts(text: str) -> str:
    """Limpia marcas markdown y normaliza siglas habituales para locución natural en español."""
    clean = re.sub(r"[*_`#>~]+", " ", text)
    clean = re.sub(r'[“”«»„‟"]+', "", clean)
    clean = re.sub(r"\s*[—–]\s*", ", ", clean)
    clean = re.sub(r"\.{2,}", ".", clean)
    clean = re.sub(r"\bH10\b", "Hache Diez", clean)
    clean = re.sub(r"\bC\.H\.I\.S\.P\.A\.?", "Chispa", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\bNCPD\b", "ene ce pe de", clean)
    clean = re.sub(r"\b6th\s+Street\b", "Calle Seis", clean, flags=re.IGNORECASE)
    clean = re.sub(
        r"\b(las|los|unas|unos|estas|esas|aquellas)\s+I\.?A\.?s?\b",
        lambda m: f"{m.group(1)} ías",
        clean,
    )
    clean = re.sub(r"\bI\.?A\.?s\b", "ías", clean)
    clean = re.sub(r"\bI\.?A\.?\b", "ía", clean)
    clean = re.sub(r"\b(\d{1,3})\.(\d{3})\b", r"\1\2", clean)
    clean = re.sub(r"(\d+)\s*(?:€\$|E\$)", r"\1 edis", clean)
    clean = re.sub(r"€\$|\bE\$", "edis", clean)
    clean = re.sub(r"\s+", " ", clean).strip()
    return clean


def _pct_to_es(match: re.Match[str]) -> str:
    val = int(match.group(1))
    return f"{_int_to_es(val)} por ciento"


def normalize_spanish_for_f5(text: str) -> str:
    """Normaliza a minúsculas puras y español hablado para evitar el sesgo inglés de F5-Spanish."""
    clean = sanitize_text_for_tts(text).lower()
    if not clean:
        return ""

    clean = re.sub(r"(\d{1,6})\s*%", _pct_to_es, clean)
    for year, words in _ES_YEAR_MAP.items():
        clean = re.sub(rf"\b{year}\b", words, clean)
    clean = re.sub(r"\b(\d{1,6})\b", lambda m: _int_to_es(int(m.group(1))), clean)

    for pattern, phonetic in _CYBER_LOANWORDS_ES:
        clean = re.sub(pattern, phonetic, clean, flags=re.IGNORECASE)

    # Mover la coma delante de conjunción y/o ("algoritmos y, en" -> "algoritmos, y en")
    clean = re.sub(r"\s+\b([yo])\s*,\s*", r", \1 ", clean)
    clean = re.sub(r"(?:,\s*){2,}", ", ", clean)

    # Quitar ¡/¿ y comillas residuales; pegar puntuación al vocablo previo
    clean = re.sub(r'[¡¿“”«»„‟"]+', "", clean)
    clean = re.sub(r"\.{2,}", ".", clean)
    clean = re.sub(r"\s*([.,;:?!…]+)\s*", r"\1 ", clean)
    clean = re.sub(r"^[.,;:?!…\s]+", "", clean)
    clean = re.sub(r"\s+", " ", clean).strip()
    return clean


def _trim_generated_speech_edges(
    wav: np.ndarray,
    sr: int,
    pre_pad_s: float = 0.08,
    post_pad_s: float = 0.14,
) -> np.ndarray:
    """Preserva el ataque inicial (80 ms) y la cola final de consonantes (140 ms) sin silencios muertos."""
    arr = np.asarray(wav, dtype=np.float32).reshape(-1)
    if arr.size == 0 or sr <= 0:
        return arr
    peak = float(np.max(np.abs(arr)))
    if peak < 1e-5:
        return arr
    thresh = max(0.005, peak * 0.018)
    active = np.flatnonzero(np.abs(arr) >= thresh)
    if active.size == 0:
        return arr
    s0 = max(0, int(active[0]) - int(round(pre_pad_s * sr)))
    s1 = int(active[-1]) + 1
    core = arr[s0:s1]
    avail_tail = max(0, int(arr.size - s1))
    need_tail = int(round(post_pad_s * sr))
    if avail_tail >= need_tail:
        return arr[s0 : s1 + need_tail].copy()
    pad = np.zeros(need_tail - avail_tail, dtype=np.float32)
    return np.concatenate([core, arr[s1:], pad]).astype(np.float32)


def _resample_if_needed(samples: np.ndarray, src_sr: int, dst_sr: int) -> tuple[np.ndarray, int]:
    if src_sr == dst_sr or samples.size == 0:
        return samples.astype(np.float32), src_sr
    from scipy import signal

    g = np.gcd(int(src_sr), int(dst_sr))
    up = int(dst_sr // g)
    down = int(src_sr // g)
    resampled = signal.resample_poly(samples.astype(np.float64), up, down).astype(np.float32)
    return resampled, dst_sr


class TTSBackend(Protocol):
    name: str
    device_label: str

    def warmup(self) -> float: ...
    def synthesize(self, text: str) -> tuple[np.ndarray, int]: ...


class Qwen3CloneBackend:
    """Clonación vocal zero-shot de CHISPA en español con Qwen/Qwen3-TTS-12Hz-0.6B-Base."""

    name = "qwen3_clone"

    def __init__(self, cfg: ChispaServiceConfig) -> None:
        self.cfg = cfg
        self.model: Any = None
        self.voice_prompt: Any = None
        self.device_label = "cuda:0"

    def warmup(self) -> float:
        if self.model is not None and self.voice_prompt is not None:
            return 0.0

        t0 = time.perf_counter()
        if not self.cfg.ref_wav_path.is_file():
            raise FileNotFoundError(
                f"Falta el audio de referencia de CHISPA: {self.cfg.ref_wav_path}"
            )

        import torch
        from qwen_tts import Qwen3TTSModel

        use_cuda = (self.cfg.qwen3_device != "cpu") and torch.cuda.is_available()
        device_map = self.cfg.qwen3_device or ("cuda:0" if use_cuda else "cpu")
        dtype = torch.bfloat16 if use_cuda else torch.float32
        self.device_label = f"{device_map} ({'bf16' if use_cuda else 'fp32'})"

        last_exc: Exception | None = None
        for attn_impl in ("sdpa", "eager"):
            try:
                self.model = Qwen3TTSModel.from_pretrained(
                    self.cfg.qwen3_model_id,
                    device_map=device_map,
                    dtype=dtype,
                    attn_implementation=attn_impl,
                )
                break
            except Exception as exc:
                last_exc = exc
                self.model = None
        if self.model is None:
            raise RuntimeError(f"No se pudo cargar {self.cfg.qwen3_model_id}: {last_exc}") from last_exc

        ref_np, ref_sr = sf.read(str(self.cfg.ref_wav_path), dtype="float32")
        if ref_np.ndim > 1:
            ref_np = np.mean(ref_np, axis=1).astype(np.float32)

        self.voice_prompt = self.model.create_voice_clone_prompt(
            ref_audio=(ref_np, int(ref_sr)),
            ref_text=self.cfg.ref_text_es,
            x_vector_only_mode=False,
        )
        # Pasada corta de calentamiento para compilar grafos PyTorch antes de medir latencia real
        _ = self.synthesize("Prueba rápida de ópticametro en línea.")
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.model is None or self.voice_prompt is None:
            self.warmup()
        spoken = sanitize_text_for_tts(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate

        wavs, sr = self.model.generate_voice_clone(
            text=spoken,
            language="Spanish",
            voice_clone_prompt=self.voice_prompt,
        )
        raw = np.asarray(wavs[0], dtype=np.float32).reshape(-1)
        resampled, out_sr = _resample_if_needed(raw, int(sr), self.cfg.sample_rate)
        polished = CyberAiDSP.process(resampled, out_sr, mode="light_polish")
        return polished, out_sr


class KokoroONNXBackend:
    """Alternativa ultraligera multi-GPU / CPU basada en Kokoro-82M ONNX + CyberAiDSP."""

    name = "kokoro_onnx"

    def __init__(self, cfg: ChispaServiceConfig) -> None:
        self.cfg = cfg
        self.kokoro: Any = None
        self.voice_id: str = cfg.kokoro_voice_es
        self.device_label = "ONNX CPU (0 MB VRAM)"

    def _ensure_assets(self) -> tuple[Path, Path]:
        self.cfg.kokoro_dir.mkdir(parents=True, exist_ok=True)
        paths: list[Path] = []
        for fname in KOKORO_FILES:
            dst = self.cfg.kokoro_dir / fname
            if not dst.is_file() or dst.stat().st_size < 1024:
                url = f"{KOKORO_RELEASE_BASE}/{fname}"
                tmp = dst.with_suffix(dst.suffix + ".tmp")
                print(f"[KokoroONNX] Descargando {fname} desde GitHub Releases...")
                req = urllib.request.Request(url, headers={"User-Agent": "ChispaLocalService/0.1"})
                with urllib.request.urlopen(req, timeout=180) as resp, open(tmp, "wb") as out_f:
                    while True:
                        chunk = resp.read(1024 * 256)
                        if not chunk:
                            break
                        out_f.write(chunk)
                tmp.replace(dst)
            paths.append(dst)
        return paths[0], paths[1]

    def warmup(self) -> float:
        if self.kokoro is not None:
            return 0.0
        t0 = time.perf_counter()
        from kokoro_onnx import Kokoro

        onnx_path, voices_path = self._ensure_assets()
        self.kokoro = Kokoro(str(onnx_path), str(voices_path))
        available = list(self.kokoro.get_voices())
        if self.cfg.kokoro_voice_es not in available:
            es_males = [v for v in available if v.startswith("em_")]
            es_all = [v for v in available if v.startswith("e")]
            self.voice_id = (es_males or es_all or available)[0]
        _ = self.synthesize("Enlace óptico calibrado.")
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.kokoro is None:
            self.warmup()
        spoken = sanitize_text_for_tts(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate

        samples, sr = self.kokoro.create(
            spoken,
            voice=self.voice_id,
            speed=self.cfg.kokoro_speed_es,
            lang="es",
        )
        raw = np.asarray(samples, dtype=np.float32).reshape(-1)
        resampled, out_sr = _resample_if_needed(raw, int(sr), self.cfg.sample_rate)
        filtered = CyberAiDSP.process(resampled, out_sr, mode="full_cyber_ai")
        return filtered, out_sr


def _hf_cached_or_download(repo_id: str, filename: str) -> str:
    """Resuelve primero desde la caché local (0 peticiones HTTP) y descarga solo si falta."""
    from huggingface_hub import hf_hub_download

    try:
        return hf_hub_download(repo_id=repo_id, filename=filename, local_files_only=True)
    except Exception:
        return hf_hub_download(repo_id=repo_id, filename=filename, local_files_only=False)


_F5_ES_CACHE: dict[tuple[str, str, int], tuple[Any, Any, str, int, float, str]] = {}


class F5SpanishCloneBackend:
    """Clonación vocal en tiempo real con F5-TTS Flow-Matching (jpgallegoar/F5-Spanish)."""

    name = "f5_clone"

    def __init__(self, cfg: ChispaServiceConfig, dsp_mode: str = "gutsy_fiel") -> None:
        self.cfg = cfg
        self.dsp_mode = dsp_mode
        self.name = "f5_clean" if dsp_mode == "light_polish" else "f5_clone"
        self.f5: Any = None
        self._ref_audio: Any = None
        self._ref_text_clean: str = ""
        self._max_chars: int = 180
        self._ref_speech_dur_s: float = 6.0
        self.device_label = "cuda"

    def warmup(self) -> float:
        if self.f5 is not None and self._ref_audio is not None:
            return 0.0
        cache_key = (str(self.cfg.ref_wav_path), self.cfg.ref_text_es, int(self.cfg.f5_nfe_step))
        cached = _F5_ES_CACHE.get(cache_key)
        if cached is not None:
            self.f5, self._ref_audio, self._ref_text_clean, self._max_chars, self._ref_speech_dur_s, self.device_label = cached
            return 0.0
        t0 = time.perf_counter()
        if not self.cfg.ref_wav_path.is_file():
            raise FileNotFoundError(
                f"Falta el audio de referencia de CHISPA: {self.cfg.ref_wav_path}"
            )

        # Silenciar avisos inocuos de redirección POSIX (Windows) y consultas HTTP al cachear en offline
        logging.getLogger("torch.distributed.elastic.multiprocessing.redirects").setLevel(logging.ERROR)
        logging.getLogger("huggingface_hub.utils._http").setLevel(logging.ERROR)

        import torch
        import torchaudio
        from f5_tts.api import F5TTS

        # Evitar dependencia de libtorchcodec (FFmpeg shared DLLs) en torchaudio>=2.9 en Windows
        def _sf_load(uri: Any, *args: Any, **kwargs: Any) -> tuple[Any, int]:
            data, sr_loaded = sf.read(str(uri), dtype="float32", always_2d=True)
            return torch.from_numpy(data.T.copy()), int(sr_loaded)

        torchaudio.load = _sf_load  # type: ignore[assignment]

        ckpt_path = _hf_cached_or_download(self.cfg.f5_repo_id, self.cfg.f5_ckpt_filename)
        vocab_path = _hf_cached_or_download(self.cfg.f5_repo_id, self.cfg.f5_vocab_filename)
        vocos_cfg = _hf_cached_or_download("charactr/vocos-mel-24khz", "config.yaml")
        _ = _hf_cached_or_download("charactr/vocos-mel-24khz", "pytorch_model.bin")
        vocoder_local_dir = str(Path(vocos_cfg).parent)

        device = "cuda" if torch.cuda.is_available() else "cpu"
        self.device_label = f"{device} (F5-Spanish NFE={self.cfg.f5_nfe_step})"

        with contextlib.redirect_stdout(io.StringIO()):
            try:
                self.f5 = F5TTS(
                    model=self.cfg.f5_model_arch,
                    ckpt_file=ckpt_path,
                    vocab_file=vocab_path,
                    vocoder_local_path=vocoder_local_dir,
                    device=device,
                )
            except Exception:
                self.f5 = F5TTS(
                    model="F5TTS_v1_Base",
                    ckpt_file=ckpt_path,
                    vocab_file=vocab_path,
                    vocoder_local_path=vocoder_local_dir,
                    device=device,
                )

        # Precargar y recortar silencios extremos en RAM dejando 180 ms de guarda tras la referencia
        ref_np, ref_sr = sf.read(str(self.cfg.ref_wav_path), dtype="float32")
        if ref_np.ndim > 1:
            ref_np = np.mean(ref_np, axis=1).astype(np.float32)
        nz = np.flatnonzero(np.abs(ref_np) > 0.004)
        if nz.size > 0:
            pad = int(0.05 * ref_sr)
            ref_np = ref_np[max(0, int(nz[0]) - pad) : min(ref_np.size, int(nz[-1]) + pad)]
        dur_ref_s = max(float(ref_np.size) / float(ref_sr), 1.0)
        self._ref_speech_dur_s = dur_ref_s
        ref_np = np.concatenate([ref_np, np.zeros(int(0.18 * ref_sr), dtype=np.float32)])
        self._ref_audio = (torch.from_numpy(ref_np).unsqueeze(0), int(ref_sr))

        ref_txt = normalize_spanish_for_f5(self.cfg.ref_text_es) or self.cfg.ref_text_es.strip().lower()
        if not ref_txt.endswith((".", "!", "?")):
            ref_txt = ref_txt + "."
        self._ref_text_clean = ref_txt + " "
        self._max_chars = min(
            145,
            max(
                95,
                int(len(self._ref_text_clean.encode("utf-8")) / dur_ref_s * max(4.0, 22.0 - dur_ref_s) * self.cfg.f5_speed_es),
            ),
        )

        # Calienta grafos CUDA antes de medir latencia real y libera caché temporal para Cyberpunk 4K
        _F5_ES_CACHE[cache_key] = (
            self.f5,
            self._ref_audio,
            self._ref_text_clean,
            self._max_chars,
            self._ref_speech_dur_s,
            self.device_label,
        )
        _ = self.synthesize("Enlace táctico en línea, recluta.")
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.f5 is None or self._ref_audio is None:
            self.warmup()
        spoken = normalize_spanish_for_f5(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate
        if not spoken.endswith((".", "!", "?", "…")):
            spoken = f"{spoken}."

        import torch
        from f5_tts.infer.utils_infer import chunk_text, infer_batch_process

        batches = chunk_text(spoken, max_chars=self._max_chars)
        if not batches:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate
        if len(batches) > 1 and len(batches[-1].encode("utf-8")) < 22:
            merged = f"{batches[-2]} {batches[-1]}".strip()
            if len(merged.encode("utf-8")) <= 168:
                batches = [*batches[:-2], merged]

        ref_tensor, ref_sr = self._ref_audio
        ref_total_s = float(ref_tensor.shape[-1]) / float(ref_sr)
        ref_bps = max(10.0, float(len(self._ref_text_clean.encode("utf-8"))) / max(1.0, self._ref_speech_dur_s))
        speed_val = max(0.75, float(self.cfg.f5_speed_es))

        parts: list[np.ndarray] = []
        infer_sr = int(self.cfg.sample_rate)
        for b_idx, batch in enumerate(batches):
            chunk_txt = batch.strip().rstrip(",;:")
            if not chunk_txt:
                continue
            if not chunk_txt.endswith((".", "!", "?", "…")):
                chunk_txt = f"{chunk_txt}."
            if len(chunk_txt.encode("utf-8")) < 10:
                chunk_txt = f"{chunk_txt}."
            gen_s = max(1.45, (float(len(chunk_txt.encode("utf-8"))) / ref_bps) / (speed_val * 0.94) + 0.62)
            fix_dur = ref_total_s + gen_s

            chunk_wav, sr, _ = next(
                infer_batch_process(
                    self._ref_audio,
                    self._ref_text_clean,
                    [chunk_txt],
                    self.f5.ema_model,
                    self.f5.vocoder,
                    mel_spec_type=self.f5.mel_spec_type,
                    progress=None,
                    nfe_step=self.cfg.f5_nfe_step,
                    speed=speed_val,
                    fix_duration=fix_dur,
                    device=self.f5.device,
                )
            )
            infer_sr = int(sr)
            is_last = b_idx == (len(batches) - 1)
            trimmed = _trim_generated_speech_edges(
                np.asarray(chunk_wav, dtype=np.float32).reshape(-1),
                infer_sr,
                pre_pad_s=0.08,
                post_pad_s=0.14 if is_last else 0.08,
            )
            if trimmed.size > 0:
                parts.append(trimmed)

        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        if not parts:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate
        if len(parts) == 1:
            raw = parts[0]
        else:
            gap = np.zeros(max(1, int(round(0.045 * infer_sr))), dtype=np.float32)
            joined: list[np.ndarray] = []
            for p_idx, part in enumerate(parts):
                joined.append(part)
                if p_idx < len(parts) - 1:
                    joined.append(gap)
            raw = np.concatenate(joined).astype(np.float32)

        resampled, out_sr = _resample_if_needed(raw, infer_sr, self.cfg.sample_rate)
        polished = CyberAiDSP.process(resampled, out_sr, mode=self.dsp_mode)
        return polished, out_sr


class KokoroSergeantBackend(KokoroONNXBackend):
    """Voz de sargento veterano esculpida mezclando vectores Kokoro + ajuste grave + CyberAiDSP."""

    name = "kokoro_sergeant"

    def __init__(self, cfg: ChispaServiceConfig) -> None:
        super().__init__(cfg)
        self.voice_blend: np.ndarray | None = None
        self.device_label = "ONNX CPU Sargento Blend (0 MB VRAM)"

    def warmup(self) -> float:
        if self.kokoro is not None and self.voice_blend is not None:
            return 0.0
        t0 = time.perf_counter()
        from kokoro_onnx import Kokoro

        onnx_path, voices_path = self._ensure_assets()
        self.kokoro = Kokoro(str(onnx_path), str(voices_path))
        santa = self.kokoro.get_voice_style("em_santa").astype(np.float32)
        fenrir = self.kokoro.get_voice_style("am_fenrir").astype(np.float32)
        onyx = self.kokoro.get_voice_style("am_onyx").astype(np.float32)
        self.voice_blend = (0.45 * santa + 0.35 * fenrir + 0.20 * onyx).astype(np.float32)
        _ = self.synthesize("Enlace óptico calibrado, recluta.")
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.kokoro is None or self.voice_blend is None:
            self.warmup()
        spoken = sanitize_text_for_tts(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate

        # Bajar timbre -1.15 semitonos compensando cadencia en Kokoro (tempo neto ~1.06x)
        pitch_ratio = 2.0 ** (-1.15 / 12.0)  # ~0.9357
        gen_speed = float(self.cfg.kokoro_sergeant_speed_es) / pitch_ratio
        samples, sr = self.kokoro.create(
            spoken,
            voice=self.voice_blend,
            speed=gen_speed,
            lang="es",
        )
        raw = np.asarray(samples, dtype=np.float32).reshape(-1)
        lowered, out_sr = _resample_if_needed(raw, int(round(sr * pitch_ratio)), self.cfg.sample_rate)
        filtered = CyberAiDSP.process(lowered, out_sr, mode="full_cyber_ai")
        return filtered, out_sr


def create_tts_backend(engine_name: str, cfg: ChispaServiceConfig) -> TTSBackend:
    """Factoría explícita para cambiar entre F5 clonado (Gutsy/Limpia), Kokoro y Qwen3."""
    if engine_name == "f5_clone":
        return F5SpanishCloneBackend(cfg, dsp_mode="gutsy_fiel")
    if engine_name == "f5_clean":
        return F5SpanishCloneBackend(cfg, dsp_mode="light_polish")
    if engine_name == "kokoro_sergeant":
        return KokoroSergeantBackend(cfg)
    if engine_name == "kokoro_onnx":
        return KokoroONNXBackend(cfg)
    if engine_name == "qwen3_clone":
        return Qwen3CloneBackend(cfg)
    raise ValueError(f"Motor TTS desconocido: {engine_name!r}")
