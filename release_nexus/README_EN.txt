SPARKY Protocol - Night City Survival Guide (v2.0.0 — Live Local AI Companion + Complete Season 1)
Author: 0utKast
Compatibility: Cyberpunk 2077 2.x — Base Game Compatible (No Phantom Liberty required; Season 1 ready on Windows / Linux / Proton / Steam Deck; v2.0 Live Local AI Bridge for Windows)
Required Core Frameworks: RED4ext, ArchiveXL, TweakXL, Codeware, redscript, Cyber Engine Tweaks, plus AudioXL (recommended on Linux / Steam Deck & Windows) OR Audioware (Windows)
v2.0.0 4K Live AI Showcase (YouTube): https://youtu.be/oh9oSNnJVh0
Season 1 Campaign Trailer (YouTube): https://youtu.be/9MXEEu3NCcc
Open-Source Repository & Releases (GitHub): https://github.com/0utKast/cyberpunk2077-sparky-protocol

OVERVIEW ("NIGHT CITY'S ANTI-TUTORIAL + LIVE LOCAL AI COMPANION"):
A 2022 Zetatech tactical concierge AI—sabotaged right before the DataKrash into a foul-mouthed veteran drill sergeant with zero corporate censorship—links into your Kiroshi optics and holophone.
- Play the complete 6-episode voiced Season 1 campaign (Episodes 0–5 across Watson, Arroyo & Pacifica) with 7 custom Iconic weapons and 3 RPG endings—no boring VR rooms, only live street combat, optical telemetry, CR2W hazards, and deep lore.
- Pair it with the optional standalone v2.0.0 Local AI Bridge (`SPARKY_v2.0.0_LocalAI_Service_EN.zip`) to chat live from gameplay (`[Y]`), request instant spoken tactical scans (`[U]`), build isolated per-playthrough episodic memory, search 162 offline lore cards (`0 MB` extra VRAM), and hear zero-input spontaneous callouts without cloud APIs or external accounts.

LORE & WORLD-BUILDING "SPOILER" NOTE:
While v2.0's Hybrid RAG shields Act 2+ main-story endings/Relic revelations in Act 1, S.P.A.R.K.Y. carries extensive 2022–2077 Night City intelligence, so optional lore conversations may still discuss deep background mysteries early in a run.

WHAT'S NEW IN v2.0.0 (LIVE LOCAL AI COMPANION BRIDGE):
- HUD Kiroshi Neural Link (`[Y]`) & Live Tactical Read (`[U]`):
  - Press `[Y]` anytime in free roam or stealth to type freely to S.P.A.R.K.Y. (press `[Tab]` inside the bar for a no-typing situation read, `[Up]` to recall your last prompt, or `[Esc]` to cancel).
  - Press `[U]` directly in gameplay to trigger a real-time spoken telemetry breakdown (district, active quest, scanned target, weapon, HP, NCPD wanted level). Keys can be disabled/rebound cleanly via CET Bindings.
- 100% Local Ollama LLM (`gemma3:12b` default, `gemma3:4b` lighter option) + Streaming Voice (`F5-TTS` / `Kokoro-82M`):
  - Streams clause-by-clause replies straight to low-latency voice cloning on GPU (`F5-TTS`) or zero-VRAM CPU `Kokoro Sergeant` blended voices, with automatic NVML VRAM layer splitting on GPUs <=16 GB.
- 162-Card Offline Hybrid RAG Lore Engine (`0 MB` Extra VRAM, `<5 ms` CPU Search):
  - Combines Kiroshi state pinning + `SQLite FTS5` + CPU ONNX multilingual dense vectors across 162 modular Night City lore cards (`custom_lore_en.json` supported), keeping 2022 vs. 2077 framing distinct and gating Act 2+ spoilers during Act 1.
- Isolated Per-Playthrough Episodic Memory (`chispa_mem_uid`):
  - Every save stamps a unique persistent `chispa_mem_uid` and `playthrough_sec` timestamp so different characters/runs never mix memories, reloading earlier saves hides future timeline events, read Shards index automatically, and an async Ollama recap maintains a 15-item 1st-person journal.
- Spontaneous Reactions & Immersion Guards:
  - Toggle live in `SPARKY Studio` between `Tactical` (<=28% HP, NCPD/MaxTac 5-star, cyberpsycho/boss scans, long firefights, district arrivals, quest progress), `Active Companion` (adds Shard comments & ambient road banter), or `Off`. Automatically holds/mutes over vanilla calls, cutscenes, dialogue hubs, menus, and Shard readers.
- Opt-In Cyberpunk Wiki Lookup (Disabled by Default):
  - Opens zero external sockets unless you explicitly check the opt-in toggle inside `SPARKY Studio`.
- One-Click Standalone Installer (`install_sparky_ai.bat`) & Auto Steam / GOG / Epic Detection:
  - Automatically discovers Cyberpunk 2077 across Steam, GOG, and Epic Games (or `--ipc-dir` / `game_path.txt` override) without any hardcoded paths.
