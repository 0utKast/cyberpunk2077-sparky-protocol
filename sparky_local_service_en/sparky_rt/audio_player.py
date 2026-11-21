"""Windows WASAPI stereo-adaptive audio output (44.1/48 kHz) and microphone capture."""

from __future__ import annotations

import ctypes
import json
import math
import queue
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np
import sounddevice as sd
import soundfile as sf
from scipy import signal

from sparky_rt.config import SERVICE_ROOT

PREFS_PATH = SERVICE_ROOT / "user_audio_prefs.json"

_VIRTUAL_PREFIXES = (
    "asignador de sonido",
    "microsoft sound mapper",
    "controlador primario",
    "primary sound",
)


@dataclass
class AudioDeviceEntry:
    index: int
    name: str
    samplerate: int
    channels: int
    hostapi_name: str
    is_default: bool = False


def load_audio_prefs() -> dict[str, Any]:
    if not PREFS_PATH.is_file():
        return {}
    try:
        return json.loads(PREFS_PATH.read_text(encoding="utf-8"))
    except Exception:
        return {}


def save_audio_prefs(output_name: str | None = None, input_name: str | None = None, tts_engine: str | None = None) -> None:
    prefs = load_audio_prefs()
    if output_name is not None:
        prefs["output_device_name"] = output_name
    if input_name is not None:
        prefs["input_device_name"] = input_name
    if tts_engine is not None:
        prefs["tts_engine"] = tts_engine
    tmp = PREFS_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(prefs, indent=2, ensure_ascii=False), encoding="utf-8")
    tmp.replace(PREFS_PATH)


def _clean_devices(is_output: bool) -> list[AudioDeviceEntry]:
    devices = sd.query_devices()
    hostapis = sd.query_hostapis()
    def_in, def_out = sd.default.device

    api_rank: dict[int, tuple[int, str]] = {}
    for idx, ha in enumerate(hostapis):
        hname = str(ha.get("name", ""))
        low = hname.lower()
        if "wasapi" in low:
            rank = 0
        elif "mme" in low:
            rank = 1
        elif "directsound" in low:
            rank = 2
        else:
            rank = 3
        api_rank[idx] = (rank, hname)

    target_default = int(def_out) if is_output else int(def_in)
    default_name = ""
    if 0 <= target_default < len(devices):
        default_name = str(devices[target_default]["name"]).strip().lower()

    candidates: list[tuple[int, AudioDeviceEntry]] = []
    for idx, dev in enumerate(devices):
        ch = int(dev["max_output_channels"] if is_output else dev["max_input_channels"])
        if ch <= 0:
            continue
        name = str(dev["name"]).strip()
        if any(name.lower().startswith(pref) for pref in _VIRTUAL_PREFIXES):
            continue
        api_idx = int(dev["hostapi"])
        rank, api_name = api_rank.get(api_idx, (9, "Other"))
        if rank >= 2:
            continue
        sr = int(round(float(dev.get("default_samplerate") or 48000.0)))
        clean_name = name.replace("\r", " ").replace("\n", " ").strip()
        is_def = bool(default_name and clean_name.lower().startswith(default_name[:24]))
        candidates.append(
            (
                rank,
                AudioDeviceEntry(
                    index=idx,
                    name=clean_name,
                    samplerate=sr,
                    channels=min(ch, 2),
                    hostapi_name=api_name,
                    is_default=is_def,
                ),
            )
        )

    candidates.sort(key=lambda item: (item[0], item[1].index))
    seen_prefixes: set[str] = set()
    unique: list[AudioDeviceEntry] = []
    for _, entry in candidates:
        key = entry.name.lower()[:28]
        if key in seen_prefixes:
            continue
        seen_prefixes.add(key)
        unique.append(entry)
    return unique


def list_output_devices() -> list[AudioDeviceEntry]:
    return _clean_devices(is_output=True)


def list_input_devices() -> list[AudioDeviceEntry]:
    return _clean_devices(is_output=False)


def resolve_default_output_index(devices: list[AudioDeviceEntry]) -> int:
    if not devices:
        return int(sd.default.device[1])
    prefs = load_audio_prefs()
    saved_name = str(prefs.get("output_device_name") or "").strip().lower()
    if saved_name:
        for d in devices:
            if d.name.lower() == saved_name:
                return d.index
    for d in devices:
        if d.is_default:
            return d.index
    return devices[0].index


