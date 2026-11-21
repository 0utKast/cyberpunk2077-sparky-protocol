# -*- coding: utf-8 -*-
"""
sync_github_repo.py
===================
Populates/syncs the clean standalone public GitHub repository tree at:
  <workspace>/sparky_protocol/
Preserves `.git/` if already initialized, keeps all compiled `.archive`/`.ogg`/`.zip`/model
binaries out of Git tracking (they ship via GitHub Releases v2.0.0+), and updates README,
CREDITS, source trees, Local AI Bridges, and Nexus BBCode for release v2.0.0.

Usage:
  python mods/chispa_nc/tools/sync_github_repo.py
"""

from __future__ import annotations

import shutil
from pathlib import Path

TOOLS_DIR = Path(__file__).resolve().parent
SRC_MOD_DIR = TOOLS_DIR.parent
MODS_DIR = SRC_MOD_DIR.parent
WORKSPACE_ROOT = MODS_DIR.parent
EN_MOD_DIR = MODS_DIR / "chispa_nc_en"
MEDIA_PACK_DIR = WORKSPACE_ROOT / "NEXUS_MEDIA_PACK_SPARKY_PROTOCOL"
REPO_DIR = WORKSPACE_ROOT / "sparky_protocol"

RELEASE_VERSION = "2.0.0"
GITHUB_REPO_URL = "https://github.com/0utKast/cyberpunk2077-sparky-protocol"
YOUTUBE_V2_TRAILER_URL = "https://youtu.be/oh9oSNnJVh0"
YOUTUBE_TRAILER_URL = "https://youtu.be/9MXEEu3NCcc"
NEXUS_MOD_URL = "https://www.nexusmods.com/cyberpunk2077/mods/38982"


def _copy_clean_dir(src: Path, dst: Path) -> int:
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True, exist_ok=True)
    count = 0
    for f in sorted(src.rglob("*")):
        if f.is_file() and f.name != ".gitkeep":
            rel = f.relative_to(src)
            out = dst / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(f, out)
            count += 1
    return count


def _copy_clean_local_ai_service(src_dir: Path, dst_dir: Path, pkg_name: str) -> int:
    """Copies only pure text/code/config/lore_kb sources of a Local AI service (zero binaries/caches)."""
    if dst_dir.exists():
        shutil.rmtree(dst_dir)
    dst_dir.mkdir(parents=True, exist_ok=True)
    count = 0
    excluded_dirs = {".venv", "__pycache__", "audio_out", "models", "models_cache", "huggingface"}
    excluded_files = {"user_audio_prefs.json", "voice_override.json", ".env"}
    excluded_suffixes = {".pyc", ".pyo", ".sqlite", ".db", ".log", ".tmp", ".bak", ".wav", ".ogg", ".mp3", ".onnx", ".bin", ".safetensors"}

    for f in sorted(src_dir.iterdir()):
        if f.is_file() and f.name not in excluded_files and f.suffix.lower() in {".toml", ".bat", ".md", ".ico"}:
            shutil.copy2(f, dst_dir / f.name)
            count += 1

    pkg_src = src_dir / pkg_name
    for f in sorted(pkg_src.rglob("*")):
        if not f.is_file():
            continue
        if any(part in excluded_dirs for part in f.parts):
            continue
        if f.name in excluded_files or f.suffix.lower() in excluded_suffixes:
            continue
        out = dst_dir / f.relative_to(src_dir)
        out.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, out)
        count += 1
    return count


def _clean_repo_non_git(repo_dir: Path) -> None:
    repo_dir.mkdir(parents=True, exist_ok=True)
    for item in list(repo_dir.iterdir()):
        if item.name == ".git":
            continue
        if item.is_dir():
            shutil.rmtree(item)
        else:
            item.unlink()


def _write_gitignore(repo_dir: Path) -> None:
    content = """# Compiled / binary archives, audio binaries, AI weights, & distribution ZIPs (published in GitHub Releases)
*.archive
*.ogg
*.wav
*.mp3
*.zip
*.onnx
*.bin
*.sqlite
*.db
*.safetensors

# Local AI virtual environments & runtime outputs
.venv/
audio_out/
models_cache/

# Python / OS / Env artifacts
__pycache__/
*.pyc
*.pyo
.env
*.tmp
.DS_Store
Thumbs.db
"""
    (repo_dir / ".gitignore").write_text(content, encoding="utf-8")


