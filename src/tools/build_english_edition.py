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


def _build_english_subtitle_fallback_methods() -> str:
    cases: list[str] = []
    for line in DIALOGUE_LINES:
        lid = line["id"]
        sub_esc = _escape_redscript_string(line["en_sub"])
        cases.append(f'            case n"{lid}":\n                return "{sub_esc}";')
    cases_block = "\n".join(cases)
    return (
        "    public final func HideFallbackSubtitleIfActive(eventName: CName, token: Int32) -> Void {\n"
        "        if token != this.m_fallbackSubToken || !IsNameValid(eventName) || Equals(eventName, n\"None\") {\n"
        "            return;\n"
        "        }\n"
        "        let game: GameInstance = this.GetGameInstance();\n"
        "        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);\n"
        "        if IsDefined(board) {\n"
        "            let hideIds: array<CRUID>;\n"
        "            ArrayPush(hideIds, CreateCRUID(StringToUint64(NameToString(eventName))));\n"
        "            board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine, ToVariant(hideIds), true);\n"
        "        }\n"
        "    }\n\n"
        "    private final func ResolveFallbackEnglishSubtitle(eventName: CName) -> String {\n"
        "        switch eventName {\n"
        f"{cases_block}\n"
        "            default:\n"
        "                return \"\";\n"
        "        }\n"
        "    }\n\n"
        "    private final func EnsureFallbackSubtitleShown(eventName: CName, speakerEntity: EntityID, speakerName: CName, lineType: scnDialogLineType, duration: Float) -> Void {\n"
        "        if !IsNameValid(eventName) || Equals(eventName, n\"None\") {\n"
        "            return;\n"
        "        }\n"
        "        let key: String = NameToString(eventName);\n"
        "        if StrLen(key) == 0 {\n"
        "            return;\n"
        "        }\n"
        "        let game: GameInstance = this.GetGameInstance();\n"
        "        let locSys: ref<LocalizationSystem> = LocalizationSystem.GetInstance(game);\n"
        "        if IsDefined(locSys) {\n"
        "            let resolved: String = locSys.GetSubtitle(key);\n"
        "            if StrLen(resolved) > 0 && NotEquals(key, resolved) {\n"
        "                return;\n"
        "            }\n"
        "        }\n"
        "        let fallbackText: String = this.ResolveFallbackEnglishSubtitle(eventName);\n"
        "        if Equals(fallbackText, \"\") {\n"
        "            return;\n"
        "        }\n"
        "        let targetObj: wref<GameObject> = EntityID.IsDefined(speakerEntity) ? (GameInstance.FindEntityByID(game, speakerEntity) as GameObject) : null;\n"
        "        let line: scnDialogLineData;\n"
        "        line.duration = duration;\n"
        "        line.id = CreateCRUID(StringToUint64(key));\n"
        "        line.isPersistent = false;\n"
        "        line.speaker = targetObj;\n"
        "        line.speakerName = NameToString(speakerName);\n"
        "        line.text = fallbackText;\n"
        "        line.type = lineType;\n"
        "        let lines: array<scnDialogLineData>;\n"
        "        ArrayPush(lines, line);\n"
        "        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);\n"
        "        if IsDefined(board) {\n"
        "            board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant(lines), true);\n"
        "        }\n"
        "        this.m_fallbackSubToken += 1;\n"
        "        let hideCb: ref<ChispaSubtitleHideCallback> = new ChispaSubtitleHideCallback();\n"
        "        hideCb.system = this;\n"
        "        hideCb.eventName = eventName;\n"
        "        hideCb.token = this.m_fallbackSubToken;\n"
        "        GameInstance.GetDelaySystem(game).DelayCallback(hideCb, MaxF(0.25, duration), false);\n"
        "    }"
    )