def _resample_audio(samples: np.ndarray, src_sr: int, dst_sr: int) -> np.ndarray:
    if src_sr == dst_sr or samples.size == 0:
        return np.asarray(samples, dtype=np.float32).reshape(-1)
    g = math.gcd(int(src_sr), int(dst_sr))
    up = int(dst_sr // g)
    down = int(src_sr // g)
    return signal.resample_poly(samples.astype(np.float64), up, down).astype(np.float32)


class WASAPIStreamPlayer:
    """Streams PCM audio cleanly using the speaker's native sample rate and channel count."""

    def __init__(
        self,
        sample_rate: int = 24000,
        block_size: int = 1024,
        device_index: int | None = None,
    ) -> None:
        self.sample_rate = sample_rate
        self.block_size = block_size
        self.device_index = device_index
        self._queue: queue.Queue[tuple[int, np.ndarray] | None] = queue.Queue()
        self._cancel_event = threading.Event()
        self._reopen_event = threading.Event()
        self._state_lock = threading.Lock()
        self._active_lock = threading.Lock()
        self._idle_event = threading.Event()
        self._idle_event.set()
        self._generation = 0
        self._last_error: str | None = None
        self._worker = threading.Thread(target=self._run_loop, name="sparky-audio-out", daemon=True)
        self._worker.start()

    def set_device(self, device_index: int | None) -> None:
        self.interrupt()
        self.device_index = device_index
        self._reopen_event.set()

    def _pick_stream_params(self) -> tuple[int | None, int, int]:
        dev_idx = self.device_index
        try:
            info = sd.query_devices(dev_idx, kind="output") if dev_idx is not None else sd.query_devices(kind="output")
            pref_sr = int(round(float(info.get("default_samplerate") or 48000.0)))
            max_ch = int(info.get("max_output_channels") or 2)
        except Exception:
            pref_sr = 48000
            max_ch = 2

        out_ch = 2 if max_ch >= 2 else 1
        for sr_try in (pref_sr, 48000, 44100, self.sample_rate):
            for ch_try in (out_ch, 1 if out_ch == 2 else 2):
                try:
                    sd.check_output_settings(device=dev_idx, samplerate=sr_try, channels=ch_try, dtype="float32")
                    return dev_idx, int(sr_try), int(ch_try)
                except Exception:
                    continue
        return dev_idx, 48000, 2

    def enqueue(self, samples: np.ndarray) -> None:
        wav = np.asarray(samples, dtype=np.float32).reshape(-1)
        if wav.size == 0:
            return
        with self._state_lock:
            self._cancel_event.clear()
            self._idle_event.clear()
            self._queue.put((self._generation, wav))

    def play_test_tone(self) -> None:
        """Plays a brief two-tone Kiroshi chime to test speaker hardware."""
        sr = self.sample_rate
        t1 = np.linspace(0.0, 0.14, int(sr * 0.14), endpoint=False, dtype=np.float32)
        t2 = np.linspace(0.0, 0.22, int(sr * 0.22), endpoint=False, dtype=np.float32)
        env1 = np.sin(np.pi * np.linspace(0.0, 1.0, t1.size, dtype=np.float32))
        env2 = np.sin(np.pi * np.linspace(0.0, 1.0, t2.size, dtype=np.float32))
        b1 = 0.50 * np.sin(2.0 * np.pi * 680.0 * t1) * env1
        gap = np.zeros(int(sr * 0.05), dtype=np.float32)
        b2 = 0.55 * np.sin(2.0 * np.pi * 1020.0 * t2) * env2
        self.interrupt()
        self.enqueue(np.concatenate([b1, gap, b2]).astype(np.float32))

    def play_voice_check(self, ref_wav_path: Path | None = None) -> None:
        """Plays a short real SPARKY voice sample immediately without waiting for model warmup."""
        if ref_wav_path is not None and ref_wav_path.is_file():
            try:
                wav, sr = sf.read(str(ref_wav_path), dtype="float32")
                if wav.ndim > 1:
                    wav = np.mean(wav, axis=1).astype(np.float32)
                wav = wav[: int(sr * 3.35)]
                wav = _resample_audio(wav, int(sr), self.sample_rate)
                peak = float(np.max(np.abs(wav)) + 1e-8)
                wav = (wav * (0.88 / peak)).astype(np.float32)
                fade = min(int(self.sample_rate * 0.02), wav.size // 4)
                if fade > 1:
                    wav[-fade:] *= np.linspace(1.0, 0.0, fade, dtype=np.float32)
                self.interrupt()
                self.enqueue(wav)
                return
            except Exception as exc:
                print(f"[AUDIO WARNING] Falling back to chime on speaker test: {exc}")
        self.play_test_tone()

    def wait_until_done(self, timeout: float | None = None) -> bool:
        return self._idle_event.wait(timeout=timeout)

    def interrupt(self) -> None:
        """Stops playback immediately and clears any queued clauses."""
        with self._state_lock:
            self._generation += 1
            self._cancel_event.set()
            while True:
                try:
                    _ = self._queue.get_nowait()
                except queue.Empty:
                    break
            self._idle_event.set()

    def close(self) -> None:
        self.interrupt()
        self._queue.put(None)
        self._worker.join(timeout=1.5)

    def _open_output_stream(self, dev_idx: int | None, dev_sr: int, out_ch: int) -> Any:
        try:
            return sd.OutputStream(
                device=dev_idx,
                samplerate=dev_sr,
                channels=out_ch,
                dtype="float32",
                blocksize=0,
                latency=0.10,
            )
        except TypeError:
            return sd.OutputStream(
                device=dev_idx,
                samplerate=dev_sr,
                channels=out_ch,
                dtype="float32",
                blocksize=self.block_size,
            )

    def _run_loop(self) -> None:
        com_inited = False
        try:
            ctypes.windll.ole32.CoInitializeEx(None, 0)
            com_inited = True
        except Exception:
            pass
        try:
            while True:
                first_item = self._queue.get()
                if first_item is None:
                    return
                with self._active_lock:
                    while True:
                        dev_idx, dev_sr, out_ch = self._pick_stream_params()
                        should_reopen = False
                        try:
                            with self._open_output_stream(dev_idx, dev_sr, out_ch) as stream:
                                self._last_error = None
                                warm_buf = np.zeros((max(1, int(dev_sr * 0.22)), out_ch), dtype=np.float32)
                                keepalive_buf = np.zeros((max(1, int(dev_sr * 0.025)), out_ch), dtype=np.float32)
                                inter_clause_buf = np.zeros((max(1, int(dev_sr * 0.055)), out_ch), dtype=np.float32)
                                drain_buf = np.zeros((max(1, int(dev_sr * 0.28)), out_ch), dtype=np.float32)
                                write_step = max(1024, int(dev_sr * 0.04))
                                stream.write(warm_buf)

                                pending: tuple[int, np.ndarray] | None = first_item
                                first_item = None
                                while True:
                                    if pending is None:
                                        if self._reopen_event.is_set():
                                            self._reopen_event.clear()
                                            should_reopen = True
                                            break
                                        try:
                                            nxt = self._queue.get_nowait()
                                        except queue.Empty:
                                            stream.write(keepalive_buf)
                                            continue
                                        if nxt is None:
                                            return
                                        pending = nxt

                                    gen, wav_raw = pending
                                    pending = None
                                    if gen != self._generation or self._reopen_event.is_set():
                                        if self._queue.empty():
                                            self._idle_event.set()
                                        continue

                                    wav_dev = _resample_audio(wav_raw, self.sample_rate, dev_sr)
                                    if out_ch == 2:
                                        buf = np.ascontiguousarray(np.column_stack([wav_dev, wav_dev]), dtype=np.float32)
                                    else:
                                        buf = np.ascontiguousarray(wav_dev.reshape(-1, 1), dtype=np.float32)

                                    pos = 0
                                    total = buf.shape[0]
                                    aborted = False
                                    while pos < total:
                                        if gen != self._generation or self._reopen_event.is_set():
                                            aborted = True
                                            break
                                        end = min(pos + write_step, total)
                                        stream.write(buf[pos:end])
                                        pos = end

                                    if not aborted and not self._reopen_event.is_set():
                                        try:
                                            peek = self._queue.get_nowait()
                                        except queue.Empty:
                                            peek = None
                                        else:
                                            if peek is None:
                                                stream.write(drain_buf)
                                                self._idle_event.set()
                                                return
                                            pending = peek
                                            if peek[0] == self._generation:
                                                stream.write(inter_clause_buf)
                                        if pending is None:
                                            stream.write(drain_buf)

                                    if pending is None and self._queue.empty():
                                        self._idle_event.set()
                        except Exception as exc:
                            self._last_error = str(exc)
                            print(f"[AUDIO WARNING] Error opening output stream (device={dev_idx}, {dev_sr} Hz, {out_ch}ch): {exc}")
                            if self._queue.empty():
                                self._idle_event.set()
                            break
                        if not should_reopen:
                            break
                        nxt_after_reopen = self._queue.get()
                        if nxt_after_reopen is None:
                            return
                        first_item = nxt_after_reopen
        finally:
            if com_inited:
                try:
                    ctypes.windll.ole32.CoUninitialize()
                except Exception:
                    pass
