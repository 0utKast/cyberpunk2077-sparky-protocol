-- SPARKY Protocol — CET Study & Test Panel (English Edition, Season 1: Episodes 0–5)

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
