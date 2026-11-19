-- Protocolo CHISPA / SPARKY Protocol — CET Study & Test Panel (Episodio 0+)

local ChispaUI = {
    overlayOpen = false,
    showPanel = false,
}

local statusText = "Listo para probar Episodio 0 en el solar trasero del Megaedificio H10."

local function withSystem(fn)
    local sys = Game.GetScriptableSystemsContainer():Get("ChispaNC.ChispaSystem")
    if not sys then
        statusText = "Error: ChispaNC.ChispaSystem no esta cargado todavia."
        return
    end
    fn(sys)
end

registerHotkey("chispa_toggle_panel", "Mostrar/Ocultar panel de depuracion CHISPA", function()
    ChispaUI.showPanel = not ChispaUI.showPanel
end)

registerForEvent("onInit", function()
    print("[ChispaNC] CET Panel inicializado (oculto por defecto).")
end)

registerForEvent("onOverlayOpen", function()
    ChispaUI.overlayOpen = true
end)

registerForEvent("onOverlayClose", function()
    ChispaUI.overlayOpen = false
end)

registerForEvent("onDraw", function()
    if not ChispaUI.overlayOpen or not ChispaUI.showPanel then
        return
    end

    local open, keepOpen = ImGui.Begin("Protocolo CHISPA — Estudio CET", ChispaUI.showPanel, ImGuiWindowFlags.AlwaysAutoResize)
    if keepOpen == false then
        ChispaUI.showPanel = false
    end
    if open then
        ImGui.Text("C.H.I.S.P.A. v0.98b — Guia Callejera de Night City (Temporada 1 Completa: Ep. 0–5)")
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
        ImGui.TextWrapped(statusText)
    end
    ImGui.End()
end)
