"""
Builds the standalone 100% English edition of Protocolo CHISPA / SPARKY Protocol
in mods/chispa_nc_en (archive_name: SparkyProtocol_EN) from mods/chispa_nc sources.

Usage:
  python mods/chispa_nc/tools/build_english_edition.py
"""

from __future__ import annotations

import json
import re
import shutil
import sys
from pathlib import Path
from typing import Any

import yaml

TOOLS_DIR = Path(__file__).resolve().parent
SRC_MOD_DIR = TOOLS_DIR.parent
MODS_DIR = SRC_MOD_DIR.parent
DST_MOD_DIR = MODS_DIR / "chispa_nc_en"

if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from generate_chispa_audio import DIALOGUE_LINES, SFX_SPECS  # noqa: E402
from generate_journal_and_loc import LOC_STRINGS  # noqa: E402

ALL_CP2077_LOCALES: tuple[str, ...] = (
    "en-us",
    "es-es",
    "es-mx",
    "de-de",
    "fr-fr",
    "pl-pl",
    "pt-br",
    "it-it",
    "ru-ru",
    "jp-jp",
    "kr-kr",
    "zh-cn",
    "zh-tw",
    "cz-cz",
    "hu-hu",
    "tr-tr",
    "ar-ar",
    "th-th",
    "ua-ua",
)

AUDIOWARE_LOCALES: tuple[str, ...] = ALL_CP2077_LOCALES


def _escape_redscript_string(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def _clean_dir(path: Path) -> None:
    if path.exists():
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)


