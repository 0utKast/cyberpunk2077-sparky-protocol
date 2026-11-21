"""Estudio Cyberpunk de Chat por Texto con Respuesta Vocal en Vivo (C.H.I.S.P.A. v2.0)."""

from __future__ import annotations

import argparse
import os
import queue
import sys
import tempfile
import threading
import time
import tkinter as tk
from pathlib import Path
from tkinter import scrolledtext, ttk
from typing import Any

os.environ.setdefault("HF_HUB_DISABLE_SYMLINKS_WARNING", "1")

import numpy as np

from chispa_rt.audio_player import (
    AudioDeviceEntry,
    WASAPIStreamPlayer,
    list_output_devices,
    load_audio_prefs,
    resolve_default_output_index,
    save_audio_prefs,
)
from chispa_rt.companion_prefs import CompanionPrefs, load_companion_prefs, save_companion_prefs
from chispa_rt.config import ChispaServiceConfig, get_gpu_vram_status
from chispa_rt.episodic_memory import EpisodicMemoryManager, get_episodic_memory
from chispa_rt.llm_ollama import OllamaChispaClient
from chispa_rt.lore_rag import HybridCyberpunkRAG, format_rag_dossier, get_hybrid_rag
from chispa_rt.tts_backends import TTSBackend, create_tts_backend
from chispa_rt.wiki_online import lookup_wiki_online

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

TTS_OPTIONS = [
    ("f5_clean", "F5-Spanish Clonado — Sargento CHISPA Voz Limpia (GPU, RTF ~0.10)"),
    ("f5_clone", "F5-Spanish Clonado — Sargento CHISPA Bocina Gutsy (GPU, RTF ~0.10)"),
    ("kokoro_sergeant", "Kokoro Sargento Blend — Timbre Grave (CPU, 0 VRAM)"),
    ("kokoro_onnx", "Kokoro Base (em_alex + Radio DSP, CPU)"),
]

SPONTANEOUS_OPTIONS = [
    ("tactical", "Tácticas (Combate, Jefes, Distritos, Misiones)"),
    ("active", "Compañero Activo (+ Pinchos y Charla Ambiental)"),
    ("off", "Desactivadas (Solo al pulsar [Y] o [U])"),
]

BG_DARK = "#0b0f17"
BG_CARD = "#141c2b"
BG_INPUT = "#1a2436"
FG_TEXT = "#e6eef8"
FG_MUTED = "#8fa3bf"
ACCENT_CYAN = "#00f0ff"
ACCENT_YELLOW = "#fcee0a"
ACCENT_GREEN = "#39ff88"


