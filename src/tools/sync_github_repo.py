# -*- coding: utf-8 -*-
"""
sync_github_repo.py
===================
Populates/syncs the clean standalone public GitHub repository tree at:
  <workspace>/sparky_protocol/
Preserves `.git/` if already initialized, keeps all compiled `.archive`/`.ogg`/`.zip`
binaries out of Git tracking (they ship via GitHub Releases v1.4.0+), and mirrors
the documentation & media layout used in 0utKast/fallout4-project-astro-cosmos.

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

GITHUB_REPO_URL = "https://github.com/0utKast/cyberpunk2077-sparky-protocol"
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
    content = """# Compiled / binary archives, audio binaries, & distribution ZIPs (published in GitHub Releases)
*.archive
*.ogg
*.wav
*.mp3
*.zip

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
Audioware manifests, localization generators, and associated documentation files
(the "Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom
the Software is furnished to do so, subject to the following conditions:

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
**SPARKY Protocol — Night City Survival Guide / Protocolo C.H.I.S.P.A.** (both the **100% Pure English Standalone Edition** and the **Spanish / Bilingual Edition**) is released under the **MIT License** with **100% Open Modding Permissions**:
- **Modification, Asset Use, Translation & Redistribution:** Explicitly **OPEN**. Any member of the community may inspect, study, modify, translate, port, integrate, or redistribute this mod, its Python CR2W/localization/audio builders, redscript modules, TweakXL records, and CET scripts freely, provided credit to the original author (`0utKast`) is included.
- **100% Base Game Compatible (`2.x`, Zero Paid DLC Required):** Built strictly using vanilla `Cyberpunk 2077` 2.x assets plus open-source REDengine 4 extender frameworks. No *Phantom Liberty* (`ep1`) assets or paid third-party asset packs are required.
- **100% Standalone (Zero Third-Party Content Dependencies):** Requires only standard open-source core frameworks (`RED4ext`, `ArchiveXL`, `TweakXL`, `Codeware`, `redscript`, `Audioware`, and `Cyber Engine Tweaks`), downloaded cleanly from their original authors without bundling their `.dll` binaries inside our mod archives.

---

## 2. Full Attribution Table / Tabla Completa de Reconocimiento y Autoría

| Component / Componente | Author / Autor Original | License / Permisos | Link / Referencia |
| :--- | :--- | :--- | :--- |
| **SPARKY / C.H.I.S.P.A. Modular Engine, Episodes 0–5, Custom Iconic Weapons & CR2W Templates** | **OutKast (`0utKast`)** | **MIT License (100% Open Permissions)** | [GitHub]({GITHUB_REPO_URL}) · [Nexus Mods #38982]({NEXUS_MOD_URL}) |
| **WolvenKit & WolvenKit CLI** | WolvenKit Team & REDModding Community | Open Source | https://github.com/WolvenKit/WolvenKit |
| **RED4ext** | WopsS & Contributors | Open Source | https://github.com/WopsS/RED4ext |
| **ArchiveXL / TweakXL / Codeware** | psiberx | MIT / Open Source | https://github.com/psiberx |
| **redscript & redscript-cli** | jac3km4 | Open Source | https://github.com/jac3km4/redscript |
| **Cyber Engine Tweaks (CET)** | yamashi, maximegmd & Contributors | MIT / Open Source | https://github.com/maximegmd/CyberEngineTweaks |
| **Audioware** | cyb3rpsych0s1s / Roms1383 | Open Source | https://github.com/cyb3rpsych0s1s/audioware |
| **Full Studio Voice Acting (`144` EN + `144` ES Lines + `5` SFX) & Trailer Music (`music_v2_5`)** | **Synthesized & DSP-Mastered by `0utKast`** via ElevenLabs & FFmpeg | **100% Open Redistribution in Mod** | https://elevenlabs.io/ |
| **Base Game Engine & Universe** | CD Projekt RED (*Cyberpunk 2077* 2.x Base Game) | Official Base Game | https://www.cyberpunk.net/ |
"""
    (repo_dir / "CREDITS.md").write_text(content, encoding="utf-8")


def _write_readme(repo_dir: Path) -> None:
    content = f"""# Cyberpunk 2077 — SPARKY Protocol / Protocolo C.H.I.S.P.A.
### *Night City Survival Guide* — Voiced Kiroshi AI Companion (`144` EN & `144` ES Studio Lines, Live Holo-Feed), `6` Episodic Tactical Quests (`Ep. 0–5`), `7` Custom Iconic Weapons, and `3` Quest-Yellow RPG Endings

[![License: MIT & Open Permissions](https://img.shields.io/badge/License-MIT%20%28100%25%20Open%20Permissions%29-brightgreen.svg)](LICENSE)
[![Nexus Mods #38982](https://img.shields.io/badge/Nexus%20Mods-%2338982-da8e35.svg)]({NEXUS_MOD_URL})
[![Official Trailer](https://img.shields.io/badge/YouTube-Official%20Trailer-ff0000.svg)]({YOUTUBE_TRAILER_URL})
[![Release v1.4.0](https://img.shields.io/badge/Release-v1.4.0%20Season%201%20%28EN%20%26%20ES%29-fcee0a.svg)]({GITHUB_REPO_URL}/releases)
[![Cyberpunk 2077 2.x](https://img.shields.io/badge/Cyberpunk%202077-2.x%20Base%20Game%20Compatible-00f0ff.svg)](#universal-compatibility)
[![WolvenKit & Redscript QA](https://img.shields.io/badge/QA-WolvenKit%20RDAR%20%26%20redscript--cli%20Verified-brightgreen.svg)](#architecture--pipeline)

![SPARKY Protocol Header Banner](media/00_HEADER_NEXUS_1920x1080_EN.jpg)

> **🌍 Navigation & Direct Downloads / Navegación y Descarga Directa:**
> - 🧩 **[Nexus Mods Page (`cyberpunk2077/mods/38982`)]({NEXUS_MOD_URL})**
> - 🎬 **[Watch Official 3-Minute Trailer on YouTube / Ver Tráiler Oficial en YouTube (`youtu.be/9MXEEu3NCcc`)]({YOUTUBE_TRAILER_URL})**
> - 📦 **[Download Release `v1.4.0` on GitHub (`SparkyProtocol_EN_v1.4.0.zip` & `ChispaNC_v1.4.0.zip`)]({GITHUB_REPO_URL}/releases/tag/v1.4.0)**
>   - 🇺🇸 **`SparkyProtocol_EN_v1.4.0.zip`** — *100% Pure English Standalone Edition (Vortex / MO2 / Manual)*
>   - 🇪🇸 **`ChispaNC_v1.4.0.zip`** — *Edición Española / Bilingüe (ES & EN, Vortex / MO2 / Manual)*
> - 🇺🇸 **[English Documentation (Campaign Ep. 0–5, Mechanics, Arsenal & Installation)](#english-documentation)**
> - 🇪🇸 **[Documentación en Español (Campaña Ep. 0–5, Mecánicas, Arsenal e Instalación)](#documentación-en-español)**
> - ⚖️ **[Credits & Open Modding Permissions (`CREDITS.md`)](CREDITS.md)** · 📜 **[MIT License (`LICENSE`)](LICENSE)**

---

<a name="english-documentation"></a>
# 🇺🇸 English Documentation

## 1. Overview
**SPARKY Protocol — Night City Survival Guide** (*Protocolo C.H.I.S.P.A.*) is a **100% standalone, base-game compatible (`2.x`, no Phantom Liberty required) episodic campaign and tactical Kiroshi companion mod** for Cyberpunk 2077.

Sabotaged right before the 2022 DataKrash into a foul-mouthed, raspy veteran drill sergeant, **S.P.A.R.K.Y.** hijacks V's Kiroshi optics and guides you across **6 interconnected episodes** spanning **Watson (Little China, Kabuki Creek, Northside, South Quay)**, **Heywood (Arroyo)**, and **Pacifica (Coastview)**. Instead of sterile VR tutorials, every episode teaches deep combat, netrunning, stealth, Tech penetration, Smart-Link locking, and ballistic ricochets through live street encounters, reactive telemetry banter, custom CR2W hazard traps, custom Iconic weapons, and authentic 2022–2077 Night City lore.

---

## 2. Season 1 Campaign (`Episodes 0–5`, `v1.4.0`)

| Episode | Title & Location | Tactical Mechanics, Rewards & Lore |
| :--- | :--- | :--- |
| **Ep. 0** | *Not Your Office Paperclip* (`Megabuilding H10`, Watson) | Rescue S.P.A.R.K.Y. v0.98b, scan targets with Kiroshi `[TAB]`, overload the unstable industrial capacitor (`[F]`), claim `+1,500 €$`, Iconic pistol ***Executive Courtesy*** (`Lexington`), and unlock portable lore on Richard Night & Megabuildings. |
| **Ep. 1** | *Ghosts in the Camera* (`Kabuki Creek`, Watson) | Receive starter `Ping`, hijack chained surveillance cameras (`CAM-01 -> CAM-02`), detonate the Scav Entropy server or overload the red RABIDS relay bank (`[F]`), claim Sector #01 (`+2,200 €$`, Tier-2 quickhacks, Iconic SMG ***Phantom Frequency***), and explore Rache Bartmoss, DataKrash, & the Blackwall. |
| **Ep. 2** | *More Chrome Than Meat* (`Northside Docks`, Watson) | Subvert or rip off Maelstrom's perimeter security turret, purge the pressurized CHOOH2 regulator (`[F]`), recover Sector #02 (`+2,800 €$`, Reboot Optics Lvl 2, Iconic Tech rifle ***Piercing Clause*** `M-179e Achilles`), and discuss Maelstrom, Cyberpsychosis, & MaxTac. |
| **Ep. 3** | *Bullets That Bend Corners* (`South Quay`, Watson) | Experience SPARKY's live `HasSmartLink` optical bridge, encounter Tyger Claws smart-deflecting ink (`OnSmartBulletDeflectedEvent`), invert the Arasaka IFF Jammer Pylon (`[F]`), and recover Sector #03 (`+3,400 €$`, Contagion Lvl 2, Iconic Smart SMG ***Executive Curve*** `Shingen`). |
| **Ep. 4** | *Honor, Scrap & Cardboard Patriots* (`Arroyo`, Heywood) | Unlocks automatically once Watson's police lockdown lifts (`HasLiftedWatsonLockdown`). Activate SPARKY's `CanSeeRicochetVisuals` trajectory preview bridge (`GetNumRicochetBounces()` telemetry), spike the ballistic relay into 6th Street's NUSA ammo depot (`[F]`), and claim Sector #04 (`+4,200 €$`, Iconic ***Street Geometry*** `Masamune`). |
| **Ep. 5** | *Beyond the Blackwall* (`Coastview`, Pacifica) | Storm the Voodoo Boys cryo-node with chained cams, dual Smart + Ricochet bridges, and NetWatch containment purge (`[F]`). Claim Master Sector #05 (`+5,000 €$`, System Collapse Lvl 3, Iconic Tech pistol ***Firewall '22*** `Kenshin`), then choose among **3 Quest-Yellow RPG Endings** (*Autonomous Partner v1.0*, *N54 Data Leak* `+4,500 €$` + Cyberware Malfunction Lvl 3, or *Gunsmith Protocol* forging Iconic revolver ***Sergeant's Last Word*** `Overture`). |

---

## 3. Technical Highlights (`v1.4.0`)
- **Persistent Top-Left Kiroshi Holo-Feed (`440×440`):** Animated `ZETATECH 2022 // KIROSHI` holographic videocall frame during field interventions and final links without applying `PhoneCallRestriction` or blocking movement, Sandevistan, or combat.
- **Instant Combat Interaction Responsiveness:** Field tactical/victory barks (`actionOnComplete == 0`) never hide or lock `[F]` hazard overloads or terminal extractions (`IsSpeechBlockingWorldInteraction` + `InterruptAmbientFieldSpeech`), and `LinearWipe_0` + `m_isPreserveSelectionFadeOut` guards ensure single yellow choices appear and respond without delay.
- **Full Studio Voice Acting (`EN & ES`) + DSP Radio Filtering:** `144` voice clips in English + `144` in Spanish (`V female`, `V male`, raspy drill-sergeant `S.P.A.R.K.Y.` / `C.H.I.S.P.A.`, and unique gang bosses) synced cleanly with `Audioware` (`IntoLocaleExt` dual lookup + `affectedByTimeDilation = false`).
- **Native Yellow Map & Minimap GPS:** Custom `gameJournalQuestMapPin` entries auto-tracked cleanly on `[M]` map and HUD minimap without stealing focus during Prologue / Character Creation (`GameplayTier.Tier1_FullGameplay` + `q001`/`q101` checks).

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
## 5. Compatibility, Requirements & Installation
- **Game Version:** Cyberpunk 2077 `2.x` (**100% Base Game Compatible** — *Phantom Liberty* is **NOT** required).
- **Required Open-Source Frameworks** *(install separately; never bundled inside mod zips)*:
  [RED4ext](https://github.com/WopsS/RED4ext), [ArchiveXL](https://github.com/psiberx/cp2077-archive-xl), [TweakXL](https://github.com/psiberx/cp2077-tweak-xl), [Codeware](https://github.com/psiberx/cp2077-codeware), [redscript](https://github.com/jac3km4/redscript), [Audioware](https://github.com/cyb3rpsych0s1s/audioware), and [Cyber Engine Tweaks](https://github.com/maximegmd/CyberEngineTweaks).
- **Manual / Vortex / MO2 Installation:**
  1. Choose **one** edition from [Nexus Mods #38982]({NEXUS_MOD_URL}) or [GitHub Releases (`v1.4.0`)]({GITHUB_REPO_URL}/releases/tag/v1.4.0):
     - **`SparkyProtocol_EN_v1.4.0.zip`** — Standalone 100% English edition (displays English subtitles/text and plays English voiceovers across all game UI languages).
     - **`ChispaNC_v1.4.0.zip`** — Bilingual Spanish/English edition tailored for Spanish (`es-es` / `es-mx`) or matching EN/ES game setups.
  2. Install via **Vortex** / **Mod Organizer 2**, or extract directly into your `Cyberpunk 2077` root folder. *(Never install both editions simultaneously.)*

---

<a name="architecture--pipeline"></a>
## 6. Repository Architecture & Reproducible Build Pipeline

```mermaid
flowchart LR
    subgraph GEN["1. Python Content & CR2W Generators (src/tools/)"]
        LOC["generate_journal_and_loc.py\n• 315 EN/ES Keys + .journal Quest Graph"]
        ENT["generate_entities.py\n• Custom CR2W Devices, Terminal & Props"]
        AUD["generate_chispa_audio.py\n• 144 EN + 144 ES OGGs + 5 SFX (ElevenLabs + FFmpeg)"]
    end

    subgraph RUNTIME["2. Runtime Modules (src/)"]
        RS["redscript Core & Episodes 0–5\n• ChispaEngine.reds / ChispaTelemetry.reds / Ep00..Ep05.reds"]
        XL["ArchiveXL / TweakXL / Audioware / CET\n• .xl manifests, Iconic Tweak records, .yaml & init.lua"]
    end

    subgraph BUILD["3. Standalone EN Mirror & Release QA"]
        EN["build_english_edition.py\n• Generates chispa_nc_en (SparkyProtocol_EN)"]
        PKG["WolvenKit.CLI RDAR Pack + redscript-cli Lint\n• SparkyProtocol_EN_v1.4.0.zip & ChispaNC_v1.4.0.zip"]
    end

    GEN --> RUNTIME --> BUILD
```

---

<a name="documentación-en-español"></a>
# 🇪🇸 Documentación en Español

![Cabecera Protocolo CHISPA ES](media/00_HEADER_NEXUS_1920x1080_ES.jpg)

## 1. Descripción General
**Protocolo C.H.I.S.P.A. — Guía Callejera de Night City** (*SPARKY Protocol*) es una **expansión narrativa episódica de 6 misiones (`Ep. 0–5`) y compañero táctico en tus ópticas Kiroshi** compatible al 100 % con el **Juego Base de Cyberpunk 2077 (`2.x`)** sin necesitar *Phantom Liberty*.

Una IA táctica de Zetatech de 2022 —saboteada antes del DataKrash con carácter de sargento veterano malhablado— secuestra tus ópticas Kiroshi para guiarte desde **Watson** (**Little China**, **Kabuki Creek**, **Northside**, **Muelle Sur**) hasta **Heywood** (**Arroyo**) y **Pacifica** (**Coastview**), integrando combate vivo, trampas ambientales interactivas, cámaras encadenadas, saboteo de torretas, desvíos Smart, rebotes Power, **7 armas icónicas únicas**, **5 volúmenes de códice**, **doblaje completo en español e inglés** y **3 finales RPG reales en amarillo**.

## 2. Desglose de Campaña (Temporada 1 Completa, `v1.4.0`)
- **Ep. 0 (*No soy un clip de oficina* — H10):** Escanea carroñeros, sobrecarga el condensador industrial con `[F]`, rescata el coprocesador de titanio y consigue `+1.500 €$` más la pistola icónica *«Cortesía Ejecutiva»*.
- **Ep. 1 (*Fantasmas en la Cámara* — Kabuki Creek):** Secuestra cámaras en cadena, lanza `Ping` a través de muros, detona el servidor Entropy / relé RABIDS y recupera el Sector #01 (`+2.200 €$` + subfusil icónico *«Frecuencia Fantasma»*).
- **Ep. 2 (*Más Hierro que Carne* — Northside):** Sabotea o arranca la torreta automática Maelstrom, purga el regulador de presión CHOOH2 con `[F]` y extrae el Sector #02 (`+2.800 €$` + fusil técnico *«Cláusula Perforante»*).
- **Ep. 3 (*Balas que Doblan Esquinas* — Muelle Sur):** Puente óptico Smart en vivo (`HasSmartLink`), desvío de tinta Arasaka, inversión de baliza IFF con `[F]` y extracción del Sector #03 (`+3.400 €$` + subfusil Smart *«Curva Ejecutiva»*).
- **Ep. 4 (*Honor, Chatarra y Patriotas de Cartón* — Arroyo):** Se activa automáticamente tras levantarse el bloqueo policial de Watson. Puente de rebotes Power en vivo (`CanSeeRicochetVisuals`), voladura del alijo NUSA de Calle 6 y Sector #04 (`+4.200 €$` + fusil *«Geometría Callejera»*).
- **Ep. 5 (*Más Allá del Muro Negro* — Coastview, Pacifica):** Asalto al nodo criogénico de los Hijos del Vudú, purga de NetWatch, Sector Maestro #05 (`+5.000 €$` + pistola Tech *«Cortafuegos del 22»*) y **3 finales reales en amarillo** (*Socio Autónomo v1.0*, *Filtración N54* o *Protocolo Armero* con el revólver *«Última Palabra de Sargento»*).

## 3. Instalación Rápida (Español)
1. Descarga **`ChispaNC_v1.4.0.zip`** desde **[Nexus Mods #38982]({NEXUS_MOD_URL})** o desde **[GitHub Releases (`v1.4.0`)]({GITHUB_REPO_URL}/releases/tag/v1.4.0)**.
2. Instala primero los frameworks base (*RED4ext*, *ArchiveXL*, *TweakXL*, *Codeware*, *redscript*, *Audioware*, *Cyber Engine Tweaks*) y extrae el `.zip` en la carpeta raíz de **Cyberpunk 2077** (o mediante **Vortex** / **MO2**). *(No instales simultáneamente la edición inglesa `SparkyProtocol_EN` y la bilingüe `ChispaNC`).*
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
    shutil.copy2(SRC_MOD_DIR / "files" / "bin" / "x64" / "plugins" / "cyber_engine_tweaks" / "mods" / "ChispaNC" / "init.lua", src_dst / "cet" / "chispa_nc_init.lua")
    shutil.copy2(EN_MOD_DIR / "files" / "bin" / "x64" / "plugins" / "cyber_engine_tweaks" / "mods" / "SparkyProtocol_EN" / "init.lua", src_dst / "cet" / "SparkyProtocol_EN_init.lua")

    (src_dst / "tools").mkdir(parents=True, exist_ok=True)
    for tname in (
        "generate_entities.py",
        "generate_journal_and_loc.py",
        "generate_chispa_audio.py",
        "build_english_edition.py",
        "sync_github_repo.py",
        "audio_durations.json",
    ):
        shutil.copy2(TOOLS_DIR / tname, src_dst / "tools" / tname)

    shutil.copy2(SRC_MOD_DIR / "mod.json", src_dst / "mod_chispa_nc.json")
    shutil.copy2(EN_MOD_DIR / "mod.json", src_dst / "mod_sparky_protocol_en.json")

    rel_dst = REPO_DIR / "release_nexus"
    rel_dst.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SRC_MOD_DIR / "docs" / "NEXUS_DESCRIPTION_BBCODE.txt", rel_dst / "NEXUS_DESCRIPTION_BBCODE_EN.txt")
    shutil.copy2(SRC_MOD_DIR / "docs" / "NEXUS_DESCRIPTION_BBCODE_ES.txt", rel_dst / "NEXUS_DESCRIPTION_BBCODE_ES.txt")
    shutil.copy2(SRC_MOD_DIR / "docs" / "README_EN.txt", rel_dst / "README_EN.txt")
    shutil.copy2(SRC_MOD_DIR / "docs" / "LEEME_ES.txt", rel_dst / "LEEME_ES.txt")

    print(
        f"[SYNC OK] {REPO_DIR} | media={copied_media}, reds={rs_count}+{rs_en_count}, tweaks={tw_count}, cr2w_json={cr2w_count}"
    )


if __name__ == "__main__":
    main()