def _inject_english_subtitle_fallback(txt: str) -> str:
    nl = "\r\n" if "\r\n" in txt else "\n"
    norm = txt.replace("\r\n", "\n")
    if "ChispaSubtitleHideCallback" in norm:
        return txt
    lip_anchor = (
        "public class ChispaLipSyncCallback extends DelayCallback {\n"
        "    public let system: wref<ChispaSystem>;\n"
        "    public let token: Int32;\n\n"
        "    public func Call() -> Void {\n"
        "        if IsDefined(this.system) {\n"
        "            this.system.OnLipSyncTick(this.token);\n"
        "        }\n"
        "    }\n"
        "}"
    )
    sub_cb = (
        "public class ChispaSubtitleHideCallback extends DelayCallback {\n"
        "    public let system: wref<ChispaSystem>;\n"
        "    public let eventName: CName;\n"
        "    public let token: Int32;\n\n"
        "    public func Call() -> Void {\n"
        "        if IsDefined(this.system) {\n"
        "            this.system.HideFallbackSubtitleIfActive(this.eventName, this.token);\n"
        "        }\n"
        "    }\n"
        "}"
    )
    assert lip_anchor in norm
    norm = norm.replace(lip_anchor, lip_anchor + "\n\n" + sub_cb, 1)
    norm = norm.replace(
        "    private let m_skipHintVisible: Bool;",
        "    private let m_skipHintVisible: Bool;\n    private let m_fallbackSubToken: Int32;",
        1,
    )
    norm = norm.replace(
        "        this.m_skipHintVisible = false;",
        "        this.m_skipHintVisible = false;\n        this.m_fallbackSubToken = 0;",
        1,
    )
    norm = norm.replace(
        "    private final func StopCurrentSpeechAudio() -> Void {\n        if !IsNameValid(this.m_currentPlayingEvent)",
        "    private final func StopCurrentSpeechAudio() -> Void {\n        this.m_fallbackSubToken += 1;\n        if !IsNameValid(this.m_currentPlayingEvent)",
        1,
    )
    clear_anchor = (
        "    private final func ClearCurrentSpeechTracking() -> Void {\n"
        "        this.m_currentPlayingEvent = n\"None\";\n"
        "        this.m_currentPlayingEntity = new EntityID();\n"
        "        this.m_currentPlayingSpeaker = n\"None\";\n"
        "    }"
    )
    assert clear_anchor in norm
    norm = norm.replace(clear_anchor, clear_anchor + "\n\n" + _build_english_subtitle_fallback_methods(), 1)
    norm = norm.replace(
        "        let dur: Float = this.ResolveStepDuration(step, audioExt);\n        this.StartNpcLipSync(",
        "        let dur: Float = this.ResolveStepDuration(step, audioExt);\n        this.EnsureFallbackSubtitleShown(step.eventName, speakerEntity, resolvedSpeaker, step.lineType, dur);\n        this.StartNpcLipSync(",
        1,
    )
    return norm.replace("\n", nl)


def _transform_redscript_source(src_text: str, rel_posix: str, en_durations: dict[str, float]) -> str:
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
        txt = _inject_english_subtitle_fallback(txt)
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
    lua_content = """-- SPARKY Protocol — CET Study & Test Panel (English Edition, Season 1: Episodes 0–5)

local SparkyUI = {
    overlayOpen = false,
    showPanel = false,
}

local statusText = "Ready to test Episode 0 behind Megabuilding H10."

local function withSystem(fn)
    local sys = Game.GetScriptableSystemsContainer():Get("ChispaNC.ChispaSystem")
    if not sys then
        statusText = "Error: ChispaNC.ChispaSystem is not loaded yet."
        return
    end
    fn(sys)
end

registerHotkey("chispa_toggle_panel", "Show/Hide SPARKY Debug & Study Panel", function()
    SparkyUI.showPanel = not SparkyUI.showPanel
end)

registerForEvent("onInit", function()
    print("[SparkyProtocol_EN] CET Panel initialized (hidden by default).")
end)

registerForEvent("onOverlayOpen", function()
    SparkyUI.overlayOpen = true
end)

registerForEvent("onOverlayClose", function()
    SparkyUI.overlayOpen = false
end)

registerForEvent("onDraw", function()
    if not SparkyUI.overlayOpen or not SparkyUI.showPanel then
        return
    end

    local open, keepOpen = ImGui.Begin("SPARKY Protocol — CET Study Panel", SparkyUI.showPanel, ImGuiWindowFlags.AlwaysAutoResize)
    if keepOpen == false then
        SparkyUI.showPanel = false
    end
    if open then
        ImGui.Text("S.P.A.R.K.Y. v0.98b — Night City Survival Guide (Complete Season 1: Ep. 0–5)")
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
