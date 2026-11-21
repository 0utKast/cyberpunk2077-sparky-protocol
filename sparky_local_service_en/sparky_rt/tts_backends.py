"""Local English TTS backends for S.P.A.R.K.Y. v2.0 (F5-TTS Clone, Kokoro Sergeant/Base, and Qwen3)."""

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

from sparky_rt.config import SparkyServiceConfig
from sparky_rt.dsp import CyberAiDSP

KOKORO_RELEASE_BASE = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"
KOKORO_FILES = (
    "kokoro-v1.0.onnx",
    "voices-v1.0.bin",
)


def sanitize_text_for_tts_en(text: str) -> str:
    """Strips markdown noise and normalizes Night City acronyms for clean English speech."""
    clean = re.sub(r"[*_`#>~]+", " ", text)
    clean = re.sub(r'[“”«»„‟"]+', "", clean)
    clean = re.sub(r"\s*[—–]\s*", ", ", clean)
    clean = re.sub(r"\.{2,}", ".", clean)
    clean = re.sub(r"\bH10\b", "Aitch Ten", clean)
    clean = re.sub(r"\bS\.?P\.?A\.?R\.?K\.?Y\.?", "Sparky", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\bC\.?H\.?I\.?S\.?P\.?A\.?", "Sparky", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\bR\.?\s*A\.?\s*B\.?\s*I\.?\s*D\.?\s*S\.?\b", "rabids", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\bN\.?C\.?P\.?D\.?\b", "N C P D", clean)
    clean = re.sub(r"\b6th\s+Street\b", "Sixth Street", clean, flags=re.IGNORECASE)
    clean = re.sub(r"\bCHOOH2\b", "choo two", clean, flags=re.IGNORECASE)
    clean = re.sub(r"(\d+)\s*(?:€\$|\bE\$)", r"\1 eddies", clean)
    clean = re.sub(r"€\$|\bE\$", "eddies", clean)
    clean = re.sub(r"(\d+)\s*%", r"\1 percent", clean)
    clean = re.sub(r"\s+\b(and|or)\s*,\s*", r", \1 ", clean, flags=re.IGNORECASE)
    clean = re.sub(r"(?:,\s*){2,}", ", ", clean)
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
    """Preserves leading attack (80 ms) and trailing consonant tail (140 ms) without dead silence."""
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


def _hf_cached_or_download(repo_id: str, filename: str) -> str:
    """Resolves HuggingFace artifacts strictly offline from cache first, downloading only if missing."""
    from huggingface_hub import hf_hub_download

    try:
        return hf_hub_download(repo_id=repo_id, filename=filename, local_files_only=True)
    except Exception:
        return hf_hub_download(repo_id=repo_id, filename=filename, local_files_only=False)


class TTSBackend(Protocol):
    name: str
    device_label: str

    def warmup(self) -> float: ...
    def synthesize(self, text: str) -> tuple[np.ndarray, int]: ...


class Qwen3CloneBackend:
    """Zero-shot voice cloning of SPARKY in English via Qwen/Qwen3-TTS-12Hz-0.6B-Base."""

    name = "qwen3_clone"

    def __init__(self, cfg: SparkyServiceConfig) -> None:
        self.cfg = cfg
        self.model: Any = None
        self.voice_prompt: Any = None
        self.device_label = "cuda:0"

    def warmup(self) -> float:
        if self.model is not None and self.voice_prompt is not None:
            return 0.0
        t0 = time.perf_counter()
        if not self.cfg.ref_wav_path.is_file():
            raise FileNotFoundError(f"Missing SPARKY reference audio: {self.cfg.ref_wav_path}")

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
            raise RuntimeError(f"Failed to load {self.cfg.qwen3_model_id}: {last_exc}") from last_exc

        ref_np, ref_sr = sf.read(str(self.cfg.ref_wav_path), dtype="float32")
        if ref_np.ndim > 1:
            ref_np = np.mean(ref_np, axis=1).astype(np.float32)

        self.voice_prompt = self.model.create_voice_clone_prompt(
            ref_audio=(ref_np, int(ref_sr)),
            ref_text=self.cfg.ref_text_en,
            x_vector_only_mode=False,
        )
        _ = self.synthesize("Kiroshi optic link online, recruit.")
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.model is None or self.voice_prompt is None:
            self.warmup()
        spoken = sanitize_text_for_tts_en(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate

        wavs, sr = self.model.generate_voice_clone(
            text=spoken,
            language="English",
            voice_clone_prompt=self.voice_prompt,
        )
        raw = np.asarray(wavs[0], dtype=np.float32).reshape(-1)
        resampled, out_sr = _resample_if_needed(raw, int(sr), self.cfg.sample_rate)
        polished = CyberAiDSP.process(resampled, out_sr, mode="light_polish")
        return polished, out_sr


class KokoroONNXBackend:
    """Zero-VRAM CPU fallback based on Kokoro-82M ONNX + CyberAiDSP."""

    name = "kokoro_onnx"

    def __init__(self, cfg: SparkyServiceConfig) -> None:
        self.cfg = cfg
        self.kokoro: Any = None
        self.voice_id: str = cfg.kokoro_voice_en
        self.device_label = "ONNX CPU (0 MB VRAM)"

    def _ensure_assets(self) -> tuple[Path, Path]:
        self.cfg.kokoro_dir.mkdir(parents=True, exist_ok=True)
        paths: list[Path] = []
        for fname in KOKORO_FILES:
            dst = self.cfg.kokoro_dir / fname
            if not dst.is_file() or dst.stat().st_size < 1024:
                url = f"{KOKORO_RELEASE_BASE}/{fname}"
                tmp = dst.with_suffix(dst.suffix + ".tmp")
                print(f"[KokoroONNX] Downloading {fname} from GitHub Releases...")
                req = urllib.request.Request(url, headers={"User-Agent": "SparkyLocalService/2.0"})
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
        if self.cfg.kokoro_voice_en not in available:
            en_males = [v for v in available if v.startswith("am_")]
            en_all = [v for v in available if v.startswith("a")]
            self.voice_id = (en_males or en_all or available)[0]
        _ = self.synthesize("Kiroshi optic link calibrated.")
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.kokoro is None:
            self.warmup()
        spoken = sanitize_text_for_tts_en(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate

        samples, sr = self.kokoro.create(
            spoken,
            voice=self.voice_id,
            speed=self.cfg.kokoro_speed_en,
            lang="en-us",
        )
        raw = np.asarray(samples, dtype=np.float32).reshape(-1)
        resampled, out_sr = _resample_if_needed(raw, int(sr), self.cfg.sample_rate)
        filtered = CyberAiDSP.process(resampled, out_sr, mode="full_cyber_ai")
        return filtered, out_sr


_F5_EN_CACHE: dict[tuple[str, str, int], tuple[Any, Any, str, int, float, str]] = {}


class F5EnglishCloneBackend:
    """Real-time zero-shot English voice cloning via F5-TTS Flow-Matching (SWivid/F5-TTS)."""

    name = "f5_clone"

    def __init__(self, cfg: SparkyServiceConfig, dsp_mode: str = "gutsy_fiel") -> None:
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
        cache_key = (str(self.cfg.ref_wav_path), self.cfg.ref_text_en, int(self.cfg.f5_nfe_step))
        cached = _F5_EN_CACHE.get(cache_key)
        if cached is not None:
            self.f5, self._ref_audio, self._ref_text_clean, self._max_chars, self._ref_speech_dur_s, self.device_label = cached
            return 0.0
        t0 = time.perf_counter()
        if not self.cfg.ref_wav_path.is_file():
            raise FileNotFoundError(f"Missing SPARKY reference audio: {self.cfg.ref_wav_path}")

        logging.getLogger("torch.distributed.elastic.multiprocessing.redirects").setLevel(logging.ERROR)
        logging.getLogger("huggingface_hub.utils._http").setLevel(logging.ERROR)

        import torch
        import torchaudio
        from f5_tts.api import F5TTS

        def _sf_load(uri: Any, *args: Any, **kwargs: Any) -> tuple[Any, int]:
            data, sr_loaded = sf.read(str(uri), dtype="float32", always_2d=True)
            return torch.from_numpy(data.T.copy()), int(sr_loaded)

        torchaudio.load = _sf_load  # type: ignore[assignment]

        ckpt_path = _hf_cached_or_download(self.cfg.f5_repo_id, self.cfg.f5_ckpt_filename)
        vocos_cfg = _hf_cached_or_download("charactr/vocos-mel-24khz", "config.yaml")
        _ = _hf_cached_or_download("charactr/vocos-mel-24khz", "pytorch_model.bin")
        vocoder_local_dir = str(Path(vocos_cfg).parent)

        device = "cuda" if torch.cuda.is_available() else "cpu"
        self.device_label = f"{device} (F5-TTS v1 Base EN NFE={self.cfg.f5_nfe_step})"

        with contextlib.redirect_stdout(io.StringIO()):
            self.f5 = F5TTS(
                model=self.cfg.f5_model_arch,
                ckpt_file=ckpt_path,
                vocab_file=self.cfg.f5_vocab_filename,
                vocoder_local_path=vocoder_local_dir,
                device=device,
            )

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

        ref_txt = sanitize_text_for_tts_en(self.cfg.ref_text_en) or self.cfg.ref_text_en.strip()
        if not ref_txt.endswith((".", "!", "?")):
            ref_txt = ref_txt + "."
        self._ref_text_clean = ref_txt + " "
        self._max_chars = min(
            145,
            max(
                95,
                int(len(self._ref_text_clean.encode("utf-8")) / dur_ref_s * max(4.0, 22.0 - dur_ref_s) * self.cfg.f5_speed_en),
            ),
        )

        _F5_EN_CACHE[cache_key] = (
            self.f5,
            self._ref_audio,
            self._ref_text_clean,
            self._max_chars,
            self._ref_speech_dur_s,
            self.device_label,
        )
        _ = self.synthesize("Tactical link online, recruit.")
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.f5 is None or self._ref_audio is None:
            self.warmup()
        spoken = sanitize_text_for_tts_en(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate
        if not spoken.endswith((".", "!", "?", "...")):
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
        speed_val = max(0.75, float(self.cfg.f5_speed_en))

        parts: list[np.ndarray] = []
        infer_sr = int(self.cfg.sample_rate)
        for b_idx, batch in enumerate(batches):
            chunk_txt = batch.strip().rstrip(",;:")
            if not chunk_txt:
                continue
            if not chunk_txt.endswith((".", "!", "?", "...")):
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
    """Veteran US drill-sergeant voice sculpted by blending Kokoro English male vectors + CyberAiDSP."""

    name = "kokoro_sergeant"

    def __init__(self, cfg: SparkyServiceConfig) -> None:
        super().__init__(cfg)
        self.voice_blend: np.ndarray | None = None
        self.device_label = "ONNX CPU Sergeant Blend (0 MB VRAM)"

    def warmup(self) -> float:
        if self.kokoro is not None and self.voice_blend is not None:
            return 0.0
        t0 = time.perf_counter()
        from kokoro_onnx import Kokoro

        onnx_path, voices_path = self._ensure_assets()
        self.kokoro = Kokoro(str(onnx_path), str(voices_path))
        fenrir = self.kokoro.get_voice_style("am_fenrir").astype(np.float32)
        onyx = self.kokoro.get_voice_style("am_onyx").astype(np.float32)
        santa = self.kokoro.get_voice_style("am_santa").astype(np.float32)
        self.voice_blend = (0.45 * fenrir + 0.35 * onyx + 0.20 * santa).astype(np.float32)
        _ = self.synthesize("Kiroshi optic link calibrated, recruit.")
        return time.perf_counter() - t0

    def synthesize(self, text: str) -> tuple[np.ndarray, int]:
        if self.kokoro is None or self.voice_blend is None:
            self.warmup()
        spoken = sanitize_text_for_tts_en(text)
        if not spoken:
            return np.zeros(0, dtype=np.float32), self.cfg.sample_rate

        pitch_ratio = 2.0 ** (-1.10 / 12.0)  # ~0.9384 (-1.10 semitones)
        gen_speed = float(self.cfg.kokoro_sergeant_speed_en) / pitch_ratio
        samples, sr = self.kokoro.create(
            spoken,
            voice=self.voice_blend,
            speed=gen_speed,
            lang="en-us",
        )
        raw = np.asarray(samples, dtype=np.float32).reshape(-1)
        lowered, out_sr = _resample_if_needed(raw, int(round(sr * pitch_ratio)), self.cfg.sample_rate)
        filtered = CyberAiDSP.process(lowered, out_sr, mode="full_cyber_ai")
        return filtered, out_sr


def create_tts_backend(engine_name: str, cfg: SparkyServiceConfig) -> TTSBackend:
    """Explicit factory to switch between English F5 clone (Gutsy/Clean), Kokoro Sergeant/Base, and Qwen3."""
    if engine_name == "f5_clone":
        return F5EnglishCloneBackend(cfg, dsp_mode="gutsy_fiel")
    if engine_name == "f5_clean":
        return F5EnglishCloneBackend(cfg, dsp_mode="light_polish")
    if engine_name == "kokoro_sergeant":
        return KokoroSergeantBackend(cfg)
    if engine_name == "kokoro_onnx":
        return KokoroONNXBackend(cfg)
    if engine_name == "qwen3_clone":
        return Qwen3CloneBackend(cfg)
    raise ValueError(f"Unknown TTS backend: {engine_name!r}")
