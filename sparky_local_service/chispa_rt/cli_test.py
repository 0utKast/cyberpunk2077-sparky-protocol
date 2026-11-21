"""CLI de prueba en español y comparativa directa F5-Spanish Clonado vs Kokoro Sargento/Base."""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import soundfile as sf

from chispa_rt.audio_player import WASAPIStreamPlayer, list_output_devices, resolve_default_output_index
from chispa_rt.config import ChispaServiceConfig, get_gpu_vram_status
from chispa_rt.llm_ollama import OllamaChispaClient
from chispa_rt.tts_backends import TTSBackend, create_tts_backend

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

AB_SAMPLE_TEXT_ES = (
    "Escúchame bien, recluta: esos Hijos del Vudú tienen dos cámaras enlazadas y una torreta automática en la entrada. "
    "Ni se te ocurra entrar pegando tiros como un novato; dame un escaneo Kiroshi y déjame freírles la subred primero."
)


def _print_vram(prefix: str, baseline_mib: int | None = None) -> int:
    st = get_gpu_vram_status()
    if st.nvml_ok:
        delta = f" | delta IA: +{st.used_mib - baseline_mib} MiB" if baseline_mib is not None else ""
        print(
            f"[{prefix}] GPU: {st.gpu_name} | VRAM usada: {st.used_mib} MiB / {st.total_mib} MiB "
            f"(libres: {st.free_mib} MiB{delta})"
        )
        return st.used_mib
    print(f"[{prefix}] GPU NVML no disponible (modo CPU)")
    return 0


def run_ab_comparison(cfg: ChispaServiceConfig, play_audio: bool) -> None:
    """Genera el mismo guion con los 3 motores rápidos para comparar timbre y latencia."""
    cfg.audio_out_dir.mkdir(parents=True, exist_ok=True)
    def_out = resolve_default_output_index(list_output_devices()) if play_audio else None
    player = WASAPIStreamPlayer(cfg.sample_rate, device_index=def_out) if play_audio else None

    print("=== COMPARATIVA EN ESPAÑOL EN TIEMPO REAL (CHISPA v2.0) ===")
    print(f"Guion de prueba: «{AB_SAMPLE_TEXT_ES}»\n")
    baseline = _print_vram("INICIO")

    specs = [
        ("f5_clone", cfg.audio_out_dir / "comparativa_f5_chispa_clonado.wav"),
        ("kokoro_sergeant", cfg.audio_out_dir / "comparativa_kokoro_sargento_blend.wav"),
        ("kokoro_onnx", cfg.audio_out_dir / "comparativa_kokoro_em_alex_base.wav"),
    ]

    try:
        for engine_name, out_path in specs:
            backend = create_tts_backend(engine_name, cfg)
            warm_s = backend.warmup()
            t0 = time.perf_counter()
            wav, sr = backend.synthesize(AB_SAMPLE_TEXT_ES)
            synth_s = time.perf_counter() - t0
            dur_s = float(wav.size) / float(sr)
            rtf = synth_s / max(dur_s, 1e-4)
            rms = float(np.sqrt(np.mean(wav * wav) + 1e-12))

            sf.write(str(out_path), wav, sr)
            print(
                f"• Motor '{engine_name}' ({backend.device_label}) -> "
                f"warmup={warm_s:.2f}s | síntesis={synth_s*1000:.0f} ms | "
                f"audio={dur_s:.2f}s | RTF={rtf:.3f} | RMS={rms:.3f} | WAV={out_path.name}"
            )
            _print_vram(f"TRAS {engine_name}", baseline_mib=baseline)
            if player is not None:
                print(f"  Reproduciendo '{out_path.name}'...")
                player.enqueue(wav)
                player.wait_until_done(timeout=dur_s + 2.0)

            del backend
            try:
                import gc, torch

                gc.collect()
                if torch.cuda.is_available():
                    torch.cuda.empty_cache()
            except Exception:
                pass
    finally:
        if player is not None:
            player.close()


def run_single_turn(
    ollama: OllamaChispaClient,
    backend: TTSBackend,
    history: list[dict[str, str]],
    user_text: str,
    player: WASAPIStreamPlayer | None,
    save_wav_path: Path | None = None,
) -> str:
    """Ejecuta un turno completo streaming LLM -> TTS por cláusulas -> WASAPI."""
    t_turn0 = time.perf_counter()
    first_audio_ms: float | None = None
    first_ttft_ms: float | None = None
    full_reply_parts: list[str] = []
    audio_chunks: list[np.ndarray] = []

    print("\nCHISPA> ", end="", flush=True)
    for clause in ollama.stream_clauses(history, user_text):
        if first_ttft_ms is None:
            first_ttft_ms = clause.ttft_ms
        print(clause.text, end=" ", flush=True)
        full_reply_parts.append(clause.text)

        wav, sr = backend.synthesize(clause.text)
        if wav.size > 0:
            if first_audio_ms is None:
                first_audio_ms = (time.perf_counter() - t_turn0) * 1000.0
            audio_chunks.append(wav)
            if player is not None:
                player.enqueue(wav)

    print("")
    full_reply = " ".join(full_reply_parts).strip()
    total_ms = (time.perf_counter() - t_turn0) * 1000.0
    if player is not None:
        player.wait_until_done(timeout=60.0)

    if save_wav_path is not None and audio_chunks:
        save_wav_path.parent.mkdir(parents=True, exist_ok=True)
        combined = np.concatenate(audio_chunks)
        sf.write(str(save_wav_path), combined, backend.cfg.sample_rate if hasattr(backend, "cfg") else 24000)

    st = get_gpu_vram_status()
    vram_str = f" | VRAM: {st.used_mib}/{st.total_mib} MiB (libre: {st.free_mib} MiB)" if st.nvml_ok else ""
    print(
        f"  [Métricas] TTFT LLM: {first_ttft_ms or 0:.0f} ms | "
        f"TTFA (1.ª sílaba hablada): {first_audio_ms or 0:.0f} ms | "
        f"Total turno: {total_ms:.0f} ms{vram_str}"
    )

    if full_reply:
        history.append({"role": "user", "content": user_text})
        history.append({"role": "assistant", "content": full_reply})
    return full_reply


