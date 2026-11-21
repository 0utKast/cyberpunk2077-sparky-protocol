-- Protocolo CHISPA / SPARKY Protocol — CET Enlace Kiroshi en Vivo (v2.0) + Panel Estudio (Ep. 0–5)

local LiveIPC = require("live_ipc")

local ChispaUI = {
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
    daemonInfo = "IA local desconectada — ejecuta sparky_local_service/iniciar_servicio_chispa.bat",
    fastGateTimer = 0.0,
    lastReqSentAt = -999.0,
    telemetryTimer = 0.50,
    inboxTimer = 0.0,
    heartbeatTimer = 2.50,
    liveStatus = "Pulsa [Y] en juego para hablar con C.H.I.S.P.A. o [U] para análisis táctico rápido.",
    chatLog = {},
}

local statusText = "Listo para probar Episodio 0 en el solar trasero del Megaedificio H10."

local function pushChatLog(author, text)
    if type(text) ~= "string" or #text == 0 then
        return
    end
    table.insert(ChispaUI.chatLog, { author = author, text = text })
    if #ChispaUI.chatLog > 40 then
        table.remove(ChispaUI.chatLog, 1)
    end
end

local function withSystem(fn)
    local sys = Game.GetScriptableSystemsContainer():Get("ChispaNC.ChispaSystem")
    if not sys then
        statusText = "Error: ChispaNC.ChispaSystem no esta cargado todavia."
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
        statusText = "Error: carga primero una partida activa antes de entregar el arsenal."
        return
    end
    local player = Game.GetPlayer and Game.GetPlayer() or nil
    if not player then
        statusText = "Error: V aun no esta en el mundo (carga una partida)."
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
    statusText = string.format("Arsenal listo: 7/7 Armas Iconicas (%d nuevas) + Municion + Puentes Smart/Rebote Kiroshi activados.", added)
end