def _write_license(repo_dir: Path) -> None:
    content = f"""MIT License & 100% Open Modding Permissions

Copyright (c) 2026 OutKast (0utKast)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software, CR2W entity/journal templates, ArchiveXL manifests, TweakXL
records, redscript source modules (.reds), Cyber Engine Tweaks Lua scripts,
Audioware manifests, localization generators, Local AI bridge Python services,
and associated documentation files (the "Software"), to deal in the Software
without restriction, including without limitation the rights to use, copy, modify,
merge, publish, distribute, sublicense, and/or sell copies of the Software, and
to permit persons to whom the Software is furnished to do so, subject to the
following conditions:

1. Attribution: Explicit credit to the original author (0utKast) and a link to
   the original project repository ({GITHUB_REPO_URL})
   shall be included in all copies, derivative mods, translations, or substantial
   portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
    (repo_dir / "LICENSE").write_text(content, encoding="utf-8")


def _write_credits(repo_dir: Path) -> None:
    content = f"""# Credits, Licenses & Open Modding Policy / Créditos, Licencias y Política de Modding Abierto

## 1. Open Modding Commitment / Compromiso de Modding Abierto (100% Open Permissions)
**SPARKY Protocol — Night City Survival Guide / Protocolo C.H.I.S.P.A. v{RELEASE_VERSION}** (both the **100% Pure English Standalone Edition** and the **Spanish / Bilingual Edition**, including their **100% Local AI Bridges**) is released under the **MIT License** with **100% Open Modding Permissions**:
- **Modification, Asset Use, Translation & Redistribution:** Explicitly **OPEN**. Any member of the community may inspect, study, modify, translate, port, integrate, or redistribute this mod, its Python CR2W/localization/audio builders, redscript modules, TweakXL records, CET scripts, and Local AI Python services freely, provided credit to the original author (`0utKast`) is included.
- **100% Base Game Compatible (`2.x`, Zero Paid DLC Required):** Built strictly using vanilla `Cyberpunk 2077` 2.x assets plus open-source REDengine 4 extender frameworks. No *Phantom Liberty* (`ep1`) assets or paid third-party asset packs are required.
- **100% Standalone (Zero Third-Party Content Dependencies):** Requires only standard open-source core frameworks (`RED4ext`, `ArchiveXL`, `TweakXL`, `Codeware`, `redscript`, `Cyber Engine Tweaks`, plus `AudioXL` or `Audioware`), downloaded cleanly from their original authors without bundling their `.dll` binaries inside our mod archives.

---

## 2. Full Attribution Table / Tabla Completa de Reconocimiento y Autoría