def run_interactive_repl(cfg: ChispaServiceConfig, play_audio: bool) -> None:
    print("=== C.H.I.S.P.A. v2.0 — CONSOLA LOCAL EN VIVO (ESPAÑOL) ===")
    baseline = _print_vram("ARRANQUE")

    ollama = OllamaChispaClient(cfg)
    print(f"Cargando LLM local en Ollama ({cfg.llm_model})...")
    ollama.ensure_model_loaded()

    backends: dict[str, TTSBackend] = {}
    current_name = cfg.tts_engine
    backends[current_name] = create_tts_backend(current_name, cfg)
    print(f"Calentando motor de voz '{current_name}' ({backends[current_name].device_label})...")
    warm_s = backends[current_name].warmup()
    print(f"Listo en {warm_s:.2f}s. Escribe como si fueras V.")
    print("Comandos: /voz f5 | /voz sargento | /voz kokoro | /voz qwen | /vram | /limpiar | /salir\n")
    _print_vram("ACTIVO", baseline_mib=baseline)

    def_out = resolve_default_output_index(list_output_devices()) if play_audio else None
    player = WASAPIStreamPlayer(cfg.sample_rate, device_index=def_out) if play_audio else None
    history: list[dict[str, str]] = []

    try:
        while True:
            try:
                user_text = input("V> ").strip()
            except (EOFError, KeyboardInterrupt):
                break
            if not user_text:
                continue

            if player is not None:
                player.interrupt()

            low = user_text.lower()
            if low in ("/salir", "/exit", "/quit"):
                break
            if low == "/vram":
                _print_vram("ESTADO", baseline_mib=baseline)
                continue
            if low == "/limpiar":
                history.clear()
                print("[Historial de sesión reiniciado]")
                continue
            if low.startswith("/voz "):
                target = low.split(maxsplit=1)[1].strip()
                alias_map = {
                    "f5": "f5_clone",
                    "f5_clone": "f5_clone",
                    "clon": "f5_clone",
                    "sargento": "kokoro_sergeant",
                    "kokoro_sergeant": "kokoro_sergeant",
                    "kokoro": "kokoro_onnx",
                    "kokoro_onnx": "kokoro_onnx",
                    "qwen": "qwen3_clone",
                    "qwen3": "qwen3_clone",
                    "qwen3_clone": "qwen3_clone",
                }
                mapped = alias_map.get(target, "")
                if not mapped:
                    print("Usa: /voz f5 | /voz sargento | /voz kokoro | /voz qwen")
                    continue
                if mapped not in backends:
                    backends[mapped] = create_tts_backend(mapped, cfg)
                    w = backends[mapped].warmup()
                    print(f"[Motor '{mapped}' inicializado en {w:.2f}s]")
                current_name = mapped
                print(f"[Voz activa cambiada a '{current_name}' ({backends[current_name].device_label})]")
                continue

            run_single_turn(
                ollama=ollama,
                backend=backends[current_name],
                history=history,
                user_text=user_text,
                player=player,
                save_wav_path=cfg.audio_out_dir / f"ultima_respuesta_{current_name}.wav",
            )
    finally:
        if player is not None:
            player.close()
        ollama.close()


def main() -> None:
    parser = argparse.ArgumentParser(description="Prueba Fase 1 de CHISPA v2.0 100% local en español")
    parser.add_argument("--ab-compare", action="store_true", help="Genera comparativa F5 Clonado vs Kokoro Sargento/Base")
    parser.add_argument("--once", default="", help="Ejecuta un único turno LLM + TTS y guarda WAV")
    parser.add_argument(
        "--tts",
        default="f5_clone",
        choices=["f5_clone", "f5_clean", "kokoro_sergeant", "kokoro_onnx", "qwen3_clone"],
        help="Motor TTS",
    )
    parser.add_argument("--model", default=ChispaServiceConfig().llm_model, help="Modelo en Ollama")
    parser.add_argument("--no-play", action="store_true", help="No reproduce por altavoces (solo guarda WAV)")
    args = parser.parse_args()

    cfg = ChispaServiceConfig(llm_model=args.model, tts_engine=args.tts)
    play_audio = not args.no_play

    if args.ab_compare:
        run_ab_comparison(cfg, play_audio=play_audio)
        return

    if args.once:
        ollama = OllamaChispaClient(cfg)
        ollama.ensure_model_loaded()
        backend = create_tts_backend(cfg.tts_engine, cfg)
        warm_s = backend.warmup()
        print(f"Motor '{cfg.tts_engine}' ({backend.device_label}) listo en {warm_s:.2f}s.")
        def_out = resolve_default_output_index(list_output_devices()) if play_audio else None
        player = WASAPIStreamPlayer(cfg.sample_rate, device_index=def_out) if play_audio else None
        try:
            run_single_turn(
                ollama=ollama,
                backend=backend,
                history=[],
                user_text=args.once,
                player=player,
                save_wav_path=cfg.audio_out_dir / f"ultima_respuesta_{cfg.tts_engine}.wav",
            )
        finally:
            if player is not None:
                player.close()
            ollama.close()
        return

    run_interactive_repl(cfg, play_audio=play_audio)


if __name__ == "__main__":
    main()