local function sendLiveRequest(action, rawText)
    local clean = tostring(rawText or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if action == "chat" and #clean == 0 then
        return
    end
    ChispaUI.reqId = ChispaUI.reqId + 1
    ChispaUI.lastReqSentAt = os.clock()
    if action == "chat" then
        pushChatLog("TÚ", clean)
        ChispaUI.liveStatus = "Consultando cerebro local de C.H.I.S.P.A..."
    elseif action == "tactical" then
        clean = "[AUTO_SITUACION]"
        pushChatLog("TÚ [TÁCTICO]", "Analiza mi situación actual en Night City.")
        ChispaUI.liveStatus = "Solicitando comentario táctico por Kiroshi..."
    elseif action == "stop" then
        ChispaUI.liveStatus = "Voz en vivo silenciada."
        withSystem(function(sys)
            sys:PushLiveCompanionSubtitle(0, "", 0.0)
        end)
    end
    LiveIPC.sendRequest(ChispaUI.cetSession, ChispaUI.reqId, action, clean)
end

registerHotkey("chispa_toggle_live_chat", "Abrir Barra Neural HUD (o ventana auxiliar en overlay CET)", function()
    if not ChispaUI.overlayOpen then
        withSystem(function(sys)
            sys:OpenKiroshiPrompt()
        end)
    else
        ChispaUI.showLiveChat = not ChispaUI.showLiveChat
    end
end)

registerHotkey("chispa_quick_tactical_remark", "Pedir comentario táctico en vivo a C.H.I.S.P.A.", function()
    withSystem(function(sys)
        sys:TriggerQuickTacticalRemark()
    end)
end)

registerHotkey("chispa_stop_live_voice", "Silenciar voz en vivo de C.H.I.S.P.A.", function()
    sendLiveRequest("stop", "")
end)

registerHotkey("chispa_toggle_panel", "Mostrar/Ocultar panel de depuracion CHISPA (Ep. 0-5)", function()
    ChispaUI.showPanel = not ChispaUI.showPanel
end)

registerHotkey("chispa_grant_iconic_arsenal", "Entregar las 7 Armas Iconicas + Municion (Showcase)", function()
    grantShowcaseArsenal()
end)

registerForEvent("onInit", function()
    math.randomseed(os.time())
    ChispaUI.cetSession = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    pushChatLog("SISTEMA", "Enlace Kiroshi nativo listo ([Y] Escribir / [U] Análisis táctico).")
    print("[ChispaNC] Barra Neural HUD + Puente IPC en Vivo inicializados.")
end)

registerForEvent("onOverlayOpen", function()
    ChispaUI.overlayOpen = true
    withSystem(function(sys)
        sys:SetCetOverlayOpen(true)
    end)
end)

registerForEvent("onOverlayClose", function()
    ChispaUI.overlayOpen = false
    withSystem(function(sys)
        sys:SetCetOverlayOpen(false)
    end)
end)

registerForEvent("onUpdate", function(delta)
    ChispaUI.fastGateTimer = ChispaUI.fastGateTimer + delta
    if ChispaUI.fastGateTimer < 0.06 then
        return
    end
    local step = ChispaUI.fastGateTimer
    ChispaUI.fastGateTimer = 0.0

    if not Game or not Game.GetScriptableSystemsContainer then
        return
    end
    local sys = Game.GetScriptableSystemsContainer():Get("ChispaNC.ChispaSystem")
    if not sys then
        return
    end

    -- Drenar peticiones originadas en la Barra Neural nativa del HUD de forma instantánea
    local pendingSeq = tonumber(sys:GetPendingLiveReqSeq()) or 0
    if pendingSeq < ChispaUI.lastFlushedNativeSeq then
        ChispaUI.lastFlushedNativeSeq = 0
    end
    if pendingSeq > ChispaUI.lastFlushedNativeSeq then
        ChispaUI.lastFlushedNativeSeq = pendingSeq
        ChispaUI.telemetryTimer = 0.0
        LiveIPC.writeState(sys:ExportLiveStateJson(), true)
        sendLiveRequest(sys:GetPendingLiveReqAction(), sys:GetPendingLiveReqText())
    end

    local inMenu = sys:IsInSystemOrPauseMenu()
    local isBusy = sys:IsLiveCompanionBusy()

    ChispaUI.telemetryTimer = ChispaUI.telemetryTimer + step
    local telePeriod = inMenu and 1.20 or 0.50
    if ChispaUI.telemetryTimer >= telePeriod then
        ChispaUI.telemetryTimer = 0.0
        LiveIPC.writeState(sys:ExportLiveStateJson(), false)
    end

    if ChispaUI.daemonOnline then
        ChispaUI.inboxTimer = ChispaUI.inboxTimer + step
        local awaitingReply = isBusy or ((os.clock() - ChispaUI.lastReqSentAt) < 5.0)
        local inboxPeriod = awaitingReply and 0.08 or (inMenu and 1.20 or 0.40)
        if ChispaUI.inboxTimer >= inboxPeriod then
            ChispaUI.inboxTimer = 0.0
            local pkt = LiveIPC.readInbox()
            if pkt and pkt.session_id and pkt.msg_id then
                if tostring(pkt.session_id) ~= ChispaUI.lastInboxSession then
                    ChispaUI.lastInboxSession = tostring(pkt.session_id)
                    ChispaUI.lastInboxMsgId = 0
                    ChispaUI.lastReplySeq = 0
                end
                local msgId = tonumber(pkt.msg_id) or 0
                if msgId > ChispaUI.lastInboxMsgId then
                    ChispaUI.lastInboxMsgId = msgId
                    local st = tonumber(pkt.state) or 0
                    local sub = tostring(pkt.subtitle or "")
                    local dur = tonumber(pkt.duration) or 4.0
                    sys:PushLiveCompanionSubtitle(st, sub, dur)
                    if st == 0 then
                        ChispaUI.liveStatus = "Listo — pulsa [Y] en el juego o [U] para análisis táctico."
                    elseif #sub > 0 then
                        ChispaUI.liveStatus = "C.H.I.S.P.A. hablando en directo..."
                    end
                    local rSeq = tonumber(pkt.reply_seq) or 0
                    local fullReply = tostring(pkt.full_reply or "")
                    if rSeq > ChispaUI.lastReplySeq and #fullReply > 0 then
                        ChispaUI.lastReplySeq = rSeq
                        pushChatLog("C.H.I.S.P.A.", fullReply)
                    end
                end
            end
        end
    end

    ChispaUI.heartbeatTimer = ChispaUI.heartbeatTimer + step
    if ChispaUI.heartbeatTimer >= 2.50 then
        ChispaUI.heartbeatTimer = 0.0
        local hb = LiveIPC.readHeartbeat()
        if hb and hb.ts and math.abs(os.time() - (tonumber(hb.ts) or 0)) <= 6 then
            ChispaUI.daemonOnline = true
            ChispaUI.daemonInfo = string.format(
                "IA Local EN LÍNEA | Cerebro: %s | Voz: %s | Salida: %s",
                tostring(hb.llm or "gemma3:4b"),
                tostring(hb.tts or "f5_clone"),
                tostring(hb.speaker or "WASAPI")
            )
        else
            ChispaUI.daemonOnline = false
            ChispaUI.daemonInfo = "IA local desconectada — abre sparky_local_service/iniciar_servicio_chispa.bat"
        end
        sys:SetLiveDaemonOnline(ChispaUI.daemonOnline)
        pcall(function()
            sys:SetLiveVk186Acute(hb and hb.vk186_acute == true or false)
        end)
    end
end)

local function drawLiveChatWindow()
    if not ChispaUI.showLiveChat then
        return
    end
    local cond = ImGuiCond and ImGuiCond.FirstUseEver or 4
    ImGui.SetNextWindowSize(560, 420, cond)
    local open, keepOpen = ImGui.Begin("C.H.I.S.P.A. v2.0 — Enlace Kiroshi en Vivo", ChispaUI.showLiveChat)
    if keepOpen == false then
        ChispaUI.showLiveChat = false
    end
    if open then
        if ChispaUI.daemonOnline then
            ImGui.TextColored(0.22, 1.0, 0.53, 1.0, ChispaUI.daemonInfo)
        else
            ImGui.TextColored(1.0, 0.55, 0.25, 1.0, ChispaUI.daemonInfo)
        end
        ImGui.Separator()

        if ImGui.BeginChild("##chispa_live_history", 0, -96, true) then
            for _, entry in ipairs(ChispaUI.chatLog) do
                if entry.author == "C.H.I.S.P.A." then
                    ImGui.TextColored(0.99, 0.93, 0.04, 1.0, entry.author .. ":")
                elseif entry.author == "SISTEMA" then
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
        local newText, enterPressed = ImGui.InputText("##chispa_chat_input", ChispaUI.inputText, 512, flags)
        ChispaUI.inputText = newText or ""
        if enterPressed and #ChispaUI.inputText > 0 then
            sendLiveRequest("chat", ChispaUI.inputText)
            ChispaUI.inputText = ""
        end

        if ImGui.Button("Enviar") then
            if #ChispaUI.inputText > 0 then
                sendLiveRequest("chat", ChispaUI.inputText)
                ChispaUI.inputText = ""
            end
        end
        ImGui.SameLine()
        if ImGui.Button("Comentario Táctico") then
            sendLiveRequest("tactical", "[AUTO_SITUACION]")
        end
        ImGui.SameLine()
        if ImGui.Button("Callar") then
            sendLiveRequest("stop", "")
        end
        ImGui.SameLine()
        if ImGui.Button("Limpiar") then
            ChispaUI.chatLog = {}
        end
        ImGui.SameLine()
        if ImGui.Button(ChispaUI.showPanel and "Ocultar Ep.0-5" or "Panel Ep.0-5") then
            ChispaUI.showPanel = not ChispaUI.showPanel
        end

        ImGui.TextWrapped(ChispaUI.liveStatus)
    end
    ImGui.End()
end

registerForEvent("onDraw", function()
    if not ChispaUI.overlayOpen then
        return
    end

    drawLiveChatWindow()

    if not ChispaUI.showPanel then
        return
    end

    local open, keepOpen = ImGui.Begin("Protocolo CHISPA — Estudio CET", ChispaUI.showPanel, ImGuiWindowFlags.AlwaysAutoResize)
    if keepOpen == false then
        ChispaUI.showPanel = false
    end
    if open then
        ImGui.Text("C.H.I.S.P.A. v0.98b — Guia Callejera de Night City (Temporada 1 Completa: Ep. 0–5)")
        ImGui.Separator()

        if ImGui.Button("Entregar las 7 Armas Iconicas + Municion (Showcase)") then
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
            local vmode = qs:GetFact("chispa_videocall_disabled") == 0 and "VIDEOCALL" or "SOLO AUDIO"
            ImGui.Text(string.format("Ep00 Stage: %d | Scan: %d | Trap: %d | Done: %d | Llamada: %s",
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

        if ImGui.Button("Repetir videollamada Ep. 0") then
            withSystem(function(sys)
                sys:ReplayEp00Call()
                statusText = "Videollamada inicial de CHISPA lanzada."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Alternar Videocall / Solo Audio") then
            withSystem(function(sys)
                local enabled = sys:IsVideocallModeEnabled()
                sys:SetVideocallModeEnabled(not enabled)
                statusText = (not enabled) and "Modo Videollamada Holografica activado." or "Modo Solo Audio activado."
            end)
        end

        if ImGui.Button("Ir al solar trasero H10 (Ep. 0)") then
            withSystem(function(sys)
                sys:TeleportToEp00Alley()
                statusText = "Teletransportado a la entrada del solar trasero de H10."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Sobrecargar condensador (test)") then
            withSystem(function(sys)
                sys:TriggerEp00CapacitorOverload()
                statusText = "Condensador sobrecargado manualmente."
            end)
        end

        if ImGui.Button("Reiniciar Episodio 0 completo") then
            withSystem(function(sys)
                sys:ResetAllState()
                statusText = "Episodio 0 reiniciado desde cero."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Desbloquear Watson (Pruebas)") then
            withSystem(function(sys)
                sys:UnlockFullNightCityMap()
                statusText = "Bloqueo policial de Watson eliminado."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Pruebas rapidas — Episodio 1: Fantasmas en la Camara (Kabuki)")

        if ImGui.Button("Saltar a Ep. 1") then
            withSystem(function(sys)
                sys:StartEp01Directly()
                statusText = "Episodio 1 iniciado (Ep. 0 marcado como completado)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Ir a Kabuki Creek (Ep. 1)") then
            withSystem(function(sys)
                sys:TeleportToEp01Kabuki()
                statusText = "Teletransportado al paseo fluvial de Kabuki Creek (Ep. 1)."
            end)
        end

        if ImGui.Button("Sobrecargar subred Ep. 1") then
            withSystem(function(sys)
                sys:TriggerEp01RelaySurge()
                statusText = "Repetidor RABIDS y servidor de Kabuki sobrecargados."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reiniciar solo Ep. 1") then
            withSystem(function(sys)
                sys:ResetEp01Only()
                statusText = "Episodio 1 reiniciado limpiamente."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Pruebas rapidas — Episodio 2: Mas Hierro que Carne (Northside)")

        if ImGui.Button("Saltar a Ep. 2") then
            withSystem(function(sys)
                sys:StartEp02Directly()
                statusText = "Episodio 2 iniciado (Ep. 0 + Ep. 1 marcados como completados)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Ir a Northside (Ep. 2)") then
            withSystem(function(sys)
                sys:TeleportToEp02Northside()
                statusText = "Teletransportado a los muelles industriales de Northside (Ep. 2)."
            end)
        end

        if ImGui.Button("Purgar CHOOH2 Ep. 2") then
            withSystem(function(sys)
                sys:TriggerEp02RegulatorSurge()
                statusText = "Regulador de presion y deposito CHOOH2 detonados."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reiniciar solo Ep. 2") then
            withSystem(function(sys)
                sys:ResetEp02Only()
                statusText = "Episodio 2 reiniciado limpiamente."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Pruebas rapidas — Episodio 3: Balas que Doblan Esquinas (Muelle Sur)")

        if ImGui.Button("Saltar a Ep. 3") then
            withSystem(function(sys)
                sys:StartEp03Directly()
                statusText = "Episodio 3 iniciado (Ep. 0 + Ep. 1 + Ep. 2 completados)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Ir al Muelle Sur (Ep. 3)") then
            withSystem(function(sys)
                sys:TeleportToEp03Waterfront()
                statusText = "Teletransportado al muelle sur de Watson Waterfront (Ep. 3)."
            end)
        end

        if ImGui.Button("Invertir Inhibidor Ep. 3") then
            withSystem(function(sys)
                sys:TriggerEp03JammerSurge()
                statusText = "Baliza inhibidora IFF invertida y antena explosiva detonada."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reiniciar solo Ep. 3") then
            withSystem(function(sys)
                sys:ResetEp03Only()
                statusText = "Episodio 3 reiniciado limpiamente."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Pruebas rapidas — Episodio 4: Honor, Chatarra y Patriotas (Arroyo)")

        if ImGui.Button("Saltar a Ep. 4") then
            withSystem(function(sys)
                sys:StartEp04Directly()
                statusText = "Episodio 4 iniciado (Watson desbloqueado y Ep. 0–3 completados)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Ir a Frontera Arroyo (Ep. 4)") then
            withSystem(function(sys)
                sys:TeleportToEp04Border()
                statusText = "Teletransportado al patio de contrabando de Arroyo (Ep. 4)."
            end)
        end

        if ImGui.Button("Volar Alijo NUSA Ep. 4") then
            withSystem(function(sys)
                sys:TriggerEp04CacheSurge()
                statusText = "Rele balistico sobrecargado y deposito NUSA detonado."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reiniciar solo Ep. 4") then
            withSystem(function(sys)
                sys:ResetEp04Only()
                statusText = "Episodio 4 reiniciado limpiamente."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Pruebas rapidas — Episodio 5: Mas Alla del Muro Negro (Pacifica)")

        if ImGui.Button("Saltar a Ep. 5") then
            withSystem(function(sys)
                sys:StartEp05Directly()
                statusText = "Episodio 5 iniciado (Ep. 0–4 completados)."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Ir a Pacifica (Ep. 5)") then
            withSystem(function(sys)
                sys:TeleportToEp05Pacifica()
                statusText = "Teletransportado a Coastview, Pacifica (Ep. 5)."
            end)
        end

        if ImGui.Button("Purgar Hielo Negro Ep. 5") then
            withSystem(function(sys)
                sys:TriggerEp05ContainmentPurge()
                statusText = "Baliza de contencion NetWatch purgada sobre el servidor criogenico."
            end)
        end
        ImGui.SameLine()
        if ImGui.Button("Reiniciar solo Ep. 5") then
            withSystem(function(sys)
                sys:ResetEp05Only()
                statusText = "Episodio 5 reiniciado limpiamente."
            end)
        end

        ImGui.Separator()
        ImGui.Text("Enlace Neural v2.0: [Y] Barra Kiroshi HUD | [U] Comentario tactico rapido")
        if Game and Game.GetQuestsSystem then
            local qs = Game.GetQuestsSystem()
            local keysDisabled = qs:GetFact("chispa_disable_default_yu_keys") > 0
            local lbl = keysDisabled and "Reactivar teclas [Y]/[U] de serie" or "Desactivar teclas [Y]/[U] (usar solo Binding CET)"
            if ImGui.Button(lbl) then
                qs:SetFact("chispa_disable_default_yu_keys", keysDisabled and 0 or 1)
                statusText = keysDisabled and "Teclas nativas [Y]/[U] reactivadas." or "Teclas [Y]/[U] desactivadas; asigna tu tecla en CET Bindings."
            end
            ImGui.SameLine()
        end
        if ImGui.Button(ChispaUI.showLiveChat and "Ocultar registro chat CET" or "Ver registro chat CET") then
            ChispaUI.showLiveChat = not ChispaUI.showLiveChat
        end

        ImGui.Separator()
        ImGui.TextWrapped(statusText)
    end
    ImGui.End()
end)
