"""Real-time DSP chain emulating 2022 Zetatech Kiroshi radio optics."""

from __future__ import annotations

import math

import numpy as np
from scipy import signal


def _peaking_eq_sos(center_hz: float, gain_db: float, q: float, fs: int) -> np.ndarray:
    """Computes biquad peaking EQ coefficients in SOS form."""
    nyq = 0.5 * float(fs)
    if center_hz >= nyq * 0.95 or abs(gain_db) < 1e-4:
        return np.array([[1.0, 0.0, 0.0, 1.0, 0.0, 0.0]], dtype=np.float64)
    a_lin = 10.0 ** (gain_db / 40.0)
    w0 = 2.0 * math.pi * center_hz / float(fs)
    alpha = math.sin(w0) / (2.0 * q)
    cos_w0 = math.cos(w0)

    b0 = 1.0 + alpha * a_lin
    b1 = -2.0 * cos_w0
    b2 = 1.0 - alpha * a_lin
    a0 = 1.0 + alpha / a_lin
    a1 = -2.0 * cos_w0
    a2 = 1.0 - alpha / a_lin

    return np.array([[b0 / a0, b1 / a0, b2 / a0, 1.0, a1 / a0, a2 / a0]], dtype=np.float64)


def _fast_pa_compress(x: np.ndarray, sr: int, threshold_db: float = -17.0, ratio: float = 4.6) -> np.ndarray:
    """Fast military PA envelope compressor (attack ~2.5 ms, release ~45 ms)."""
    arr = np.asarray(x, dtype=np.float64).reshape(-1)
    n = arr.size
    if n == 0:
        return arr

    hop = max(1, int(round(max(1, sr) * 0.002)))
    attack_coeff = math.exp(-float(hop) / max(1.0, 0.0025 * sr))
    release_coeff = math.exp(-float(hop) / max(1.0, 0.045 * sr))
    thresh_lin = 10.0 ** (threshold_db / 20.0)
    slope = 1.0 - (1.0 / max(ratio, 1.0))

    abs_x = np.abs(arr)
    n_blocks = (n + hop - 1) // hop
    pad_len = n_blocks * hop - n
    abs_pad = np.pad(abs_x, (0, pad_len), mode="edge") if pad_len > 0 else abs_x
    reshaped = abs_pad.reshape(n_blocks, hop)
    blk = 0.70 * np.max(reshaped, axis=1) + 0.30 * np.mean(reshaped, axis=1)

    env_blk = np.empty(n_blocks, dtype=np.float64)
    cur = 0.0
    for i, v in enumerate(blk.tolist()):
        c = attack_coeff if v > cur else release_coeff
        cur = c * cur + (1.0 - c) * v
        env_blk[i] = cur

    if n_blocks == 1:
        env = np.full(n, env_blk[0], dtype=np.float64)
    else:
        centers = (np.arange(n_blocks, dtype=np.float64) + 0.5) * float(hop)
        env = np.interp(np.arange(n, dtype=np.float64), centers, env_blk)

    gain = np.ones_like(env)
    over = env > thresh_lin
    if np.any(over):
        env_db = 20.0 * np.log10(np.maximum(env[over], 1e-8))
        gain_db = -slope * (env_db - threshold_db)
        gain[over] = 10.0 ** (gain_db / 20.0)

    return (arr * gain).astype(np.float64)