- Optional v2.0.0 Female Voice Packs:
  - `SparkyProtocol_EN_FemaleVoicePack_v2.0.0.zip` restores the classic `v1.4` female S.P.A.R.K.Y. voice across both Season 1 and Local AI F5-TTS cloning while preserving all v2.0 upgrades.

INCLUDED SEASON 1 CAMPAIGN (EPISODES 0–5):
- EPISODE 0 — "NOT YOUR OFFICE PAPERCLIP" (Little China, behind Megabuilding H10): 1,500 E$, Iconic pistol "Executive Courtesy", Richard Night & Megabuildings lore.
- EPISODE 1 — "GHOSTS IN THE CAMERA" (Kabuki Creek Pedestrian Promenade, Watson): Chained surveillance cameras (`CAM-01` -> `CAM-02`), Entropy server / RABIDS relay, 2,200 E$, adaptive quickhacks, Iconic SMG "Phantom Frequency", Codex Vol. 1.
- EPISODE 2 — "MORE CHROME THAN MEAT" (Northside Industrial Docks, Watson): Turret subversion, pressurized CHOOH2 tank purge (`[F]`), 2,800 E$, adaptive Reboot Optics, Iconic Tech precision rifle "Piercing Clause" (`M-179e Achilles`), Codex Vol. 2.
- EPISODE 3 — "BULLETS THAT BEND CORNERS" (South Watson Waterfront Quay): Kang Tao Chao Smart pistol + `HasSmartLink` optical bridge, Tyger Claws smart-jammer IFF pylon (`[F]`), 3,400 E$, Iconic Smart SMG "Executive Curve" (Shingen), Codex Vol. 3.
- EPISODE 4 — "HONOR, SCRAP & CARDBOARD PATRIOTS" (Arroyo / Heywood Border — Post-Watson Lockdown): Copperhead rifle + `CanSeeRicochetVisuals` ricochet trajectory bridge, NUSA depot surge (`[F]`), 4,200 E$, Iconic Masamune "Street Geometry", Codex Vol. 4.
- EPISODE 5 — "BEYOND THE BLACKWALL" (Coastview, Pacifica — Season 1 Finale): Voodoo Boys & Animals stronghold, dual Smart + Ricochet bridges, NetWatch cryo purge (`[F]`), 5,000 E$, Iconic Kenshin "Firewall '22", plus 3 Quest-Yellow RPG endings (Autonomous Partner v1.0, N54 Data Leak, or Gunsmith Protocol forging Iconic Overture "Sergeant's Last Word").

INSTALLATION:
1. Main Game Mod (Required): Install the required open-source frameworks (RED4ext, ArchiveXL, TweakXL, Codeware, redscript, Cyber Engine Tweaks, plus AudioXL [recommended on Linux / Steam Deck & Windows] OR Audioware [Windows]), then install ONLY ONE Main ZIP (`SparkyProtocol_EN_v2.0.0.zip` for English, or `ChispaNC_v2.0.0.zip` for Spanish) via Vortex, MO2, or extracting into your Cyberpunk 2077 root folder.
2. Live Local AI Bridge (Optional for v2.0 `[Y]`/`[U]` AI Features): Install Python 3.11/3.12 + Ollama, extract `SPARKY_v2.0.0_LocalAI_Service_EN.zip` anywhere on your PC, run `install_sparky_ai.bat`, pick your audio device in `test_sparky_studio_en.bat`, and run `start_sparky_service.bat` while playing.

PRIOR CHANGELOG SUMMARY (v1.5.1 – v1.6.1 INCLUDED):
- v1.6.1: Fixed menu-close quickhack repeat grant via deterministic `ItemID.CreateQuery` + Cyberdeck slot checks; moved Ep. 1 onto Kabuki Creek pedestrian promenade off roadway traffic; clean non-program quest hardware records for RAM (+8 base, +3/sector up to +23 RAM).
- v1.6.0: Dual optional AudioXL + Audioware conditional compilation backend (100% Linux / Proton / Steam Deck ready).
- v1.5.1–v1.5.3: Adaptive Level-2 / Tier-1 Cyberdeck quickhacks, real XP/Street Cred/Skill rewards, pause/menu subtitle sync, redesigned drill-sergeant voices, 2-line UTF-8 subtitle pagination across 19 locales.

PERMISSIONS & CREDITS:
100% Open Permissions (MIT): Free to modify, reuse assets, translate, and redistribute with credit to 0utKast (https://github.com/0utKast/cyberpunk2077-sparky-protocol). Built with open-source WolvenKit, RED4ext, ArchiveXL, TweakXL, Codeware, redscript, AudioXL (DigitalVixen), Audioware (cyb3rpsych0s1s), Cyber Engine Tweaks, Ollama, F5-TTS, Kokoro-82M, ONNX Runtime, ElevenLabs, and FFmpeg.