| Component / Componente | Author / Autor Original | License / Permisos | Link / Referencia |
| :--- | :--- | :--- | :--- |
| **SPARKY / C.H.I.S.P.A. Modular Engine, Season 1 (Ep. 0–5), v2.0 Local AI Bridge & 162-Card Lore KB** | **OutKast (`0utKast`)** | **MIT License (100% Open Permissions)** | [GitHub]({GITHUB_REPO_URL}) · [Nexus Mods #38982]({NEXUS_MOD_URL}) |
| **WolvenKit & WolvenKit CLI** | WolvenKit Team & REDModding Community | Open Source | https://github.com/WolvenKit/WolvenKit |
| **RED4ext** | WopsS & Contributors | Open Source | https://github.com/WopsS/RED4ext |
| **ArchiveXL / TweakXL / Codeware** | psiberx | MIT / Open Source | https://github.com/psiberx |
| **redscript & redscript-cli** | jac3km4 | Open Source | https://github.com/jac3km4/redscript |
| **Cyber Engine Tweaks (CET)** | yamashi, maximegmd & Contributors | MIT / Open Source | https://github.com/maximegmd/CyberEngineTweaks |
| **AudioXL** | DigitalVixen | Open Source | https://www.nexusmods.com/cyberpunk2077/mods/33442 |
| **Audioware** | cyb3rpsych0s1s / Roms1383 | Open Source | https://github.com/cyb3rpsych0s1s/audioware |
| **Ollama Local LLM Runtime** | Ollama Team | MIT License | https://github.com/ollama/ollama |
| **F5-TTS & F5-Spanish Voice Synthesis** | SWivid & jpgallegoar | MIT / Apache-2.0 | https://github.com/SWivid/F5-TTS |
| **Kokoro-82M / kokoro-onnx** | hexgrad & thewh1teagle | Apache-2.0 / MIT | https://github.com/thewh1teagle/kokoro-onnx |
| **ONNX Runtime & Sentence-Transformers** | Microsoft / UKPLab (`MiniLM-L12-v2`) | MIT / Apache-2.0 | https://github.com/microsoft/onnxruntime |
| **Studio Voice Acting (`144` EN + `144` ES), 4K Showcase Score & Trailer SFX** | **Synthesized & DSP-Mastered by `0utKast`** via ElevenLabs & FFmpeg | **100% Open Redistribution in Mod** | https://elevenlabs.io/ |
| **Base Game Engine & Universe** | CD Projekt RED (*Cyberpunk 2077* 2.x Base Game) | Official Base Game | https://www.cyberpunk.net/ |
"""
    (repo_dir / "CREDITS.md").write_text(content, encoding="utf-8")


def _write_readme(repo_dir: Path) -> None:
    content = f"""# Cyberpunk 2077 — SPARKY Protocol / Protocolo C.H.I.S.P.A. (`v{RELEASE_VERSION}`)
### *Night City Survival Guide* — **v2.0 Live Local AI Companion** (`Ollama` + `F5-TTS`/`Kokoro-82M`, `162`-Card Hybrid RAG, Isolated Per-Save Memory, `[Y]`/`[U]` HUD Telemetry) + **Complete Season 1 Voiced Campaign** (`Ep. 0–5`, `7` Iconic Weapons, `3` RPG Endings)

[![License: MIT & Open Permissions](https://img.shields.io/badge/License-MIT%20%28100%25%20Open%20Permissions%29-brightgreen.svg)](LICENSE)
[![Nexus Mods #38982](https://img.shields.io/badge/Nexus%20Mods-%2338982-da8e35.svg)]({NEXUS_MOD_URL})
[![v2.0 4K Live AI Showcase](https://img.shields.io/badge/YouTube-v2.0%204K%20Live%20AI%20Showcase-ff0000.svg)]({YOUTUBE_V2_TRAILER_URL})
[![Season 1 Trailer](https://img.shields.io/badge/YouTube-Season%201%20Trailer-cc0000.svg)]({YOUTUBE_TRAILER_URL})
[![Release v{RELEASE_VERSION}](https://img.shields.io/badge/Release-v{RELEASE_VERSION}%20Live%20AI%20%2B%20Season%201-fcee0a.svg)]({GITHUB_REPO_URL}/releases/tag/v{RELEASE_VERSION})
[![Cyberpunk 2077 2.x](https://img.shields.io/badge/Cyberpunk%202077-2.x%20Base%20Game%20%2B%20AudioXL-00f0ff.svg)](#universal-compatibility)

![SPARKY Protocol Header Banner](media/00_HEADER_NEXUS_1920x1080_EN.jpg)

> **🌍 Navigation & Direct Downloads / Navegación y Descarga Directa (`v{RELEASE_VERSION}`):**
> - 🧩 **[Nexus Mods Page (`cyberpunk2077/mods/38982`)]({NEXUS_MOD_URL})**
> - 🎬 **[Watch v2.0.0 4K Live AI Showcase on YouTube (`youtu.be/oh9oSNnJVh0`)]({YOUTUBE_V2_TRAILER_URL})** · **[Season 1 Trailer (`youtu.be/9MXEEu3NCcc`)]({YOUTUBE_TRAILER_URL})**
> - 📦 **[Download Release `v{RELEASE_VERSION}` on GitHub]({GITHUB_REPO_URL}/releases/tag/v{RELEASE_VERSION})**
>   - 🇺🇸 **`SparkyProtocol_EN_v{RELEASE_VERSION}.zip`** — *Main Game Mod: 100% Pure English Standalone Edition*
>   - 🇪🇸 **`ChispaNC_v{RELEASE_VERSION}.zip`** — *Mod Principal: Edición Española / Bilingüe (ES & EN)*
>   - 🤖 **`SPARKY_v{RELEASE_VERSION}_LocalAI_Service_EN.zip`** — *Optional Live Local AI Bridge (EN: Ollama + F5-TTS/Kokoro + 162-card RAG)*
>   - 🤖 **`CHISPA_v{RELEASE_VERSION}_LocalAI_Service_ES.zip`** — *Puente Opcional de IA Local en Vivo (ES: Ollama + F5-Spanish/Kokoro + RAG 162 fichas)*
>   - 🎙️ Optional Voice Packs: `SparkyProtocol_EN_FemaleVoicePack_v2.0.0.zip`, `Chispa_LocalAI_FemaleVoicePack_ES_v2.0.0.zip`, `ChispaNC_ClassicCampaignVoices_v2.0.0.zip`
> - 🇺🇸 **[English Documentation (v2.0 Local AI, Ep. 0–5 Campaign & Install)](#english-documentation)**
> - 🇪🇸 **[Documentación en Español (IA Local v2.0, Campaña Ep. 0–5 e Instalación)](#documentación-en-español)**
> - ⚖️ **[Credits & Open Modding Permissions (`CREDITS.md`)](CREDITS.md)** · 📜 **[MIT License (`LICENSE`)](LICENSE)**

---

<a name="english-documentation"></a>
# 🇺🇸 English Documentation

## 1. Overview
**SPARKY Protocol — Night City Survival Guide (`v{RELEASE_VERSION}`)** (*Protocolo C.H.I.S.P.A.*) pairs a **6-episode voiced Season 1 campaign (`Ep. 0–5`)** with a **100% local, zero-cloud real-time AI companion (`S.P.A.R.K.Y.`)** integrated natively into V's Kiroshi HUD. Fully compatible with **Cyberpunk 2077 `2.x` Base Game** (no *Phantom Liberty* DLC required).

---

## 2. What's New in `v{RELEASE_VERSION}` — Live Local AI Companion (`[Y]` / `[U]`)
- **Native HUD Kiroshi Neural Link Bar (`[Y]`) & Instant Tactical Scan (`[U]`):** Tap `[Y]` anytime in free roam or stealth to type freely without freezing the game (`[Tab]` inside the bar triggers an instant read; `[Up]` recalls your last prompt); tap `[U]` directly in gameplay to trigger a spoken breakdown of your district, active mission, scanned hostile, weapon, HP, and NCPD heat. Cleanly toggleable/rebindable via CET Bindings.
- **100% Offline Ollama LLM + Clause-by-Clause Streaming Voice:** Runs `gemma3:12b` (default with automatic NVML VRAM balancing on `<=16 GB` GPUs alongside 4K gameplay, or lighter `gemma3:4b`) streamed phrase-by-phrase into low-latency `F5-TTS` voice cloning (GPU) or zero-VRAM CPU `Kokoro-82M` sergeant blend over your chosen WASAPI output.
- **162-Card Offline Hybrid Lore RAG (`0 MB` Extra VRAM, `<5 ms` CPU Search):** Combines live Kiroshi telemetry pinning + `SQLite FTS5` + CPU ONNX dense vectors (`paraphrase-multilingual-MiniLM-L12-v2`) across **162 modular lore cards** (with custom JSON extensibility, strict 2022 vs. 2077 memory separation, and automatic Act 1 spoiler gating before *The Heist*).
- **Isolated Per-Playthrough Episodic Memory (`chispa_mem_uid`):** Every playthrough stamps a persistent `chispa_mem_uid` quest fact plus `playthrough_sec` timestamps so different characters/saves never leak history, loading earlier saves hides future timeline events, read Shards index automatically into long-term SQLite FTS5 memory, and an async background recap updates a compressed 1st-person run journal.
- **Spontaneous Reactions, Immersion Guards & Opt-In Wiki:** Toggle live in **SPARKY Studio** between `Tactical` (`<=28%` HP, NCPD/MaxTac 5★, boss/cyberpsycho scans, long firefights, district arrivals, quest progress), `Active Companion` (adds Shard comments & ambient road banter), or `Off`. Automatically pauses/mutes over vanilla calls, cutscenes, dialogue hubs, menus, and Shard readers. Online Fandom Wiki lookup is strictly **opt-in (disabled by default)**.
- **Standalone One-Click Installer & Auto Steam / GOG / Epic Detection:** Extracts anywhere (even outside the game folder), automatically detects Steam, GOG, and Epic Games installations (or `game_path.txt` / `--ipc-dir`), and sets up dependencies via `install_sparky_ai.bat`.

---

## 3. Season 1 Campaign (`Episodes 0–5`) & Technical Features
| Episode | Title & Location | Tactical Mechanics, Rewards & Lore |
| :--- | :--- | :--- |
| **Ep. 0** | *Not Your Office Paperclip* (`Megabuilding H10`, Watson) | Rescue S.P.A.R.K.Y. v0.98b, scan targets with Kiroshi `[TAB]`, overload the unstable industrial capacitor (`[F]`), claim `+1,500 €$`, Iconic pistol ***Executive Courtesy*** (`Lexington`), and unlock portable lore on Richard Night & Megabuildings. |
| **Ep. 1** | *Ghosts in the Camera* (`Kabuki Creek Promenade`, Watson) | Positioned cleanly off the roadway along the pedestrian walkway. Receive starter `Ping`, hijack chained cameras (`CAM-01 -> CAM-02`), detonate the Scav Entropy server or overload the red RABIDS relay bank (`[F]`), claim Sector #01 (`+2,200 €$` + adaptive quickhacks + Iconic SMG ***Phantom Frequency***), and explore Bartmoss, DataKrash & the Blackwall. |
| **Ep. 2** | *More Chrome Than Meat* (`Northside Docks`, Watson) | Subvert or rip off Maelstrom's perimeter security turret, purge the pressurized CHOOH2 regulator (`[F]`), recover Sector #02 (`+2,800 €$` + adaptive Reboot Optics + Iconic Tech rifle ***Piercing Clause*** `M-179e Achilles`), and discuss Maelstrom, Cyberpsychosis, & MaxTac. |
| **Ep. 3** | *Bullets That Bend Corners* (`South Quay`, Watson) | Live `HasSmartLink` optical bridge, Tyger Claws smart-deflecting ink (`OnSmartBulletDeflectedEvent`), invert the Arasaka IFF Jammer Pylon (`[F]`), and recover Sector #03 (`+3,400 €$` + adaptive Contagion + Iconic Smart SMG ***Executive Curve*** `Shingen`). |
| **Ep. 4** | *Honor, Scrap & Cardboard Patriots* (`Arroyo`, Heywood) | Unlocks automatically once Watson's police lockdown lifts (`HasLiftedWatsonLockdown`). Activate `CanSeeRicochetVisuals` trajectory bridge (`GetNumRicochetBounces()` telemetry), spike the ballistic relay into 6th Street's NUSA depot (`[F]`), and claim Sector #04 (`+4,200 €$` + Iconic ***Street Geometry*** `Masamune`). |
| **Ep. 5** | *Beyond the Blackwall* (`Coastview`, Pacifica) | Storm the Voodoo Boys cryo-node with chained cams, dual Smart + Ricochet bridges, and NetWatch containment purge (`[F]`). Claim Master Sector #05 (`+5,000 €$` + adaptive System Collapse + Iconic Tech pistol ***Firewall '22*** `Kenshin`), then choose among **3 Quest-Yellow RPG Endings** (*Autonomous Partner v1.0*, *N54 Data Leak* `+4,500 €$` + Cyberware Malfunction, or *Gunsmith Protocol* forging Iconic revolver ***Sergeant's Last Word*** `Overture`). |

### Core Engineering Highlights Included (`v1.5.1` – `v1.6.1` + `v{RELEASE_VERSION}`)
- **Dual Optional Audio Backend (`AudioXL` + `Audioware`):** Works seamlessly on Windows, Linux, Proton, and Steam Deck via Redscript `@if(ModuleExists(...))` without duplicating `.ogg` files (and compiles cleanly in subtitle-only fallback mode if neither plugin is installed).
- **Level-2 & Tier-1 Cyberdeck Compatibility + Hardware RAM Bridge:** 10 adaptive quickhack tiers, clean non-program quest hardware tooltips (`+8` base RAM + `+3` per extracted Memory Sector up to `+23` bonus RAM), idempotent Level/Street Cred/Skill XP rewards, pause/menu subtitle sync, and 2-line UTF-8 pagination across 19 locales.
- **Persistent Top-Left Kiroshi Holo-Feed (`440×440`) & Zero Conflict Guarantees:** Never occupies Cyberware/Cosmetic slots, respects Prologue/Character Creation (`GameplayTier.Tier1_FullGameplay`), and leaves `[F]` world interactions responsive mid-combat.

---

## 4. In-Game Screenshot Showcase (`1920×1080`)

| Incoming Encrypted Kiroshi Holocall (Ep. 0) | Kiroshi Optical Hazard Scanning (H10 Backlot) |
| :---: | :---: |
| ![Incoming Holocall](media/01_Ep00_Incoming_Kiroshi_Holocall.jpg) | ![H10 Hazard Scan](media/02_Ep00_H10_Kiroshi_Hazard_Scan.jpg) |
| **Chained Surveillance Camera Takeover (Ep. 1)** | **Deploying Ping Daemon Through Subnet (Ep. 1)** |
| ![Camera Hijack](media/07_Ep01_Chained_Surveillance_Camera_Hijack.jpg) | ![Ping Subnet](media/08_Ep01_Ping_Daemon_Subnet_Trace.jpg) |
| **CHOOH2 Regulator Purge & Turret Override (Ep. 2)** | **Arasaka IFF Jammer Detonation (Ep. 3)** |
| ![Northside CHOOH2 Purge](media/11_Ep02_Northside_CHOOH2_Regulator_Purge.jpg) | ![Arasaka IFF Fireball](media/14_Ep03_Arasaka_IFF_Antenna_Fireball.jpg) |
| **Pacifica Blackwall Containment Purge (Ep. 5)** | **Three Real Quest-Yellow RPG Endings (Finale)** |
| ![Pacifica Cryo Purge](media/19_Ep05_Pacifica_Blackwall_Cryo_Purge.jpg) | ![Three RPG Endings](media/20_Ep05_Season_Finale_Three_RPG_Endings.jpg) |

---

<a name="universal-compatibility"></a>
## 5. Compatibility, Requirements & Two-Step Installation
- **Game Version:** Cyberpunk 2077 `2.x` (**100% Base Game Compatible** — *Phantom Liberty* is **NOT** required).
- **Required Open-Source Frameworks** *(install separately; never bundled inside mod zips)*:
  [RED4ext](https://github.com/WopsS/RED4ext), [ArchiveXL](https://github.com/psiberx/cp2077-archive-xl), [TweakXL](https://github.com/psiberx/cp2077-tweak-xl), [Codeware](https://github.com/psiberx/cp2077-codeware), [redscript](https://github.com/jac3km4/redscript), [Cyber Engine Tweaks](https://github.com/maximegmd/CyberEngineTweaks), plus [AudioXL](https://www.nexusmods.com/cyberpunk2077/mods/33442) *(recommended Linux/Steam Deck & Windows)* OR [Audioware](https://github.com/cyb3rpsych0s1s/audioware) *(Windows)*.
- **Step 1 — Install ONE Main Game Edition:**
  1. Download **one** Main ZIP from [Nexus Mods #38982]({NEXUS_MOD_URL}) or [GitHub Releases (`v{RELEASE_VERSION}`)]({GITHUB_REPO_URL}/releases/tag/v{RELEASE_VERSION}): **`SparkyProtocol_EN_v{RELEASE_VERSION}.zip`** *(English)* OR **`ChispaNC_v{RELEASE_VERSION}.zip`** *(Spanish/Bilingual)*.
  2. Install via **Vortex** / **Mod Organizer 2** or extract into your `Cyberpunk 2077` root folder. *(Never install both language editions together.)*
- **Step 2 — Optional Live Local AI Bridge (`v{RELEASE_VERSION}` `[Y]` / `[U]` Features):**
  1. Install [Python 3.11 or 3.12](https://www.python.org/downloads/) and [Ollama](https://ollama.com/download).
  2. Download the matching Local AI ZIP (`SPARKY_v{RELEASE_VERSION}_LocalAI_Service_EN.zip` or `CHISPA_v{RELEASE_VERSION}_LocalAI_Service_ES.zip`), extract anywhere on your PC (auto-detects Steam/GOG/Epic), run **`install_sparky_ai.bat`** / **`instalar_chispa_ia.bat`**, configure audio/reactions in Studio, and leave **`start_sparky_service.bat`** / **`iniciar_servicio_chispa.bat`** open while playing.

---

<a name="architecture--pipeline"></a>
## 6. Repository Architecture & Reproducible Build Pipeline

```mermaid
flowchart LR
    subgraph GAME["1. In-Game Layer (src/)"]
        RS["redscript Core & Ep. 0–5\nChispaEngine / LiveCompanion / Telemetry"]
        CET["CET HUD Bar + Atomic IPC\n[Y] Neural Input · [U] Tactical Read"]
        RES["WolvenKit CR2W + ArchiveXL + TweakXL\nAudioXL / Audioware Dual Voice Backend"]
    end

    subgraph LOCALAI["2. 100% Offline Local AI Bridge (sparky_local_service*/)"]
        RAG["162-Card Hybrid Lore RAG\nCPU ONNX Vectors + SQLite FTS5 (<5 ms)"]
        MEM["Isolated Per-Save Memory\nchispa_mem_uid + Async Recap"]
        LLM["Ollama Streaming + F5-TTS / Kokoro-82M\nClause-by-Clause WASAPI Voice Output"]
    end

    CET <-->|"Atomic JSON IPC (state.json / inbox.json)"| LOCALAI
    GAME -->|"WolvenKit.CLI RDAR + redscript-cli QA"| PKG["GitHub & Nexus Releases v{RELEASE_VERSION}"]
```

---

<a name="documentación-en-español"></a>
# 🇪🇸 Documentación en Español

![Cabecera Protocolo CHISPA ES](media/00_HEADER_NEXUS_1920x1080_ES.jpg)

## 1. Descripción General (`v{RELEASE_VERSION}`)
**Protocolo C.H.I.S.P.A. — Guía Callejera de Night City (`v{RELEASE_VERSION}`)** (*SPARKY Protocol*) combina una **campaña narrativa doblada de 6 misiones (`Ep. 0–5`)** con un **compañero de IA local en tiempo real 100 % offline** (`[Y]` barra neural HUD + `[U]` parte táctico hablado), todo compatible al 100 % con el **Juego Base de Cyberpunk 2077 (`2.x`)** sin necesitar *Phantom Liberty*.

## 2. Novedades de la `v{RELEASE_VERSION}` (Puente de IA Local en Directo)
- **Barra Neural Kiroshi (`[Y]`) y Réplica Táctica Instantánea (`[U]`):** Escribe cualquier pregunta en partida sin congelar el juego ni bloquear combates, o pulsa `[U]` para recibir análisis vivo por voz de tu distrito, misión, blanco escaneado, salud, arma y nivel NCPD.
- **Ollama 100 % Local + Voz Streaming (`F5-Spanish` / `Kokoro-82M`):** Usa `gemma3:12b` por defecto (o `gemma3:4b` en GPUs ligeras) locutando frase a frase con clonado `F5-Spanish` en GPU o mezcla `Kokoro` por CPU (`0 MB` VRAM extra).
- **Enciclopedia Híbrida Offline de `162` Fichas (`<5 ms` en CPU):** Anclaje Kiroshi + `SQLite FTS5` + vectores semánticos ONNX multilingües, perspectiva temporal `2022` vs. `2077` y escudo anti-spoilers automático en el Acto 1.
- **Memoria Episódica Aislada por Partida (`chispa_mem_uid`), Reacciones Espontáneas y Wiki Opcional:** Aíslas cada personaje y partida (`playthrough_sec`), eliges modo `Tácticas` / `Compañero Activo` / `Desactivadas` desde **Chispa Studio** y decides si autorizas consultas opcionales a la Wiki (desactivado por defecto).
- **Instalador en Un Clic y Detección Automática Steam / GOG / Epic:** Descomprime `CHISPA_v{RELEASE_VERSION}_LocalAI_Service_ES.zip` en cualquier ruta y ejecuta `instalar_chispa_ia.bat`.

## 3. Campaña Temporada 1 (`Ep. 0–5`) e Instalación Rápida (Español)
1. **Mod Principal (elige solo uno):** Descarga **`ChispaNC_v{RELEASE_VERSION}.zip`** *(Español/Bilingüe)* o **`SparkyProtocol_EN_v{RELEASE_VERSION}.zip`** *(Inglés)* desde **[Nexus Mods #38982]({NEXUS_MOD_URL})** o **[GitHub Releases (`v{RELEASE_VERSION}`)]({GITHUB_REPO_URL}/releases/tag/v{RELEASE_VERSION})**.
2. Instala los frameworks base (*RED4ext*, *ArchiveXL*, *TweakXL*, *Codeware*, *redscript*, *Cyber Engine Tweaks* y *AudioXL* o *Audioware*) y extrae el `.zip` en la raíz de **Cyberpunk 2077** (o mediante Vortex / MO2).
3. **(Opcional para IA Local v2.0):** Instala Python 3.11/3.12 + Ollama, descomprime **`CHISPA_v{RELEASE_VERSION}_LocalAI_Service_ES.zip`** donde quieras, ejecuta `instalar_chispa_ia.bat`, ajusta tu audio en `probar_chispa_es.bat` y deja abierto `iniciar_servicio_chispa.bat` al jugar.
"""
    (repo_dir / "README.md").write_text(content, encoding="utf-8")


def main() -> None:
    _clean_repo_non_git(REPO_DIR)
    _write_gitignore(REPO_DIR)
    _write_license(REPO_DIR)
    _write_credits(REPO_DIR)
    _write_readme(REPO_DIR)

    # Media headers + 8 curated 1920x1080 screenshots
    media_dst = REPO_DIR / "media"
    media_dst.mkdir(parents=True, exist_ok=True)
    headers = (
        MEDIA_PACK_DIR / "01_CABECERAS_MOD_NEXUS" / "00_HEADER_NEXUS_1920x1080_EN.jpg",
        MEDIA_PACK_DIR / "01_CABECERAS_MOD_NEXUS" / "00_HEADER_NEXUS_1920x1080_ES.jpg",
    )
    showcase = (
        "01_Ep00_Incoming_Kiroshi_Holocall.jpg",
        "02_Ep00_H10_Kiroshi_Hazard_Scan.jpg",
        "07_Ep01_Chained_Surveillance_Camera_Hijack.jpg",
        "08_Ep01_Ping_Daemon_Subnet_Trace.jpg",
        "11_Ep02_Northside_CHOOH2_Regulator_Purge.jpg",
        "14_Ep03_Arasaka_IFF_Antenna_Fireball.jpg",
        "19_Ep05_Pacifica_Blackwall_Cryo_Purge.jpg",
        "20_Ep05_Season_Finale_Three_RPG_Endings.jpg",
    )
    copied_media = 0
    for h in headers:
        shutil.copy2(h, media_dst / h.name)
        copied_media += 1
    for sc in showcase:
        shutil.copy2(MEDIA_PACK_DIR / "02_20_CAPTURAS_GALERIA_1920x1080" / sc, media_dst / sc)
        copied_media += 1

    # Source scripts, data, CR2W templates & manifests (excluding heavy .ogg/.archive/.zip binaries)
    src_dst = REPO_DIR / "src"
    rs_count = _copy_clean_dir(SRC_MOD_DIR / "files" / "r6" / "scripts" / "ChispaNC", src_dst / "redscript")
    rs_en_count = _copy_clean_dir(EN_MOD_DIR / "files" / "r6" / "scripts" / "SparkyProtocol_EN", src_dst / "redscript_en")
    cr2w_count = _copy_clean_dir(SRC_MOD_DIR / "wolvenkit_src" / "archive" / "chispa_nc", src_dst / "wolvenkit_cr2w")
    tw_count = _copy_clean_dir(SRC_MOD_DIR / "files" / "r6" / "tweaks" / "ChispaNC", src_dst / "tweaks")

    (src_dst / "archivexl").mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC_MOD_DIR / "files" / "archive" / "pc" / "mod" / "ChispaNC.xl", src_dst / "archivexl" / "ChispaNC.xl")
    shutil.copy2(EN_MOD_DIR / "files" / "archive" / "pc" / "mod" / "SparkyProtocol_EN.xl", src_dst / "archivexl" / "SparkyProtocol_EN.xl")

    (src_dst / "audioware").mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC_MOD_DIR / "files" / "r6" / "audioware" / "ChispaNC" / "ChispaNC.yaml", src_dst / "audioware" / "ChispaNC.yaml")
    shutil.copy2(EN_MOD_DIR / "files" / "r6" / "audioware" / "SparkyProtocol_EN" / "SparkyProtocol_EN.yaml", src_dst / "audioware" / "SparkyProtocol_EN.yaml")

    (src_dst / "cet").mkdir(parents=True, exist_ok=True)
    es_cet = SRC_MOD_DIR / "files" / "bin" / "x64" / "plugins" / "cyber_engine_tweaks" / "mods" / "ChispaNC"
    en_cet = EN_MOD_DIR / "files" / "bin" / "x64" / "plugins" / "cyber_engine_tweaks" / "mods" / "SparkyProtocol_EN"
    shutil.copy2(es_cet / "init.lua", src_dst / "cet" / "chispa_nc_init.lua")
    shutil.copy2(es_cet / "live_ipc.lua", src_dst / "cet" / "chispa_nc_live_ipc.lua")
    shutil.copy2(en_cet / "init.lua", src_dst / "cet" / "SparkyProtocol_EN_init.lua")
    shutil.copy2(en_cet / "live_ipc.lua", src_dst / "cet" / "SparkyProtocol_EN_live_ipc.lua")

    (src_dst / "tools").mkdir(parents=True, exist_ok=True)
    for tname in (
        "generate_entities.py",
        "generate_journal_and_loc.py",
        "generate_chispa_audio.py",
        "build_english_edition.py",
        "build_local_ai_zips.py",
        "sync_github_repo.py",
        "audio_durations.json",
    ):
        shutil.copy2(TOOLS_DIR / tname, src_dst / "tools" / tname)

    shutil.copy2(SRC_MOD_DIR / "mod.json", src_dst / "mod_chispa_nc.json")
    shutil.copy2(EN_MOD_DIR / "mod.json", src_dst / "mod_sparky_protocol_en.json")

    # Clean Local AI Bridges source trees (no .venv / weights / audio / caches)
    ai_en_count = _copy_clean_local_ai_service(WORKSPACE_ROOT / "sparky_local_service_en", REPO_DIR / "sparky_local_service_en", "sparky_rt")
    ai_es_count = _copy_clean_local_ai_service(WORKSPACE_ROOT / "sparky_local_service", REPO_DIR / "sparky_local_service", "chispa_rt")

    # Architecture blueprint & Nexus release documentation
    arch_doc = WORKSPACE_ROOT / "docs" / "PLAN_ARQUITECTURA_CHISPA_V2_LOCAL_REALTIME.md"
    if arch_doc.is_file():
        (REPO_DIR / "docs").mkdir(parents=True, exist_ok=True)
        shutil.copy2(arch_doc, REPO_DIR / "docs" / arch_doc.name)

    rel_dst = REPO_DIR / "release_nexus"
    rel_dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC_MOD_DIR / "docs" / "NEXUS_DESCRIPTION_BBCODE.txt", rel_dst / "NEXUS_DESCRIPTION_BBCODE_EN.txt")
    shutil.copy2(SRC_MOD_DIR / "docs" / "NEXUS_RELEASE_V2_0_0_SUMMARY.txt", rel_dst / "NEXUS_RELEASE_V2_0_0_SUMMARY.txt")
    if (SRC_MOD_DIR / "docs" / "NEXUS_DESCRIPTION_BBCODE_ES.txt").is_file():
        shutil.copy2(SRC_MOD_DIR / "docs" / "NEXUS_DESCRIPTION_BBCODE_ES.txt", rel_dst / "NEXUS_DESCRIPTION_BBCODE_ES.txt")
    shutil.copy2(SRC_MOD_DIR / "docs" / "README_EN.txt", rel_dst / "README_EN.txt")
    shutil.copy2(SRC_MOD_DIR / "docs" / "LEEME_ES.txt", rel_dst / "LEEME_ES.txt")

    print(
        f"[SYNC OK] {REPO_DIR} | media={copied_media}, reds={rs_count}+{rs_en_count}, tweaks={tw_count}, "
        f"cr2w_json={cr2w_count}, local_ai={ai_en_count}+{ai_es_count}"
    )


if __name__ == "__main__":
    main()