class CyberAiDSP:
    """Processes mono PCM audio with 2022 Zetatech Kiroshi vocal character."""

    @staticmethod
    def _apply_fade_edges(wav: np.ndarray, sr: int, fade_ms: float = 4.0, post_silence_s: float = 0.14) -> np.ndarray:
        fade_samples = min(int(sr * (fade_ms / 1000.0)), len(wav) // 4)
        out = wav.copy()
        if fade_samples > 1:
            ramp = np.linspace(0.0, 1.0, fade_samples, dtype=np.float32)
            out[:fade_samples] *= ramp
            out[-fade_samples:] *= ramp[::-1]
        if post_silence_s > 0.0 and sr > 0:
            pad = np.zeros(max(1, int(round(sr * post_silence_s))), dtype=np.float32)
            out = np.concatenate([out, pad]).astype(np.float32)
        return out

    @staticmethod
    def _soft_compress_and_ceiling(wav: np.ndarray, target_rms: float = 0.27, ceiling: float = 0.97) -> np.ndarray:
        x = wav.astype(np.float32, copy=False)
        rms = float(np.sqrt(np.mean(x * x) + 1e-10))
        if rms > 1e-5:
            gain = min(target_rms / rms, 5.5)
            x = x * gain
        x = np.tanh(x * 1.20) / math.tanh(1.20)
        peak = float(np.max(np.abs(x)) + 1e-10)
        if peak > ceiling:
            x = x * (ceiling / peak)
        return np.nan_to_num(x, nan=0.0, posinf=0.0, neginf=0.0).astype(np.float32)

    @classmethod
    def _process_radio_band(
        cls,
        wav: np.ndarray,
        sr: int,
        nyq: float,
        lowpass_hz: float,
        low_gain_db: float,
        mid_gain_db: float,
        echo_d1: float,
        echo_d2: float,
        target_rms: float,
        ceiling: float,
    ) -> np.ndarray:
        hp_sos = signal.butter(2, 85.0 / nyq, btype="highpass", output="sos")
        lp_sos = signal.butter(3, min(lowpass_hz, nyq * 0.92) / nyq, btype="lowpass", output="sos")
        eq_low = _peaking_eq_sos(135.0, low_gain_db, 1.1, sr)
        eq_mid = _peaking_eq_sos(1950.0, mid_gain_db, 1.4, sr)
        chain = np.vstack([hp_sos, eq_low, eq_mid, lp_sos])

        x = signal.sosfilt(chain, wav.astype(np.float64))
        d1 = max(1, int(sr * 0.007))
        d2 = max(2, int(sr * 0.014))
        echoed = x.copy()
        if echoed.size > d1 and echo_d1 > 0.0:
            echoed[d1:] += echo_d1 * x[:-d1]
        if echoed.size > d2 and echo_d2 > 0.0:
            echoed[d2:] += echo_d2 * x[:-d2]

        out = cls._soft_compress_and_ceiling(echoed.astype(np.float32), target_rms=target_rms, ceiling=ceiling)
        return cls._apply_fade_edges(out, sr)

    @classmethod
    def _process_gutsy_horn(cls, wav: np.ndarray, sr: int, nyq: float, mode: str) -> np.ndarray:
        """Applies calibrated metallic drill-horn acoustics ('gutsy_fiel' or 'gutsy_cyber')."""
        if mode == "gutsy_fiel":
            hp_hz, lp_hz = 455.0, 2850.0
            eq_specs = ((405.0, -6.5, 1.35), (815.0, -6.8, 2.0), (1365.0, 2.2, 1.6), (1970.0, 9.8, 2.15))
            drive, asym = 2.05, 0.13
            post_hp_hz, post_lp_hz = 435.0, 3350.0
            taps = ((0.0047, 0.22), (0.0081, 0.15), (0.0126, 0.08))
            comp_thresh_db, comp_ratio = -17.0, 4.6
        else:
            hp_hz, lp_hz = 260.0, 4300.0
            eq_specs = ((290.0, -3.5, 1.0), (815.0, -2.8, 1.5), (1365.0, 2.0, 1.4), (1950.0, 6.2, 1.7), (2750.0, 1.8, 1.4))
            drive, asym = 1.60, 0.09
            post_hp_hz, post_lp_hz = 240.0, 4800.0
            taps = ((0.0062, 0.16), (0.0114, 0.09))
            comp_thresh_db, comp_ratio = -17.5, 4.0

        hp_sos = signal.butter(4, min(hp_hz, nyq * 0.85) / nyq, btype="highpass", output="sos")
        lp_sos = signal.butter(3, min(lp_hz, nyq * 0.92) / nyq, btype="lowpass", output="sos")
        eq_chain = np.vstack([_peaking_eq_sos(f, g, q, sr) for f, g, q in eq_specs])
        x = signal.sosfilt(np.vstack([hp_sos, eq_chain, lp_sos]), wav.astype(np.float64))

        rms = float(np.sqrt(np.mean(x * x) + 1e-12))
        if rms > 1e-6:
            x = x * (0.19 / rms)

        bias = math.tanh(asym)
        driven = (np.tanh(drive * x + asym * (x * x)) - bias) / max(math.tanh(drive), 1e-4) * 0.35

        post_hp = signal.butter(2, min(post_hp_hz, nyq * 0.85) / nyq, btype="highpass", output="sos")
        post_lp = signal.butter(2, min(post_lp_hz, nyq * 0.92) / nyq, btype="lowpass", output="sos")
        clean_horn = signal.sosfilt(np.vstack([post_hp, post_lp]), driven)

        metallic = clean_horn.copy()
        for delay_s, tap_gain in taps:
            d = max(1, int(round(sr * delay_s)))
            if metallic.size > d:
                metallic[d:] += tap_gain * clean_horn[:-d]

        compressed = _fast_pa_compress(metallic, sr, threshold_db=comp_thresh_db, ratio=comp_ratio)
        compressed = compressed - float(np.mean(compressed))
        out = cls._soft_compress_and_ceiling(compressed.astype(np.float32), target_rms=0.28, ceiling=0.97)
        return cls._apply_fade_edges(out, sr, fade_ms=4.0)

    @classmethod
    def process(cls, samples: np.ndarray, sr: int, mode: str = "light_polish") -> np.ndarray:
        """Applies light polish, cloned cyber warmth, Gutsy horn, or full Kiroshi radio filter."""
        wav = np.asarray(samples, dtype=np.float32).reshape(-1)
        if wav.size == 0:
            return wav

        wav = wav - float(np.mean(wav))
        nyq = 0.5 * float(sr)

        if mode in ("gutsy_fiel", "gutsy_cyber"):
            return cls._process_gutsy_horn(wav, sr, nyq, mode)

        if mode == "light_polish":
            hp_sos = signal.butter(2, 80.0 / nyq, btype="highpass", output="sos")
            eq_warm = _peaking_eq_sos(180.0, 1.5, 1.0, sr)
            eq_pres = _peaking_eq_sos(2650.0, 2.8, 1.25, sr)
            filtered = signal.sosfilt(np.vstack([hp_sos, eq_warm, eq_pres]), wav.astype(np.float64))
            leveled = _fast_pa_compress(filtered, sr, threshold_db=-16.0, ratio=2.6)
            out = cls._soft_compress_and_ceiling(leveled.astype(np.float32), target_rms=0.30, ceiling=0.97)
            return cls._apply_fade_edges(out, sr, fade_ms=4.0)

        if mode == "cyber_clone_warmth":
            return cls._process_radio_band(
                wav,
                sr,
                nyq,
                lowpass_hz=7400.0,
                low_gain_db=1.8,
                mid_gain_db=2.0,
                echo_d1=0.10,
                echo_d2=0.05,
                target_rms=0.27,
                ceiling=0.97,
            )

        if mode == "full_cyber_ai":
            return cls._process_radio_band(
                wav,
                sr,
                nyq,
                lowpass_hz=6800.0,
                low_gain_db=2.4,
                mid_gain_db=2.5,
                echo_d1=0.16,
                echo_d2=0.09,
                target_rms=0.27,
                ceiling=0.97,
            )

        raise ValueError(f"Unsupported DSP mode: {mode!r}")
