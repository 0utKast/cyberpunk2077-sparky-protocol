-- SPARKY Protocol — CET Live Kiroshi Link (v2.0) & Study Panel (Season 1: Episodes 0–5)

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