class ChispaStudioApp:
    """Interfaz limpia para escribir por teclado y escuchar hablar a C.H.I.S.P.A. en directo."""

    def __init__(
        self,
        cfg: ChispaServiceConfig,
        start_warmup: bool = True,
        companion_prefs: CompanionPrefs | None = None,
        rag: HybridCyberpunkRAG | None = None,
        memory: EpisodicMemoryManager | None = None,
        prefs_saver: Any = save_companion_prefs,
    ) -> None:
        self.cfg = cfg
        self.prefs = load_audio_prefs()
        self.companion_prefs = companion_prefs if companion_prefs is not None else load_companion_prefs()
        self._save_companion_prefs = prefs_saver
        self.out_devices: list[AudioDeviceEntry] = list_output_devices()

        def_out_idx = resolve_default_output_index(self.out_devices)
        self.selected_out_idx: int | None = def_out_idx

        saved_tts = str(self.prefs.get("tts_engine") or cfg.tts_engine)
        if saved_tts not in ("f5_clean", "f5_clone", "kokoro_sergeant", "kokoro_onnx"):
            saved_tts = "f5_clean"
        self.current_tts_name = saved_tts

        self.player = WASAPIStreamPlayer(sample_rate=cfg.sample_rate, device_index=def_out_idx)
        self.ollama = OllamaChispaClient(cfg)
        self.tts_backends: dict[str, TTSBackend] = {}
        self.rag: HybridCyberpunkRAG | None = rag
        self.memory: EpisodicMemoryManager | None = memory

        self.history: list[dict[str, str]] = []
        self.ui_queue: queue.Queue[tuple[str, Any]] = queue.Queue()
        self.models_ready = False
        self.busy_turn = False
        self.turn_cancel = threading.Event()
        self.closing = False

        self._build_ui()
        if start_warmup:
            self._start_background_warmup()
        self._poll_ui_queue()

    def _build_ui(self) -> None:
        self.root = tk.Tk()
        self.root.title("C.H.I.S.P.A. v2.0 — Chat con Voz en Vivo (RTX 5070 Ti)")
        self.root.geometry("900x640")
        self.root.minsize(740, 520)
        self.root.configure(bg=BG_DARK)
        self.root.protocol("WM_DELETE_WINDOW", self._on_close)

        style = ttk.Style()
        try:
            style.theme_use("clam")
        except Exception:
            pass

        # Cabecera
        header = tk.Frame(self.root, bg=BG_DARK, padx=14, pady=10)
        header.pack(fill="x")
        tk.Label(
            header,
            text="ZETATECH 2022 // C.H.I.S.P.A. v2.0 — ESCRIBE Y ESCUCHA EN TIEMPO REAL",
            bg=BG_DARK,
            fg=ACCENT_CYAN,
            font=("Consolas", 13, "bold"),
        ).pack(anchor="w")
        tk.Label(
            header,
            text=f"Cerebro local: {self.cfg.llm_model} (Ollama)  •  Respuesta hablada por tus altavoces  •  100% Offline",
            bg=BG_DARK,
            fg=FG_MUTED,
            font=("Segoe UI", 9),
        ).pack(anchor="w")

        # Panel de altavoz y voz
        hw_card = tk.Frame(self.root, bg=BG_CARD, padx=12, pady=10, highlightbackground=ACCENT_CYAN, highlightthickness=1)
        hw_card.pack(fill="x", padx=14, pady=(0, 8))
        hw_card.columnconfigure(1, weight=1)

        # Fila 0: Salida de Audio + Botón Probar Altavoz
        tk.Label(hw_card, text="🔊 Altavoces (Salida):", bg=BG_CARD, fg=ACCENT_YELLOW, font=("Segoe UI", 9, "bold")).grid(
            row=0, column=0, sticky="w", padx=(0, 8), pady=3
        )
        out_labels = [f"[{d.index}] {d.name} ({d.samplerate} Hz)" for d in self.out_devices] or ["Predeterminado Windows"]
        self.out_var = tk.StringVar()
        self.out_combo = ttk.Combobox(hw_card, textvariable=self.out_var, values=out_labels, state="readonly")
        self.out_combo.grid(row=0, column=1, sticky="ew", pady=3, padx=(0, 8))
        sel_out_pos = next((i for i, d in enumerate(self.out_devices) if d.index == self.selected_out_idx), 0)
        if out_labels:
            self.out_combo.current(sel_out_pos)
        self.out_combo.bind("<<ComboboxSelected>>", self._on_output_changed)

        tk.Button(
            hw_card,
            text="🔊 Probar Altavoz",
            command=self._on_test_speaker,
            bg=ACCENT_YELLOW,
            fg="#090c12",
            activebackground="#ffe600",
            font=("Segoe UI", 9, "bold"),
            relief="flat",
            padx=12,
            pady=4,
            cursor="hand2",
        ).grid(row=0, column=2, sticky="e", pady=3)

        # Fila 1: Motor de Voz
        tk.Label(hw_card, text="🗣️ Voz de C.H.I.S.P.A.:", bg=BG_CARD, fg=FG_TEXT, font=("Segoe UI", 9, "bold")).grid(
            row=1, column=0, sticky="w", padx=(0, 8), pady=3
        )
        tts_labels = [label for _, label in TTS_OPTIONS]
        self.tts_var = tk.StringVar()
        self.tts_combo = ttk.Combobox(hw_card, textvariable=self.tts_var, values=tts_labels, state="readonly")
        self.tts_combo.grid(row=1, column=1, columnspan=2, sticky="ew", pady=3)
        tts_pos = next((i for i, (code, _) in enumerate(TTS_OPTIONS) if code == self.current_tts_name), 0)
        self.tts_combo.current(tts_pos)
        self.tts_combo.bind("<<ComboboxSelected>>", self._on_tts_changed)

        # Fila 2: Modo de Reacciones Espontáneas en el Juego
        tk.Label(hw_card, text="⚡ Reacciones en juego:", bg=BG_CARD, fg=ACCENT_CYAN, font=("Segoe UI", 9, "bold")).grid(
            row=2, column=0, sticky="w", padx=(0, 8), pady=3
        )
        spont_labels = [label for _, label in SPONTANEOUS_OPTIONS]
        self.spont_var = tk.StringVar()
        self.spont_combo = ttk.Combobox(hw_card, textvariable=self.spont_var, values=spont_labels, state="readonly")
        self.spont_combo.grid(row=2, column=1, columnspan=2, sticky="ew", pady=3)
        spont_pos = next(
            (i for i, (code, _) in enumerate(SPONTANEOUS_OPTIONS) if code == self.companion_prefs.spontaneous_mode),
            0,
        )
        self.spont_combo.current(spont_pos)
        self.spont_combo.bind("<<ComboboxSelected>>", self._on_spontaneous_changed)

        # Fila 3: Permiso explícito de Consulta Online a Cyberpunk Wiki (Desactivado por defecto)
        self.wiki_var = tk.BooleanVar(value=bool(self.companion_prefs.enable_online_wiki))
        self.wiki_chk = tk.Checkbutton(
            hw_card,
            text="🌐 Permitir consulta online a Cyberpunk Wiki (Desactivado por defecto — 100 % offline si no se marca)",
            variable=self.wiki_var,
            command=self._on_wiki_toggled,
            bg=BG_CARD,
            fg=FG_TEXT,
            activebackground=BG_CARD,
            activeforeground=ACCENT_YELLOW,
            selectcolor=BG_INPUT,
            font=("Segoe UI", 9),
            anchor="w",
            cursor="hand2",
        )
        self.wiki_chk.grid(row=3, column=0, columnspan=3, sticky="w", pady=(4, 0))

        # Aviso inteligente si Windows apunta a Razer Seiren Elite salida monitor y hay altavoces SAMSUNG/S/PDIF
        active_out = next((d for d in self.out_devices if d.index == self.selected_out_idx), None)
        if not self.prefs.get("output_device_name") and active_out and "razer seiren" in active_out.name.lower():
            other = next((d for d in self.out_devices if "razer seiren" not in d.name.lower()), None)
            if other:
                tk.Label(
                    hw_card,
                    text=(
                        f"⚠️ Windows tiene seleccionado por defecto '{active_out.name}' (toma de auriculares del micro). "
                        f"Si escuchas por '{other.name}', elígelo arriba y pulsa '🔊 Probar Altavoz'."
                    ),
                    bg=BG_CARD,
                    fg="#ffae42",
                    font=("Segoe UI", 8, "bold"),
                    wraplength=830,
                    justify="left",
                ).grid(row=4, column=0, columnspan=3, sticky="w", pady=(5, 0))

        # Área de conversación
        self.chat_box = scrolledtext.ScrolledText(
            self.root,
            bg="#0e1420",
            fg=FG_TEXT,
            insertbackground=ACCENT_CYAN,
            font=("Segoe UI", 10),
            wrap="word",
            relief="flat",
            padx=12,
            pady=10,
            state="disabled",
        )
        self.chat_box.pack(fill="both", expand=True, padx=14, pady=(0, 8))
        self.chat_box.tag_config("user", foreground=ACCENT_CYAN, font=("Segoe UI", 10, "bold"))
        self.chat_box.tag_config("chispa_lbl", foreground=ACCENT_YELLOW, font=("Segoe UI", 10, "bold"))
        self.chat_box.tag_config("chispa_txt", foreground=FG_TEXT, font=("Segoe UI", 10))
        self.chat_box.tag_config("meta", foreground=FG_MUTED, font=("Consolas", 8))

        # Barra inferior limpia solo escritura -> respuesta con voz
        ctrl = tk.Frame(self.root, bg=BG_DARK, padx=14)
        ctrl.pack(fill="x", pady=(0, 10))

        self.entry_var = tk.StringVar()
        self.entry = tk.Entry(
            ctrl,
            textvariable=self.entry_var,
            bg=BG_INPUT,
            fg=FG_TEXT,
            insertbackground=ACCENT_CYAN,
            font=("Segoe UI", 11),
            relief="flat",
        )
        self.entry.pack(side="left", fill="x", expand=True, ipady=9, padx=(0, 8))
        self.entry.bind("<Return>", lambda _e: self._on_send_text())
        self.entry.focus_set()

        tk.Button(
            ctrl,
            text="Enviar [Enter]",
            command=self._on_send_text,
            bg=ACCENT_CYAN,
            fg="#090c12",
            activebackground="#4df5ff",
            font=("Segoe UI", 10, "bold"),
            relief="flat",
            padx=16,
            pady=8,
            cursor="hand2",
        ).pack(side="left", padx=(0, 6))

        tk.Button(
            ctrl,
            text="⏹ Callar",
            command=self._on_interrupt,
            bg="#2b1e29",
            fg="#ff7b93",
            font=("Segoe UI", 10, "bold"),
            relief="flat",
            padx=12,
            pady=8,
            cursor="hand2",
        ).pack(side="left", padx=(0, 6))

        tk.Button(
            ctrl,
            text="🗑 Limpiar",
            command=self._on_clear,
            bg=BG_CARD,
            fg=FG_MUTED,
            font=("Segoe UI", 10),
            relief="flat",
            padx=12,
            pady=8,
            cursor="hand2",
        ).pack(side="left", padx=(0, 6))

        tk.Button(
            ctrl,
            text="🧹 Borrar Memoria",
            command=self._on_clear_memory,
            bg="#261b18",
            fg="#ffad66",
            font=("Segoe UI", 10, "bold"),
            relief="flat",
            padx=12,
            pady=8,
            cursor="hand2",
        ).pack(side="left")

        # Barra de estado inferior
        self.status_var = tk.StringVar(value=f"Cargando {self.cfg.llm_model} y voz '{self.current_tts_name}'...")
        self.vram_var = tk.StringVar(value="")
        bar = tk.Frame(self.root, bg="#080b11", padx=14, pady=5)
        bar.pack(fill="x")
        tk.Label(bar, textvariable=self.status_var, bg="#080b11", fg=ACCENT_GREEN, font=("Consolas", 9)).pack(side="left")
        tk.Label(bar, textvariable=self.vram_var, bg="#080b11", fg=FG_MUTED, font=("Consolas", 9)).pack(side="right")

        self._append_log(
            "meta",
            "1) Si no oyes sonido, selecciona arriba tu altavoz real (por ejemplo SAMSUNG) y pulsa '🔊 Probar Altavoz'.\n"
            "2) Escribe abajo cualquier mensaje y pulsa Enter: C.H.I.S.P.A. te responderá por escrito y hablando en voz alta.\n\n",
        )
        self._refresh_vram_label()

    def _append_log(self, tag: str, text: str) -> None:
        self.chat_box.configure(state="normal")
        self.chat_box.insert("end", text, tag)
        self.chat_box.see("end")
        self.chat_box.configure(state="disabled")

    def _refresh_vram_label(self) -> None:
        st = get_gpu_vram_status()
        if st.nvml_ok:
            self.vram_var.set(f"VRAM RTX: {st.used_mib}/{st.total_mib} MiB (libres: {st.free_mib} MiB)")

    def _get_or_load_tts(self, name: str) -> TTSBackend:
        if name not in self.tts_backends:
            backend = create_tts_backend(name, self.cfg)
            backend.warmup()
            self.tts_backends[name] = backend
        return self.tts_backends[name]

    def _start_background_warmup(self) -> None:
        def _worker() -> None:
            try:
                self.ui_queue.put(("status", "Cargando Enciclopedia Híbrida Cyberpunk (CPU, 0 MB VRAM)..."))
                if self.rag is None:
                    self.rag = get_hybrid_rag(self.cfg)
                if self.memory is None:
                    self.memory = get_episodic_memory(self.cfg)

                self.ui_queue.put(("status", f"Cargando LLM {self.cfg.llm_model} en Ollama..."))
                self.ollama.ensure_model_loaded()

                self.ui_queue.put(("status", f"Calentando motor de voz '{self.current_tts_name}'..."))
                self._get_or_load_tts(self.current_tts_name)

                self.models_ready = True
                wiki_msg = "Wiki Online ON" if self.companion_prefs.enable_online_wiki else "100% Offline"
                self.ui_queue.put(
                    (
                        "status",
                        f"LISTO ({self.rag.doc_count} fichas RAG · {wiki_msg}) — Escribe abajo y pulsa Enter.",
                    )
                )
                self.ui_queue.put(("vram", None))
            except Exception as exc:
                self.ui_queue.put(("status", f"ERROR en arranque: {exc}"))

        threading.Thread(target=_worker, name="chispa-warmup", daemon=True).start()

    def _on_spontaneous_changed(self, _evt: Any = None) -> None:
        pos = self.spont_combo.current()
        if 0 <= pos < len(SPONTANEOUS_OPTIONS):
            code, label = SPONTANEOUS_OPTIONS[pos]
            self.companion_prefs = self._save_companion_prefs(spontaneous_mode=code)
            self.status_var.set(f"Reacciones espontáneas ajustadas a: {label}")

    def _on_wiki_toggled(self) -> None:
        enabled = bool(self.wiki_var.get())
        self.companion_prefs = self._save_companion_prefs(enable_online_wiki=enabled)
        if enabled:
            self.status_var.set("Consulta online a Cyberpunk Wiki ACTIVADA por el usuario (con caché SQLite).")
        else:
            self.status_var.set("Modo 100 % offline activado: consulta online a Cyberpunk Wiki DESACTIVADA.")

    def _on_clear_memory(self) -> None:
        self.history.clear()
        if self.memory is None:
            self.memory = get_episodic_memory(self.cfg)
        self.memory.clear_episodic_memory()
        self.chat_box.configure(state="normal")
        self.chat_box.delete("1.0", "end")
        self.chat_box.configure(state="disabled")
        self._append_log(
            "meta",
            "🧹 Memoria episódica de partidas borrada (tu configuración de voz, altavoz y Wiki se mantiene intacta).\n\n",
        )
        self.status_var.set("Memoria episódica limpia — Voz y preferencias conservadas.")

    def _on_output_changed(self, _evt: Any = None) -> None:
        pos = self.out_combo.current()
        if 0 <= pos < len(self.out_devices):
            dev = self.out_devices[pos]
            self.selected_out_idx = dev.index
            self.player.set_device(dev.index)
            save_audio_prefs(output_name=dev.name)
            self.status_var.set(f"Altavoz cambiado a: {dev.name} ({dev.samplerate} Hz)")

    def _on_tts_changed(self, _evt: Any = None) -> None:
        pos = self.tts_combo.current()
        if 0 <= pos < len(TTS_OPTIONS):
            code = TTS_OPTIONS[pos][0]
            self.current_tts_name = code
            save_audio_prefs(tts_engine=code)
            if code not in self.tts_backends:
                self.status_var.set(f"Cargando motor de voz '{code}'...")

                def _load_tts() -> None:
                    try:
                        self._get_or_load_tts(code)
                        self.ui_queue.put(("status", f"Motor '{code}' listo para hablar."))
                        self.ui_queue.put(("vram", None))
                    except Exception as exc:
                        self.ui_queue.put(("status", f"Error cargando '{code}': {exc}"))

                threading.Thread(target=_load_tts, daemon=True).start()
            else:
                self.status_var.set(f"Motor activo: {code}")

    def _on_test_speaker(self) -> None:
        dev = next((d for d in self.out_devices if d.index == self.selected_out_idx), None)
        if dev is not None:
            save_audio_prefs(output_name=dev.name)
        self.player.play_voice_check(self.cfg.ref_wav_path)
        self.status_var.set(f"Probando voz de CHISPA en WASAPI: {dev.name if dev else 'predeterminado'}")

    def _on_interrupt(self) -> None:
        self.turn_cancel.set()
        self.player.interrupt()
        self.status_var.set("Audio silenciado.")

    def _on_clear(self) -> None:
        self.history.clear()
        self.chat_box.configure(state="normal")
        self.chat_box.delete("1.0", "end")
        self.chat_box.configure(state="disabled")
        self.status_var.set("Historial limpio.")

    def _on_send_text(self) -> None:
        txt = self.entry_var.get().strip()
        if not txt:
            return
        if not self.models_ready:
            self.status_var.set("Espera unos segundos a que terminen de cargar los modelos...")
            return
        self.entry_var.set("")
        self._launch_turn(txt)

    def _launch_turn(self, user_text: str) -> None:
        if self.busy_turn:
            self.turn_cancel.set()
            self.player.interrupt()
            time.sleep(0.05)

        self.busy_turn = True
        self.turn_cancel.clear()
        self._append_log("user", f"TÚ: {user_text}\n")
        self._append_log("chispa_lbl", "C.H.I.S.P.A.: ")

        def _worker() -> None:
            t0 = time.perf_counter()
            first_ttft: float | None = None
            first_audio: float | None = None
            parts: list[str] = []
            try:
                prefs_now = self.companion_prefs
                prev_q = ""
                for turn in reversed(self.history):
                    if turn.get("role") == "user":
                        prev_q = str(turn.get("content") or "")
                        break

                dossier_blocks: list[str] = []
                local_top = 0.0
                if self.rag is not None:
                    rag_docs = self.rag.retrieve(user_text, prev_query=prev_q, top_k=3)
                    local_top = self.rag.last_top_score
                    rag_txt = format_rag_dossier(rag_docs, max_total_chars=1280)
                    if rag_txt:
                        dossier_blocks.append(rag_txt)
                if self.memory is not None:
                    mem_txt = self.memory.build_memory_context("default", user_text)
                    if mem_txt:
                        dossier_blocks.append(mem_txt)
                if prefs_now.enable_online_wiki:
                    wiki_txt = lookup_wiki_online(
                        user_text,
                        local_top_score=local_top,
                        prefs=prefs_now,
                    )
                    if wiki_txt:
                        dossier_blocks.append(wiki_txt)
                dossier = "\n".join(dossier_blocks) if dossier_blocks else None

                backend = self._get_or_load_tts(self.current_tts_name)
                for clause in self.ollama.stream_clauses(
                    self.history,
                    user_text,
                    context_dossier=dossier,
                ):
                    if self.turn_cancel.is_set():
                        break
                    if first_ttft is None:
                        first_ttft = clause.ttft_ms
                    parts.append(clause.text)
                    self.ui_queue.put(("chunk_txt", clause.text + " "))

                    wav, _ = backend.synthesize(clause.text)
                    if self.turn_cancel.is_set():
                        break
                    if wav.size > 0:
                        if first_audio is None:
                            first_audio = (time.perf_counter() - t0) * 1000.0
                        self.player.enqueue(wav)

                reply = " ".join(parts).strip()
                if reply and not self.turn_cancel.is_set():
                    self.history.append({"role": "user", "content": user_text})
                    self.history.append({"role": "assistant", "content": reply})
                    if self.memory is not None:
                        self.memory.record_turn(
                            "default",
                            kind="chat",
                            user_text=user_text,
                            reply_text=reply,
                            allow_async_recap=True,
                        )

                meta = (
                    f"\n  [TTFT: {first_ttft or 0:.0f} ms | "
                    f"TTFA (1.ª voz): {first_audio or 0:.0f} ms | Motor: {self.current_tts_name}]\n\n"
                )
                self.ui_queue.put(("meta_line", meta))
                self.ui_queue.put(("status", "LISTO — Escribe abajo y pulsa Enter."))
                self.ui_queue.put(("vram", None))
            except Exception as exc:
                self.ui_queue.put(("meta_line", f"\n  [Error en turno: {exc}]\n\n"))
                self.ui_queue.put(("status", f"Error: {exc}"))
            finally:
                self.busy_turn = False

        threading.Thread(target=_worker, name="chispa-turn", daemon=True).start()

    def _poll_ui_queue(self) -> None:
        if self.closing:
            return
        while True:
            try:
                kind, payload = self.ui_queue.get_nowait()
            except queue.Empty:
                break
            if kind == "status":
                self.status_var.set(str(payload))
            elif kind == "vram":
                self._refresh_vram_label()
            elif kind == "chunk_txt":
                self._append_log("chispa_txt", str(payload))
            elif kind == "meta_line":
                self._append_log("meta", str(payload))

        self.root.after(40, self._poll_ui_queue)

    def _on_close(self) -> None:
        self.closing = True
        self.turn_cancel.set()
        self.player.close()
        self.ollama.close()
        self.root.destroy()

    def run(self) -> None:
        self.root.mainloop()


