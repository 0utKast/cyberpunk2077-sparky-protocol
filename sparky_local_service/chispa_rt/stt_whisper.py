"""Reconocimiento de voz local en español mediante faster-whisper (0 MB GPU VRAM)."""

from __future__ import annotations

import time
from typing import Any

import numpy as np

CYBERPUNK_ES_PROMPT = (
    "Conversación táctica en Cyberpunk 2077 en español de España: "
    "Chispa, V, Kiroshi, Night City, Watson, Pacifica, Heywood, Arasaka, "
    "Militech, Maelstrom, Hijos del Vudú, Garras de Tigre, Calle Seis, "
    "Valentinos, edis, matasanos, ciberware, subred, Muro Negro."
)


class WhisperSTTBackend:
    """Transcribe micrófono 16 kHz mono en CPU (`int8`) sin consumir VRAM de la 5070 Ti."""

    def __init__(
        self,
        model_size: str = "small",
        device: str = "cpu",
        compute_type: str = "int8",
        cpu_threads: int = 8,
    ) -> None:
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self.cpu_threads = cpu_threads
        self.model: Any = None

    def warmup(self) -> float:
        if self.model is not None:
            return 0.0
        t0 = time.perf_counter()
        from faster_whisper import WhisperModel

        self.model = WhisperModel(
            self.model_size,
            device=self.device,
            compute_type=self.compute_type,
            cpu_threads=self.cpu_threads,
        )
        # Pasada corta silenciosa para inicializar filtros/VAD
        _, _ = self.model.transcribe(np.zeros(8000, dtype=np.float32), language="es", vad_filter=False)
        return time.perf_counter() - t0

    def transcribe(self, audio_16k: np.ndarray) -> tuple[str, float]:
        if self.model is None:
            self.warmup()
        wav = np.asarray(audio_16k, dtype=np.float32).reshape(-1)
        if wav.size < int(16000 * 0.35):
            return "", 0.0
        if float(np.max(np.abs(wav))) < 0.008:
            return "", 0.0

        t0 = time.perf_counter()
        segments, _ = self.model.transcribe(
            wav,
            language="es",
            beam_size=2,
            vad_filter=True,
            initial_prompt=CYBERPUNK_ES_PROMPT,
        )
        parts = [seg.text.strip() for seg in segments if seg.text and seg.text.strip()]
        text = " ".join(parts).strip()
        elapsed_ms = (time.perf_counter() - t0) * 1000.0
        return text, elapsed_ms
