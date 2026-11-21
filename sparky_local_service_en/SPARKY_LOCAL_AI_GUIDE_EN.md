# S.P.A.R.K.Y. v2.0 — Local AI, Cyberpunk Encyclopedia & Playthrough Memory Guide

> **English Edition — 100% Local & Offline by Default**  
> Runs the conversational brain (`gemma3:12b` on Ollama with automatic VRAM split, or `gemma3:4b` on lighter GPUs) and real-time voice synthesis (`F5-TTS v1 Base` voice cloning on GPU, or `Kokoro-82M` drill-sergeant blend on CPU) directly on your machine, paired with a CPU hybrid lore encyclopedia (`0 MB` extra VRAM) and isolated per-playthrough episodic memory.

---

## 1. One-Click Setup & How to Launch S.P.A.R.K.Y. v2.0

1. **First-time automatic setup (`install_sparky_ai.bat`):**
   - Make sure [Python 3.11 or 3.12](https://www.python.org/downloads/) and [Ollama](https://ollama.com/download) are installed.
   - Double-click **`install_sparky_ai.bat`** inside `sparky_local_service_en\`: it creates `.venv`, installs CUDA (`cu124`) or CPU PyTorch, installs Python packages, and pulls `gemma3:12b`.
2. **While playing Cyberpunk 2077 (Live Kiroshi HUD Link):**
   - Double-click **`start_sparky_service.bat`** inside `sparky_local_service_en\` and leave that terminal window open in the background.
   - The bridge **automatically detects Cyberpunk 2077** across **Steam, GOG, and Epic Games** (or honors `%USERPROFILE%\.sparky_ai_bridge_en\game_path.txt` / `--ipc-dir` for custom paths).
   - Once your save loads in Cyberpunk 2077 (`SparkyProtocol_EN`), opening the Kiroshi prompt will show **`● LOCAL AI ONLINE`**.
3. **To test speakers, switch voice backends, or adjust companion settings (`SPARKY Studio`):**
   - Double-click **`test_sparky_studio_en.bat`**.
   - Inside **SPARKY Studio**, you can choose your WASAPI speaker device, switch between F5-TTS and CPU `Kokoro Sergeant`, swap models (`gemma3:12b` / `gemma3:4b`), adjust **In-Game Reactions**, **Clear Memory** without losing audio settings, or explicitly opt in to online Cyberpunk Wiki lookup.

---

## 2. In-Game Controls (Kiroshi Neural Bar)

| Key | Action |
| :--- | :--- |
| **`Y`** | Opens the native HUD **Kiroshi Neural Link** input bar to type freely to S.P.A.R.K.Y. |
| **`Enter`** | Sends your message to S.P.A.R.K.Y. (interrupts any active spontaneous line immediately). |
| **`Tab`** | Requests an instant tactical situation read without typing. |
| **`↑`** (Up Arrow) | Recalls your last typed message. |
| **`Esc`** | Cancels and closes the input bar without sending anything. |
| **`U`** | Triggers a **live quick tactical callout** directly from gameplay (reads district, active mission, scanned target, health, weapon, and NCPD stars). |

> **Immersion & Priority Guards:** S.P.A.R.K.Y. automatically detects vanilla phone calls, cinematic scenes, active dialogue hubs, system menus, and open Shard readers, muting or holding spontaneous voice playback so it never talks over vanilla characters.

---

## 3. Hybrid Cyberpunk 2077 Lore Encyclopedia (`0 MB` GPU VRAM)

S.P.A.R.K.Y. ships with a 162-card modular knowledge base in `sparky_local_service_en/sparky_rt/lore_kb/`:

- **Identity & Season 1 (`01_sparky_identity_and_season1.json`):** Zetatech 2022 origins, 55-year briefcase lockdown, Kiroshi bus integration, and Episodes 0–5 (including Coastview endings).
- **History & The Net 1990–2077 (`02_history_and_net_1990_2077.json`):** Richard Night, the Collapse, 4 Corporate Wars, Rache Bartmoss & DataKrash (2022), Arasaka Tower (2023), Time of the Red, Blackwall, Soulkiller/Mikoshi, Unification War, and *Edgerunners* (David Martinez, Lucy, Rebecca).
- **Corporations, Gangs, Districts, Characters, Arsenal & Quest Guides (`03`–`08`):** Arasaka, Militech, Zetatech, Kang Tao, Biotechnica (`CHOOH2`), Night Corp, Trauma Team, NetWatch, MaxTac, all gangs and Nomad clans, Night City + Dogtown + Badlands districts, Fixers, Power/Tech/Smart weapons, cyberware, quickhacks, and spoiler-free quest pointers.

### Three-Way Retrieval + Anti-Spoiler Shield
1. **3-Way Hybrid Search in `< 5 ms` on CPU (`0 MB` VRAM):**
   - **Live Kiroshi Pinning:** anchors to your current `district`, tracked mission (`JournalManager.GetTrackedEntry`), scanned enemy, and recently read Shards.
   - **`SQLite FTS5` (BM25):** nails exact quest IDs, cyberware names, and acronyms.
   - **CPU ONNX Dense Vectors (`paraphrase-multilingual-MiniLM-L12-v2`):** matches paraphrased questions semantically.
2. **2022 vs 2077 Era Split & Act 1 Spoiler Gate:**
   - Keeps SPARKY's firsthand pre-DataKrash 2022 memories distinct from 2077 Kiroshi Net scans, and automatically withholds Act 2+ spoilers (Johnny's Relic engram, Dogtown, late endings) when V is still in Act 1 before *The Heist*. (Note: because S.P.A.R.K.Y. carries deep 2022–2077 world records, asking him directly about broader Night City mysteries may still reveal world-building lore "spoilers" early.)
3. **Custom User Lore:**
   - Create `%USERPROFILE%\.sparky_ai_bridge_en\custom_lore_en.json` matching the `lore_kb/*.json` array format (`id`, `title`, `keywords_en`, `keywords_es`, `content`, `era`, `min_act`) and it will index automatically on next launch.

---

## 4. Isolated Per-Playthrough Episodic Memory

Saved state lives in `%USERPROFILE%\.sparky_ai_bridge_en\state\` completely separated per character and playthrough (`profile_<lifepath>_<mem_uid>.json` + `episodic_index_en.sqlite`):

- **Zero Cross-Save Leakage:** Every playthrough stamps a deterministic `chispa_mem_uid` quest fact inside that save. Switching saves or characters while the game and daemon remain open immediately clears in-RAM chat history and resets spontaneous district state—and loading an earlier save of the same character filters out future events by `playthrough_sec`.
- **Shard & Long-Term Recall:** Shards you read and past conversations are indexed in SQLite FTS5 for callbacks later in the campaign, while a background Ollama recap compresses a 15-item journal every 8 turns with zero audio latency.
- **Clear Memory Safely:** Click **`🧹 Clear Memory`** inside **SPARKY Studio** to reset playthrough logs while keeping speakers, voice engine, spontaneity, and custom lore intact.

---

## 5. Spontaneous Reaction Modes

Configurable live from **SPARKY Studio**:
1. **`Tactical` (Recommended Default):** Reacts concisely with cooldowns only to critical combat events (`<= 28%` HP), NCPD escalation / **MaxTac (5★)**, Kiroshi scans of **bosses / cyberpsychos**, long firefight starts/clears, stable district arrivals, and active quest updates.
2. **`Active Companion`:** Adds reactions after closing **Shards** plus varied ambient commentary during quiet cruises or patrols.
3. **`Off`:** S.P.A.R.K.Y. stays silent unless you press **`[Y]`** or **`[U]`**.

---

## 6. Opt-In Online Cyberpunk Wiki Lookup (**Disabled by Default**)

By privacy and reliability design, **S.P.A.R.K.Y. v2.0 runs 100% offline by default** (`enable_online_wiki = false`) and opens **zero external network sockets** unless you explicitly opt in.

If you ever want optional *Cyberpunk Wiki (Fandom)* lookup when stuck on a puzzle or specific gig (cached locally in SQLite for 7 days), enable it via either method:

### Option A — GUI Toggle (Recommended)
1. Open **`test_sparky_studio_en.bat`** (**SPARKY Studio**).
2. Check **`🌐 Allow online Cyberpunk Wiki lookup (Disabled by default — 100% offline unless checked)`**.
3. The change saves atomically and takes effect immediately even if **`start_sparky_service.bat`** is already running. Uncheck anytime to revert to 100% offline.

### Option B — Manual Config Edit
1. Open `%USERPROFILE%\.sparky_ai_bridge_en\companion_prefs.json` in a text editor.
2. Set `"enable_online_wiki": true`:
   ```json
   {
     "enable_online_wiki": true,
     "spontaneous_mode": "tactical",
     "reply_length": "balanced",
     "ambient_cooldown_s": 165.0
   }
   ```
3. Save the file; the running daemon hot-reloads it automatically.

---

## 7. Optional Classic Female Voice Pack (Add-On)

By default, **S.P.A.R.K.Y. v2.0** ships with the redesigned energetic male drill-sergeant voice across both campaign dialogue and Local AI speech.

If you prefer the **classic `v1.4` female S.P.A.R.K.Y. voice** while keeping all `v2.0` subtitle fixes, Tier-1 cyberdeck support, XP rewards, and live HUD features:
1. Download **`SparkyProtocol_EN_FemaleVoicePack_v2.0.0.zip`** from Optional Files.
2. Install the `r6/` folder into your Cyberpunk 2077 directory (allowing it to overwrite the 74 `.ogg` campaign lines from `SparkyProtocol_EN`), and copy `sparky_local_service_en/` into your Local AI service folder (adding `models/sparky_ref_classic_fem_en.wav` + `models/voice_override.json`).
3. Restart `start_sparky_service.bat`. To revert Local AI back to the default drill-sergeant voice anytime, double-click **`disable_female_voice_patch.bat`** inside `sparky_local_service_en\`.