def run_self_test(cfg: ChispaServiceConfig) -> None:
    """Verifica dispositivos de salida, reproducción estéreo silenciosa y toda la interfaz Tkinter."""
    out_devs = list_output_devices()
    print("=== SELF-TEST CHAT CON VOZ (CHISPA v2.0) ===")
    print(f"Salidas detectadas ({len(out_devs)}):")
    for d in out_devs:
        mark = " [WINDOWS DEFAULT]" if d.is_default else ""
        print(f"  - [{d.index}] {d.name} ({d.hostapi_name}, {d.samplerate} Hz, {d.channels}ch){mark}")

    def_out = resolve_default_output_index(out_devs)
    player = WASAPIStreamPlayer(sample_rate=24000, device_index=def_out)
    player.enqueue(np.zeros(4800, dtype=np.float32))
    ok_play = player.wait_until_done(timeout=4.0)
    play_err = player._last_error
    player.close()
    print(f"Prueba salida estéreo adaptativa (device={def_out}): ok={ok_play}, error={play_err}")
    if not ok_play or play_err:
        raise RuntimeError(f"Fallo en salida de audio: {play_err}")

    with tempfile.TemporaryDirectory(prefix="chispa_gui_test_") as tmp_dir:
        tmp_root = Path(tmp_dir)
        test_prefs_path = tmp_root / "prefs.json"
        mem = EpisodicMemoryManager(
            state_dir=tmp_root / "state",
            log_dir=tmp_root / "logs",
            db_path=tmp_root / "ep.sqlite",
        )
        app = ChispaStudioApp(
            cfg,
            start_warmup=False,
            companion_prefs=CompanionPrefs(),
            memory=mem,
            prefs_saver=lambda **kw: save_companion_prefs(path=test_prefs_path, **kw),
        )
        app.root.withdraw()
        app.root.update_idletasks()
        assert app.wiki_var.get() is False, "La casilla de Wiki Online debe iniciarse desmarcada."
        app.wiki_var.set(True)
        app._on_wiki_toggled()
        assert app.companion_prefs.enable_online_wiki is True
        app._on_clear_memory()
        app._on_close()
    print("Tkinter ChispaStudioApp GUI check: OK")
    print("=== SELF-TEST COMPLETADO EN VERDE ===")


def main() -> None:
    parser = argparse.ArgumentParser(description="Chat de texto con respuesta hablada para C.H.I.S.P.A. v2.0")
    parser.add_argument("--self-test", action="store_true", help="Ejecuta autodiagnóstico de altavoces y Tkinter")
    parser.add_argument("--model", default=ChispaServiceConfig().llm_model, help="Modelo Ollama por defecto")
    parser.add_argument("--tts", default="f5_clone", choices=["f5_clone", "f5_clean", "kokoro_sergeant", "kokoro_onnx"])
    args = parser.parse_args()

    cfg = ChispaServiceConfig(llm_model=args.model, tts_engine=args.tts)
    if args.self_test:
        run_self_test(cfg)
        return

    app = ChispaStudioApp(cfg)
    app.run()


if __name__ == "__main__":
    main()