def _write_mod_json() -> None:
    src_meta = json.loads((SRC_MOD_DIR / "mod.json").read_text(encoding="utf-8"))
    dst_meta = dict(src_meta)
    dst_meta["slug"] = "chispa_nc_en"
    dst_meta["archive_name"] = "SparkyProtocol_EN"
    dst_meta["name_en"] = "SPARKY Protocol - Night City Survival Guide (English)"
    dst_meta["name_es"] = "SPARKY Protocol - Night City Survival Guide (English)"
    dst_meta["nexus"] = {"mod_id": None, "mod_uid": None, "file_id": None}
    (DST_MOD_DIR / "mod.json").write_text(
        json.dumps(dst_meta, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def _copy_wolvenkit_sources() -> None:
    src_wk = SRC_MOD_DIR / "wolvenkit_src" / "archive" / "chispa_nc"
    dst_wk = DST_MOD_DIR / "wolvenkit_src" / "archive" / "chispa_nc"
    _clean_dir(DST_MOD_DIR / "wolvenkit_src")

    (dst_wk / "entities").mkdir(parents=True, exist_ok=True)
    for ent in sorted((src_wk / "entities").glob("*.ent.json")):
        shutil.copy2(ent, dst_wk / "entities" / ent.name)

    (dst_wk / "journal").mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        src_wk / "journal" / "chispa_nc.journal.json",
        dst_wk / "journal" / "chispa_nc.journal.json",
    )

    (dst_wk / "localization").mkdir(parents=True, exist_ok=True)
    shutil.copy2(
        src_wk / "localization" / "en-us.json.json",
        dst_wk / "localization" / "en-us.json.json",
    )


def _write_archivexl_manifest() -> None:
    xl_dir = DST_MOD_DIR / "files" / "archive" / "pc" / "mod"
    xl_dir.mkdir(parents=True, exist_ok=True)
    lines = [
        "# SPARKY Protocol (100% English Edition) — ArchiveXL Manifest",
        "journal:",
        "  - chispa_nc\\journal\\chispa_nc.journal",
        "localization:",
        "  onscreens:",
    ]
    for loc in ALL_CP2077_LOCALES:
        lines.append(f"    {loc}: chispa_nc\\localization\\en-us.json")
    (xl_dir / "SparkyProtocol_EN.xl").write_text("\n".join(lines) + "\n", encoding="utf-8")


def _copy_audioware_and_manifest() -> tuple[int, int]:
    src_aw = SRC_MOD_DIR / "files" / "r6" / "audioware" / "ChispaNC"
    dst_aw = DST_MOD_DIR / "files" / "r6" / "audioware" / "SparkyProtocol_EN"
    _clean_dir(dst_aw)

    en_files = sorted((src_aw / "audio" / "en").glob("*.ogg"))
    sfx_files = sorted((src_aw / "audio" / "sfx").glob("*.ogg"))

    (dst_aw / "audio" / "en").mkdir(parents=True, exist_ok=True)
    (dst_aw / "audio" / "sfx").mkdir(parents=True, exist_ok=True)
    for src in en_files:
        shutil.copy2(src, dst_aw / "audio" / "en" / src.name)
    for src in sfx_files:
        shutil.copy2(src, dst_aw / "audio" / "sfx" / src.name)

    sfx_section = {
        spec["id"]: {"file": f"./audio/sfx/{spec['id']}.ogg"}
        for spec in SFX_SPECS
    }
    voices_section: dict[str, Any] = {}
    for line in DIALOGUE_LINES:
        lid = line["id"]
        sub_en = line["en_sub"]
        entry: dict[str, Any] = {}
        if line["speaker"] == "v":
            for loc in AUDIOWARE_LOCALES:
                entry[loc] = {
                    "fem": {"file": f"./audio/en/{lid}_fem.ogg", "subtitle": sub_en},
                    "male": {"file": f"./audio/en/{lid}_male.ogg", "subtitle": sub_en},
                }
        else:
            for loc in AUDIOWARE_LOCALES:
                entry[loc] = {"file": f"./audio/en/{lid}.ogg", "subtitle": sub_en}
        voices_section[lid] = entry

    manifest = {
        "version": "1.0.0",
        "sfx": sfx_section,
        "voices": voices_section,
    }
    header = "# SPARKY Protocol (English Edition) — Audioware Voice & SFX Manifest\n"
    (dst_aw / "SparkyProtocol_EN.yaml").write_text(
        header + yaml.safe_dump(manifest, allow_unicode=True, sort_keys=False, width=1000),
        encoding="utf-8",
    )
    return len(en_files), len(sfx_files)


def _copy_tweaks() -> None:
    src_tw = SRC_MOD_DIR / "files" / "r6" / "tweaks" / "ChispaNC"
    dst_tw = DST_MOD_DIR / "files" / "r6" / "tweaks" / "SparkyProtocol_EN"
    _clean_dir(dst_tw)
    for yml in sorted(src_tw.glob("*.yaml")):
        shutil.copy2(yml, dst_tw / yml.name)


def _load_english_durations() -> dict[str, float]:
    dur_data = json.loads((TOOLS_DIR / "audio_durations.json").read_text(encoding="utf-8"))
    out: dict[str, float] = {}
    for lid, entry in dur_data.get("voices", {}).items():
        if "en" in entry:
            out[lid] = float(entry["en"])
        else:
            fem = float(entry.get("en_fem", 0.0))
            male = float(entry.get("en_male", 0.0))
            val = max(fem, male)
            if val <= 0.2:
                raise RuntimeError(f"Missing English duration for '{lid}' in audio_durations.json")
            out[lid] = val
    return out


def _build_english_audioxl_manifest() -> str:
    """Generates the English-only AudioXL manifest matching DIALOGUE_LINES and SFX_SPECS."""
    lines = [
        "// Protocolo CHISPA / SPARKY Protocol — AudioXL Manifest Registration (SparkyProtocol_EN)",
        "// Auto-generated from Audioware YAML; shares the exact .ogg assets with zero file duplication.",
        "module ChispaNC",
        "",
        '@if(ModuleExists("AudioXL"))',
        "import AudioXL.*",
        "",
        '@if(ModuleExists("AudioXL"))',
        "public class ChispaAudioXLService extends ScriptableService {",
        "    private cb func OnLoad() -> Void {",
        "        let s: ref<AudioXLSound>;",
    ]
    for spec in SFX_SPECS:
        sid = spec["id"]
        lines.append(
            f'        AudioXLAPI.RegisterSound("SparkyProtocol_EN", n"{sid}", n"mod_sfx_2d", '
            f'"r6/audioware/SparkyProtocol_EN/audio/sfx/{sid}.ogg");'
        )
    for line in DIALOGUE_LINES:
        lid = line["id"]
        if line["speaker"] == "v":
            lines.extend(
                [
                    "        s = new AudioXLSound();",
                    f'        s.name = n"{lid}";',
                    '        s.type = n"axl_voice_2d";',
                    f'        s.AddFile("", "r6/audioware/SparkyProtocol_EN/audio/en/{lid}_fem.ogg", '
                    f'"r6/audioware/SparkyProtocol_EN/audio/en/{lid}_male.ogg");',
                    '        AudioXLAPI.RegisterSound("SparkyProtocol_EN", s);',
                ]
            )
        else:
            lines.append(
                f'        AudioXLAPI.RegisterSound("SparkyProtocol_EN", n"{lid}", n"axl_voice_2d", '
                f'"r6/audioware/SparkyProtocol_EN/audio/en/{lid}.ogg");'
            )
    lines.extend(["    }", "}", ""])
    return "\n".join(lines)


def _transform_redscript_source(src_text: str, rel_posix: str, en_durations: dict[str, float]) -> str:
    if rel_posix == "Core/ChispaAudioXLManifest.reds":
        return _build_english_audioxl_manifest()

    txt = src_text

    loc_pattern = re.compile(r'n"(ch_[a-z0-9_]+)"(\s*,\s*)"((?:[^"\\]|\\.)*)"')

    def _replace_loc_fallback(match: re.Match[str]) -> str:
        key = match.group(1)
        sep = match.group(2)
        if key not in LOC_STRINGS:
            raise KeyError(f"Localization key '{key}' in {rel_posix} missing from LOC_STRINGS")
        en_esc = _escape_redscript_string(LOC_STRINGS[key][0])
        return f'n"{key}"{sep}"{en_esc}"'

    txt = loc_pattern.sub(_replace_loc_fallback, txt)

    speech_pattern = re.compile(
        r'MakeSpeechStep\(\s*n"(ch_[a-z0-9_]+)"\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*([^,]+?)\s*,\s*[0-9]+(?:\.[0-9]+)?\s*\)'
    )

    def _replace_speech_step(match: re.Match[str]) -> str:
        lid = match.group(1)
        speaker_tag = match.group(2)
        speaker_name = match.group(3)
        line_type = match.group(4)
        if lid not in en_durations:
            raise KeyError(f"Dialogue ID '{lid}' in {rel_posix} missing from English durations")
        if speaker_name == 'n"CHISPA"':
            speaker_name = 'n"SPARKY"'
        return f'MakeSpeechStep(n"{lid}", {speaker_tag}, {speaker_name}, {line_type}, {en_durations[lid]:.2f})'

    txt = speech_pattern.sub(_replace_speech_step, txt)

    if rel_posix == "Core/ChispaEngine.reds":
        txt = txt.replace(
            "    private final func PreferEnglishBuiltInSubtitleOnly() -> Bool {\n        return false;\n    }",
            "    private final func PreferEnglishBuiltInSubtitleOnly() -> Bool {\n        return true;\n    }",
            1,
        )

    if rel_posix == "Core/ChispaLiveCompanion.reds":
        live_ui_replacements = (
            ("ENLACE NEURAL KIROSHI // C.H.I.S.P.A. v2.0", "KIROSHI NEURAL LINK // S.P.A.R.K.Y. v2.0"),
            ("● IA LOCAL EN LÍNEA", "● LOCAL AI ONLINE"),
            ("▲ INICIA INICIAR_SERVICIO_CHISPA.BAT", "▲ RUN START_SPARKY_SERVICE.BAT"),
            ("Escribe tu mensaje para C.H.I.S.P.A. y pulsa [ENTER]...", "Type your message for S.P.A.R.K.Y. and press [ENTER]..."),
            (
                "[ENTER] TRANSMITIR    •    [TAB] ANÁLISIS TÁCTICO RÁPIDO    •    [↑] ÚLTIMO MENSAJE    •    [ESC] CANCELAR",
                "[ENTER] TRANSMIT    •    [TAB] QUICK TACTICAL SCAN    •    [↑] LAST MESSAGE    •    [ESC] CANCEL",
            ),
            ("CANAL NEURAL // ESCUCHANDO A V", "NEURAL CHANNEL // LISTENING TO V"),
            ("PROCESANDO ENLACE NEURAL...", "PROCESSING NEURAL LINK..."),
            ("ENLACE IA LOCAL // EN VIVO", "LOCAL AI LINK // LIVE"),
            ("MODO SARGENTO // SIN FILTRO", "DRILL SERGEANT // UNFILTERED"),
            (
                "ENLACE LOCAL DESCONECTADO — Abre iniciar_servicio_chispa.bat para activar la voz de CHISPA.",
                "LOCAL AI OFFLINE — Run start_sparky_service.bat to activate SPARKY's live voice.",
            ),
        )
        for es_str, en_str in live_ui_replacements:
            txt = txt.replace(f'"{es_str}"', f'"{en_str}"')

    return txt


def _copy_and_transform_scripts() -> int:
    src_scripts = SRC_MOD_DIR / "files" / "r6" / "scripts" / "ChispaNC"
    dst_scripts = DST_MOD_DIR / "files" / "r6" / "scripts" / "SparkyProtocol_EN"
    _clean_dir(dst_scripts)

    en_durations = _load_english_durations()
    count = 0
    for src in sorted(src_scripts.rglob("*.reds")):
        rel = src.relative_to(src_scripts)
        dst = dst_scripts / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        transformed = _transform_redscript_source(
            src.read_text(encoding="utf-8"),
            rel.as_posix(),
            en_durations,
        )
        dst.write_text(transformed, encoding="utf-8")
        count += 1
    return count


def _write_cet_panel() -> None:
    cet_dir = DST_MOD_DIR / "files" / "bin" / "x64" / "plugins" / "cyber_engine_tweaks" / "mods" / "SparkyProtocol_EN"
    _clean_dir(cet_dir)

    src_ipc_lua = (
        SRC_MOD_DIR / "files" / "bin" / "x64" / "plugins" / "cyber_engine_tweaks" / "mods" / "ChispaNC" / "live_ipc.lua"
    ).read_text(encoding="utf-8")
    en_ipc_lua = src_ipc_lua.replace(
        "-- Protocolo CHISPA v2.0 — Puente IPC por archivos seguros en CET (Windows)",
        "-- SPARKY Protocol v2.0 — Atomic File IPC Bridge in CET (Windows)",
    )
    (cet_dir / "live_ipc.lua").write_text(en_ipc_lua, encoding="utf-8")

    lua_content = """-- SPARKY Protocol — CET Live Kiroshi Link (v2.0) & Study Panel (Season 1: Episodes 0–5)

local LiveIPC = require("live_ipc")

local SparkyUI = {
    overlayOpen = false,
    showLiveChat = false,
    showPanel = true,
    inputText = "",
    cetSession = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999)),
    reqId = 0,
    lastFlushedNativeSeq = 0,
    lastInboxSession = "",
    lastInboxMsgId = 0,
    lastReplySeq = 0,
    daemonOnline = false,
    daemonInfo = "Local AI offline — run sparky_local_service_en/start_sparky_service.bat",
    fastGateTimer = 0.0,
    lastReqSentAt = -999.0,
    telemetryTimer = 0.50,
    inboxTimer = 0.0,
    heartbeatTimer = 2.50,
    liveStatus = "Press [Y] in-game to talk with S.P.A.R.K.Y. or [U] for quick tactical scan.",
    chatLog = {},
}

local statusText = "Ready to test Episode 0 behind Megabuilding H10."

local function pushChatLog(author, text)
    if type(text) ~= "string" or #text == 0 then
        return
    end
    table.insert(SparkyUI.chatLog, { author = author, text = text })
    if #SparkyUI.chatLog > 40 then
        table.remove(SparkyUI.chatLog, 1)
    end
end

local function withSystem(fn)
    local sys = Game.GetScriptableSystemsContainer():Get("ChispaNC.ChispaSystem")
    if not sys then
        statusText = "Error: ChispaNC.ChispaSystem is not loaded yet."
        return
    end
    fn(sys)
end

local ICONIC_ARSENAL = {
    "Items.Preset_Lexington_Chispa",
    "Items.Preset_Saratoga_Chispa",
    "Items.Preset_Achilles_Chispa",
    "Items.Preset_Shingen_Chispa",
    "Items.Preset_Masamune_Chispa",
    "Items.Preset_Kenshin_Chispa",
    "Items.Preset_Overture_Chispa",
}

local SHOWCASE_AMMO = {
    "Ammo.HandgunAmmo",
    "Ammo.RifleAmmo",
    "Ammo.SniperRifleAmmo",
    "Ammo.ShotgunAmmo",
}

local function grantShowcaseArsenal()
    if not Game or not Game.AddToInventory then
        statusText = "Error: load an active save first before spawning the arsenal."
        return
    end
    local player = Game.GetPlayer and Game.GetPlayer() or nil
    if not player then
        statusText = "Error: V is not spawned yet (load a save first)."
        return
    end
    local ts = Game.GetTransactionSystem and Game.GetTransactionSystem() or nil
    local added = 0
    for _, tdb in ipairs(ICONIC_ARSENAL) do
        local alreadyOwned = false
        if ts and ItemID and TweakDBID then
            local ok, qty = pcall(function()
                return ts:GetItemQuantity(player, ItemID.FromTDBID(TweakDBID.new(tdb)))
            end)
            if ok and tonumber(qty or 0) > 0 then
                alreadyOwned = true
            end
        end
        if not alreadyOwned then
            pcall(Game.AddToInventory, tdb, 1)
            added = added + 1
        end
    end
    for _, ammoId in ipairs(SHOWCASE_AMMO) do
        pcall(Game.AddToInventory, ammoId, 300)
    end
    withSystem(function(sys)
        pcall(function()
            sys:EnsureSmartBridgeActive(player)
            sys:EnsureRicochetBridgeActive(player)
        end)
    end)
    statusText = string.format("Showcase Arsenal ready: 7/7 Iconic Weapons (%d newly added) + Ammo + Smart/Ricochet Kiroshi Bridges active.", added)
end

local function sendLiveRequest(action, rawText)
    local clean = tostring(rawText or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if action == "chat" and #clean == 0 then
        return
    end
    SparkyUI.reqId = SparkyUI.reqId + 1
    SparkyUI.lastReqSentAt = os.clock()
    if action == "chat" then
        pushChatLog("YOU", clean)
        SparkyUI.liveStatus = "Querying S.P.A.R.K.Y. local neural core..."
    elseif action == "tactical" then
        clean = "[AUTO_SITUACION]"
        pushChatLog("YOU [TACTICAL]", "Analyze my current situation in Night City.")
        SparkyUI.liveStatus = "Requesting live tactical remark over Kiroshi..."
    elseif action == "stop" then
        SparkyUI.liveStatus = "Live voice silenced."
        withSystem(function(sys)
            sys:PushLiveCompanionSubtitle(0, "", 0.0)
        end)
    end
    LiveIPC.sendRequest(SparkyUI.cetSession, SparkyUI.reqId, action, clean)
end

registerHotkey("sparky_toggle_live_chat", "Open HUD Neural Bar (or toggle CET chat window)", function()
    if not SparkyUI.overlayOpen then
        withSystem(function(sys)
            sys:OpenKiroshiPrompt()
        end)
    else
        SparkyUI.showLiveChat = not SparkyUI.showLiveChat
    end
end)

registerHotkey("sparky_quick_tactical_remark", "Request live tactical remark from S.P.A.R.K.Y.", function()
    withSystem(function(sys)
        sys:TriggerQuickTacticalRemark()
    end)
end)

registerHotkey("sparky_stop_live_voice", "Silence S.P.A.R.K.Y. live AI voice", function()
    sendLiveRequest("stop", "")
end)

registerHotkey("sparky_toggle_panel", "Show/Hide SPARKY Debug & Study Panel (Ep. 0-5)", function()
    SparkyUI.showPanel = not SparkyUI.showPanel
end)

registerHotkey("sparky_grant_iconic_arsenal", "Grant All 7 Iconic Weapons + Ammo (Showcase)", function()
    grantShowcaseArsenal()
end)

registerForEvent("onInit", function()
    math.randomseed(os.time())
    SparkyUI.cetSession = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    pushChatLog("SYSTEM", "Native Kiroshi Link ready ([Y] Type to SPARKY / [U] Quick Tactical Scan).")
    print("[SparkyProtocol_EN] HUD Neural Bar + Live IPC Bridge initialized.")
end)

registerForEvent("onOverlayOpen", function()
    SparkyUI.overlayOpen = true
    withSystem(function(sys)
        sys:SetCetOverlayOpen(true)
    end)
end)

registerForEvent("onOverlayClose", function()
    SparkyUI.overlayOpen = false
    withSystem(function(sys)
        sys:SetCetOverlayOpen(false)
    end)
end)

registerForEvent("onUpdate", function(delta)
    SparkyUI.fastGateTimer = SparkyUI.fastGateTimer + delta
    if SparkyUI.fastGateTimer < 0.06 then
        return
    end
    local step = SparkyUI.fastGateTimer
    SparkyUI.fastGateTimer = 0.0

    if not Game or not Game.GetScriptableSystemsContainer then
        return
    end
    local sys = Game.GetScriptableSystemsContainer():Get("ChispaNC.ChispaSystem")
    if not sys then
        return
    end

    local pendingSeq = tonumber(sys:GetPendingLiveReqSeq()) or 0
    if pendingSeq < SparkyUI.lastFlushedNativeSeq then
        SparkyUI.lastFlushedNativeSeq = 0
    end
    if pendingSeq > SparkyUI.lastFlushedNativeSeq then
        SparkyUI.lastFlushedNativeSeq = pendingSeq
        SparkyUI.telemetryTimer = 0.0
        LiveIPC.writeState(sys:ExportLiveStateJson(), true)
        sendLiveRequest(sys:GetPendingLiveReqAction(), sys:GetPendingLiveReqText())
    end

    local inMenu = sys:IsInSystemOrPauseMenu()
    local isBusy = sys:IsLiveCompanionBusy()

    SparkyUI.telemetryTimer = SparkyUI.telemetryTimer + step
    local telePeriod = inMenu and 1.20 or 0.50
    if SparkyUI.telemetryTimer >= telePeriod then
        SparkyUI.telemetryTimer = 0.0
        LiveIPC.writeState(sys:ExportLiveStateJson(), false)
    end

    if SparkyUI.daemonOnline then
        SparkyUI.inboxTimer = SparkyUI.inboxTimer + step
        local awaitingReply = isBusy or ((os.clock() - SparkyUI.lastReqSentAt) < 5.0)
        local inboxPeriod = awaitingReply and 0.08 or (inMenu and 1.20 or 0.40)
        if SparkyUI.inboxTimer >= inboxPeriod then
            SparkyUI.inboxTimer = 0.0
            local pkt = LiveIPC.readInbox()
            if pkt and pkt.session_id and pkt.msg_id then
                if tostring(pkt.session_id) ~= SparkyUI.lastInboxSession then
                    SparkyUI.lastInboxSession = tostring(pkt.session_id)
                    SparkyUI.lastInboxMsgId = 0
                    SparkyUI.lastReplySeq = 0
                end
                local msgId = tonumber(pkt.msg_id) or 0
                if msgId > SparkyUI.lastInboxMsgId then
                    SparkyUI.lastInboxMsgId = msgId
                    local st = tonumber(pkt.state) or 0
                    local sub = tostring(pkt.subtitle or "")
                    local dur = tonumber(pkt.duration) or 4.0
                    sys:PushLiveCompanionSubtitle(st, sub, dur)
                    if st == 0 then
                        SparkyUI.liveStatus = "Ready — press [Y] in-game or [U] for quick tactical scan."
                    elseif #sub > 0 then
                        SparkyUI.liveStatus = "S.P.A.R.K.Y. speaking live..."
                    end
                    local rSeq = tonumber(pkt.reply_seq) or 0
                    local fullReply = tostring(pkt.full_reply or "")
                    if rSeq > SparkyUI.lastReplySeq and #fullReply > 0 then
                        SparkyUI.lastReplySeq = rSeq
                        pushChatLog("S.P.A.R.K.Y.", fullReply)
                    end
                end
            end
        end
    end

    SparkyUI.heartbeatTimer = SparkyUI.heartbeatTimer + step
    if SparkyUI.heartbeatTimer >= 2.50 then
        SparkyUI.heartbeatTimer = 0.0
        local hb = LiveIPC.readHeartbeat()
        if hb and hb.ts and math.abs(os.time() - (tonumber(hb.ts) or 0)) <= 6 then
            SparkyUI.daemonOnline = true
            SparkyUI.daemonInfo = string.format(
                "Local AI ONLINE | LLM: %s | Voice: %s | Output: %s",
                tostring(hb.llm or "gemma3:4b"),
                tostring(hb.tts or "f5_clone"),
                tostring(hb.speaker or "WASAPI")
            )
        else
            SparkyUI.daemonOnline = false
            SparkyUI.daemonInfo = "Local AI offline — run sparky_local_service_en/start_sparky_service.bat"
        end
        sys:SetLiveDaemonOnline(SparkyUI.daemonOnline)
        pcall(function()
            sys:SetLiveVk186Acute(hb and hb.vk186_acute == true or false)
        end)
    end
end)

local function drawLiveChatWindow()
    if not SparkyUI.showLiveChat then
        return
    end
    local cond = ImGuiCond and ImGuiCond.FirstUseEver or 4
    ImGui.SetNextWindowSize(560, 420, cond)
    local open, keepOpen = ImGui.Begin("S.P.A.R.K.Y. v2.0 — Live Kiroshi Link", SparkyUI.showLiveChat)
    if keepOpen == false then
        SparkyUI.showLiveChat = false
    end
    if open then
        if SparkyUI.daemonOnline then
            ImGui.TextColored(0.22, 1.0, 0.53, 1.0, SparkyUI.daemonInfo)
        else
            ImGui.TextColored(1.0, 0.55, 0.25, 1.0, SparkyUI.daemonInfo)
        end
        ImGui.Separator()

        if ImGui.BeginChild("##sparky_live_history", 0, -96, true) then
            for _, entry in ipairs(SparkyUI.chatLog) do
                if entry.author == "S.P.A.R.K.Y." then
                    ImGui.TextColored(0.99, 0.93, 0.04, 1.0, entry.author .. ":")
                elseif entry.author == "SYSTEM" then
                    ImGui.TextColored(0.55, 0.65, 0.78, 1.0, entry.author .. ":")
                else
                    ImGui.TextColored(0.0, 0.94, 1.0, 1.0, entry.author .. ":")
                end
                ImGui.TextWrapped(entry.text)
                ImGui.Spacing()
            end
            ImGui.SetScrollHereY(1.0)
        end
        ImGui.EndChild()

        ImGui.SetNextItemWidth(-1)
        local flags = ImGuiInputTextFlags and ImGuiInputTextFlags.EnterReturnsTrue or 32
        local newText, enterPressed = ImGui.InputText("##sparky_chat_input", SparkyUI.inputText, 512, flags)
        SparkyUI.inputText = newText or ""
        if enterPressed and #SparkyUI.inputText > 0 then
            sendLiveRequest("chat", SparkyUI.inputText)
            SparkyUI.inputText = ""
        end

        if ImGui.Button("Send") then
            if #SparkyUI.inputText > 0 then
                sendLiveRequest("chat", SparkyUI.inputText)
                SparkyUI.inputText = ""
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Tactical Remark") then
            sendLiveRequest("tactical", "[AUTO_SITUACION]")
        end
        ImGui.SameLine()
        if ImGui.Button("Silence") then
            sendLiveRequest("stop", "")
        end
        ImGui.SameLine()
        if ImGui.Button("Clear") then
            SparkyUI.chatLog = {}
        end
        ImGui.SameLine()
        if ImGui.Button(SparkyUI.showPanel and "Hide Ep.0-5" or "Ep.0-5 Panel") then
            SparkyUI.showPanel = not SparkyUI.showPanel
        end

        ImGui.TextWrapped(SparkyUI.liveStatus)
    end
    ImGui.End()
end

registerForEvent("onDraw", function()
    if not SparkyUI.overlayOpen then
        return
    end

    drawLiveChatWindow()

    if not SparkyUI.showPanel then
        return
    end

    local open, keepOpen = ImGui.Begin("SPARKY Protocol — CET Study Panel", SparkyUI.showPanel, ImGuiWindowFlags.AlwaysAutoResize)
    if keepOpen == false then
        SparkyUI.showPanel = false
    end
    if open then
        ImGui.Text("S.P.A.R.K.Y. v0.98b — Night City Survival Guide (Complete Season 1: Ep. 0–5)")
        ImGui.Separator()

        if ImGui.Button("Grant All 7 Iconic Weapons + Ammo (Showcase)") then
            grantShowcaseArsenal()
        end
        ImGui.Separator()

        if Game and Game.GetQuestsSystem then
            local qs = Game.GetQuestsSystem()
            local ep00 = qs:GetFact("chispa_ep00_stage")
            local scanned = qs:GetFact("chispa_ep00_scanned")
            local trap = qs:GetFact("chispa_ep00_used_trap")
            local done0 = qs:GetFact("chispa_ep00_done")
            local ep01 = qs:GetFact("chispa_ep01_stage")
            local cam = qs:GetFact("chispa_ep01_cam_hijacked")
            local ping = qs:GetFact("chispa_ep01_ping_used")
            local surge = qs:GetFact("chispa_ep01_relay_surged")
            local done1 = qs:GetFact("chispa_ep01_done")
            local ep02 = qs:GetFact("chispa_ep02_stage")
            local turret = qs:GetFact("chispa_ep02_turret_hacked")
            local tank = qs:GetFact("chispa_ep02_tank_blown")
            local purge = qs:GetFact("chispa_ep02_reg_purged")
            local done2 = qs:GetFact("chispa_ep02_done")
            local ep03 = qs:GetFact("chispa_ep03_stage")
            local jam = qs:GetFact("chispa_ep03_smart_jammed")
            local bomb = qs:GetFact("chispa_ep03_jammer_down")
            local done3 = qs:GetFact("chispa_ep03_done")
            local ep04 = qs:GetFact("chispa_ep04_stage")
            local rico = qs:GetFact("chispa_ep04_ricochet_used")
            local cache4 = qs:GetFact("chispa_ep04_cache_blown")
            local done4 = qs:GetFact("chispa_ep04_done")
            local ep05 = qs:GetFact("chispa_ep05_stage")
            local cryo5 = qs:GetFact("chispa_ep05_cryo_blown")
            local end5 = qs:GetFact("chispa_ep05_ending")
            local done5 = qs:GetFact("chispa_ep05_done")
            local vmode = qs:GetFact("chispa_videocall_disabled") == 0 and "VIDEOCALL" or "AUDIO ONLY"
            ImGui.Text(string.format("Ep00 Stage: %d | Scan: %d | Trap: %d | Done: %d | Call: %s",
                ep00, scanned, trap, done0, vmode))
            ImGui.Text(string.format("Ep01 Stage: %d | Cam: %d | Ping: %d | Surge: %d | Done: %d",
                ep01, cam, ping, surge, done1))
            ImGui.Text(string.format("Ep02 Stage: %d | Turret: %d | Tank: %d | Purge: %d | Done: %d",
                ep02, turret, tank, purge, done2))
            ImGui.Text(string.format("Ep03 Stage: %d | Jam: %d | Bomb: %d | Done: %d",
                ep03, jam, bomb, done3))
            ImGui.Text(string.format("Ep04 Stage: %d | Ricochet: %d | Cache: %d | Done: %d",
                ep04, rico, cache4, done4))
            ImGui.Text(string.format("Ep05 Stage: %d | Cryo: %d | Ending: %d | Done: %d",
                ep05, cryo5, end5, done5))
        end

        ImGui.Separator()

        if ImGui.Button("Replay Ep. 0 Videocall") then
            withSystem(function(sys)
                sys:ReplayEp00Call()
                statusText = "SPARKY initial videocall triggered."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Toggle Videocall / Audio Only") then
            withSystem(function(sys)
                local enabled = sys:IsVideocallModeEnabled()
                sys:SetVideocallModeEnabled(not enabled)
                statusText = (not enabled) and "Holographic Videocall mode enabled." or "Audio Only mode enabled."
            end)
        end

        if ImGui.Button("Teleport to H10 Backlot (Ep. 0)") then
            withSystem(function(sys)
                sys:TeleportToEp00Alley()
                statusText = "Teleported to the Megabuilding H10 backlot entrance."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Overload Capacitor (Test)") then
            withSystem(function(sys)
                sys:TriggerEp00CapacitorOverload()
                statusText = "Industrial capacitor manually overloaded."
            end)
        end

        if ImGui.Button("Reset Full Campaign (Ep. 0-5)") then
            withSystem(function(sys)
                sys:ResetAllState()
                statusText = "Full SPARKY campaign reset from Episode 0."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Unlock Watson Lockdown (Testing)") then
            withSystem(function(sys)
                sys:UnlockFullNightCityMap()
                statusText = "Watson police lockdown removed."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Quick Tests — Episode 1: Ghosts in the Camera (Kabuki)")

        if ImGui.Button("Jump to Ep. 1") then
            withSystem(function(sys)
                sys:StartEp01Directly()
                statusText = "Episode 1 started (Ep. 0 marked complete)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Go to Kabuki Creek (Ep. 1)") then
            withSystem(function(sys)
                sys:TeleportToEp01Kabuki()
                statusText = "Teleported to Kabuki Creek promenade (Ep. 1)."
            end)
        end

        if ImGui.Button("Overload Ep. 1 Subnet") then
            withSystem(function(sys)
                sys:TriggerEp01RelaySurge()
                statusText = "RABIDS relay and Kabuki Entropy server overloaded."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reset Ep. 1 Only") then
            withSystem(function(sys)
                sys:ResetEp01Only()
                statusText = "Episode 1 cleanly reset."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Quick Tests — Episode 2: More Chrome Than Meat (Northside)")

        if ImGui.Button("Jump to Ep. 2") then
            withSystem(function(sys)
                sys:StartEp02Directly()
                statusText = "Episode 2 started (Ep. 0 + Ep. 1 marked complete)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Go to Northside (Ep. 2)") then
            withSystem(function(sys)
                sys:TeleportToEp02Northside()
                statusText = "Teleported to Northside industrial docks (Ep. 2)."
            end)
        end

        if ImGui.Button("Purge Ep. 2 CHOOH2") then
            withSystem(function(sys)
                sys:TriggerEp02RegulatorSurge()
                statusText = "Pressure regulator and CHOOH2 tank detonated."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reset Ep. 2 Only") then
            withSystem(function(sys)
                sys:ResetEp02Only()
                statusText = "Episode 2 cleanly reset."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Quick Tests — Episode 3: Bullets That Bend Corners (South Quay)")

        if ImGui.Button("Jump to Ep. 3") then
            withSystem(function(sys)
                sys:StartEp03Directly()
                statusText = "Episode 3 started (Ep. 0-2 marked complete)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Go to South Quay (Ep. 3)") then
            withSystem(function(sys)
                sys:TeleportToEp03Waterfront()
                statusText = "Teleported to South Watson Waterfront quay (Ep. 3)."
            end)
        end

        if ImGui.Button("Invert Ep. 3 IFF Jammer") then
            withSystem(function(sys)
                sys:TriggerEp03JammerSurge()
                statusText = "IFF jammer pylon inverted and antenna detonated."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reset Ep. 3 Only") then
            withSystem(function(sys)
                sys:ResetEp03Only()
                statusText = "Episode 3 cleanly reset."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Quick Tests — Episode 4: Honor, Scrap & Cardboard Patriots (Arroyo)")

        if ImGui.Button("Jump to Ep. 4") then
            withSystem(function(sys)
                sys:StartEp04Directly()
                statusText = "Episode 4 started (Watson unlocked & Ep. 0-3 complete)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Go to Arroyo Border (Ep. 4)") then
            withSystem(function(sys)
                sys:TeleportToEp04Border()
                statusText = "Teleported to Arroyo smuggling yard (Ep. 4)."
            end)
        end

        if ImGui.Button("Blow Ep. 4 NUSA Cache") then
            withSystem(function(sys)
                sys:TriggerEp04CacheSurge()
                statusText = "Ballistic relay overloaded and NUSA ammo tank detonated."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reset Ep. 4 Only") then
            withSystem(function(sys)
                sys:ResetEp04Only()
                statusText = "Episode 4 cleanly reset."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Quick Tests — Episode 5: Beyond the Blackwall (Pacifica)")

        if ImGui.Button("Jump to Ep. 5") then
            withSystem(function(sys)
                sys:StartEp05Directly()
                statusText = "Episode 5 started (Ep. 0-4 complete)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Go to Pacifica (Ep. 5)") then
            withSystem(function(sys)
                sys:TeleportToEp05Pacifica()
                statusText = "Teleported to Coastview, Pacifica (Ep. 5)."
            end)
        end

        if ImGui.Button("Purge Ep. 5 Black ICE") then
            withSystem(function(sys)
                sys:TriggerEp05ContainmentPurge()
                statusText = "NetWatch containment pylon purged into cryo-server."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reset Ep. 5 Only") then
            withSystem(function(sys)
                sys:ResetEp05Only()
                statusText = "Episode 5 cleanly reset."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Neural Link v2.0: [Y] HUD Kiroshi Bar | [U] Quick Tactical Remark")
        if Game and Game.GetQuestsSystem then
            local qs = Game.GetQuestsSystem()
            local keysDisabled = qs:GetFact("chispa_disable_default_yu_keys") > 0
            local lbl = keysDisabled and "Re-enable default [Y]/[U] hotkeys" or "Disable default [Y]/[U] keys (use CET Bindings only)"
            if ImGui.Button(lbl) then
                qs:SetFact("chispa_disable_default_yu_keys", keysDisabled and 0 or 1)
                statusText = keysDisabled and "Default [Y]/[U] keys re-enabled." or "Default [Y]/[U] keys disabled; bind your preferred keys in CET Bindings."
            end
            ImGui.SameLine()
        end
        if ImGui.Button(SparkyUI.showLiveChat and "Hide CET Chat Log" or "Show CET Chat Log") then
            SparkyUI.showLiveChat = not SparkyUI.showLiveChat
        end

        ImGui.Separator()
        ImGui.TextWrapped(statusText)
    end
    ImGui.End()
end)
"""
    (cet_dir / "init.lua").write_text(lua_content, encoding="utf-8")


def _copy_docs() -> None:
    src_docs = SRC_MOD_DIR / "docs"
    dst_docs = DST_MOD_DIR / "docs"
    _clean_dir(dst_docs)
    for name in ("README_EN.txt", "NEXUS_DESCRIPTION_BBCODE.txt"):
        shutil.copy2(src_docs / name, dst_docs / name)


def main() -> None:
    _clean_dir(DST_MOD_DIR / "files")
    _write_mod_json()
    _copy_wolvenkit_sources()
    _write_archivexl_manifest()
    en_count, sfx_count = _copy_audioware_and_manifest()
    _copy_tweaks()
    script_count = _copy_and_transform_scripts()
    _write_cet_panel()
    _copy_docs()
    print(
        f"[OK] Generated standalone English edition -> {DST_MOD_DIR} "
        f"(en_audio={en_count}, sfx={sfx_count}, scripts={script_count})"
    )


if __name__ == "__main__":
    main()
