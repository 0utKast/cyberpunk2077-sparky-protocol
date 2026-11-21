"""Configuración y monitorización NVML de VRAM para sparky_local_service."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

SERVICE_ROOT = Path(__file__).resolve().parent.parent

DEFAULT_REF_TEXT_ES = (
    "¡Atención, recluta! ¡Alto el fuego ahora mismo! "
    "¡Escanea a esos dos mastuerzos y el condensador industrial con tus ópticas Kiroshi."
)


@dataclass
class GpuVramStatus:
    """Instantánea de memoria de vídeo de la GPU principal."""

    gpu_name: str
    total_mib: int
    used_mib: int
    free_mib: int
    nvml_ok: bool


def get_gpu_vram_status() -> GpuVramStatus:
    """Consulta la VRAM real libre/ocupada mediante NVML (nvidia-ml-py)."""
    try:
        import pynvml  # type: ignore

        pynvml.nvmlInit()
        try:
            handle = pynvml.nvmlDeviceGetHandleByIndex(0)
            raw_name = pynvml.nvmlDeviceGetName(handle)
            gpu_name = raw_name.decode("utf-8", errors="replace") if isinstance(raw_name, bytes) else str(raw_name)
            mem = pynvml.nvmlDeviceGetMemoryInfo(handle)
            mib = 1024 * 1024
            return GpuVramStatus(
                gpu_name=gpu_name,
                total_mib=int(mem.total // mib),
                used_mib=int(mem.used // mib),
                free_mib=int(mem.free // mib),
                nvml_ok=True,
            )
        finally:
            pynvml.nvmlShutdown()
    except Exception:
        return GpuVramStatus(
            gpu_name="CPU / Sin NVML",
            total_mib=0,
            used_mib=0,
            free_mib=0,
            nvml_ok=False,
        )


def select_recommended_llm(free_mib: int, tier_mode: str = "auto") -> str:
    """Elige el modelo de Ollama más adecuado según el margen libre de VRAM."""
    if tier_mode == "s_max" and free_mib >= 6500:
        return "qwen2.5:7b"
    if tier_mode == "b_lite" or (free_mib > 0 and free_mib < 1800):
        return "qwen2.5:1.5b"
    if tier_mode == "auto" and free_mib >= 8000:
        return "qwen2.5:3b"
    return "qwen2.5:3b"


def resolve_optimal_num_gpu(llm_model: str, configured_num_gpu: Optional[int] = None) -> int:
    """Equilibra VRAM de Ollama frente a Cyberpunk 2077 4K + F5-TTS en GPUs <= 16 GB."""
    if configured_num_gpu is not None:
        return int(configured_num_gpu)
    st = get_gpu_vram_status()
    model_low = (llm_model or "").lower()
    if st.nvml_ok and 0 < st.total_mib <= 17000:
        if "gemma3:12b" in model_low:
            return 18 if st.total_mib <= 13000 else 28
        if "qwen2.5:7b" in model_low:
            return 16 if st.total_mib <= 13000 else 22
        if "gemma3:4b" in model_low:
            return 16 if st.total_mib <= 13000 else 24
    return -1


@dataclass
class ChispaServiceConfig:
    """Parámetros de ejecución de la Fase 1 (español por defecto)."""

    language: str = "es"
    ollama_url: str = "http://127.0.0.1:11434"
    llm_model: str = "gemma3:12b"
    llm_num_ctx: int = 4096
    llm_num_gpu: Optional[int] = None
    enable_online_wiki: bool = False
    embed_repo_id: str = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"
    embed_onnx_file: str = "onnx/model_quint8_avx2.onnx"
    tts_engine: str = "f5_clean"  # "f5_clean" | "f5_clone" | "kokoro_sergeant" | "kokoro_onnx" | "qwen3_clone"
    f5_repo_id: str = "jpgallegoar/F5-Spanish"
    f5_model_arch: str = "F5TTS_Base"
    f5_ckpt_filename: str = "model_1250000.safetensors"
    f5_vocab_filename: str = "vocab.txt"
    f5_nfe_step: int = 20
    f5_speed_es: float = 0.96
    qwen3_model_id: str = "Qwen/Qwen3-TTS-12Hz-0.6B-Base"
    qwen3_device: Optional[str] = None  # None -> auto CUDA si disponible
    ref_wav_path: Path = field(default_factory=lambda: SERVICE_ROOT / "models" / "chispa_ref_es.wav")
    ref_text_es: str = DEFAULT_REF_TEXT_ES
    kokoro_dir: Path = field(default_factory=lambda: SERVICE_ROOT / "models" / "kokoro")
    kokoro_voice_es: str = "em_alex"
    kokoro_speed_es: float = 1.06
    kokoro_sergeant_speed_es: float = 1.08
    voice_gender: str = "male"
    audio_out_dir: Path = field(default_factory=lambda: SERVICE_ROOT / "audio_out")
    sample_rate: int = 24000
    request_timeout_s: float = 45.0

    def __post_init__(self) -> None:
        default_wav = SERVICE_ROOT / "models" / "chispa_ref_es.wav"
        override_path = SERVICE_ROOT / "models" / "voice_override.json"
        if self.ref_wav_path == default_wav and override_path.is_file():
            try:
                data = json.loads(override_path.read_text(encoding="utf-8-sig"))
                rel_wav = str(data.get("ref_wav", "")).strip()
                if rel_wav:
                    cand = SERVICE_ROOT / "models" / rel_wav
                    if cand.is_file():
                        self.ref_wav_path = cand
                ref_txt = str(data.get("ref_text", "")).strip()
                if ref_txt:
                    self.ref_text_es = ref_txt
                kokoro_v = str(data.get("kokoro_voice", "")).strip()
                if kokoro_v:
                    self.kokoro_voice_es = kokoro_v
                gender = str(data.get("gender", "")).strip().lower()
                if gender in ("male", "female"):
                    self.voice_gender = gender
            except Exception:
                pass

    def ollama_base_options(self) -> dict[str, int]:
        """Opciones consistentes de contexto y capas GPU para precarga, streaming y recap."""
        opts: dict[str, int] = {"num_ctx": int(self.llm_num_ctx)}
        ng = resolve_optimal_num_gpu(self.llm_model, self.llm_num_gpu)
        if ng >= 0:
            opts["num_gpu"] = int(ng)
        return opts
