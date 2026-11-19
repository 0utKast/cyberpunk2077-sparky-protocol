// Protocolo CHISPA / SPARKY Protocol — Episodio 1: «Fantasmas en la Cámara»
module ChispaNC

public class ChispaEp01Handler {
    private let m_sys: wref<ChispaSystem>;
    private let m_spawned: Bool;

    // Entidades estáticas y de seguridad (Kabuki Creek Promenade)
    private let m_mast01Id: EntityID;
    private let m_mast02Id: EntityID;
    private let m_cam01Id: EntityID;
    private let m_cam02Id: EntityID;
    private let m_relayId: EntityID;
    private let m_serverId: EntityID;
    private let m_terminalId: EntityID;
    private let m_sectorId: EntityID;
    private let m_cam01Configured: Bool;
    private let m_cam02Configured: Bool;
    private let m_serverConfigured: Bool;

    // Escuadra Carroñera
    private let m_kostyaId: EntityID;
    private let m_vadikId: EntityID;
    private let m_zinaId: EntityID;
    private let m_kostyaReady: Bool;
    private let m_vadikReady: Bool;
    private let m_zinaReady: Bool;

    // Cola de locuciones no solapadas y posiciones reales sobre suelo
    private let m_pendingCamBark: Bool;
    private let m_pendingPingBark: Bool;
    private let m_pendingSubnetBoom: Bool;
    private let m_pendingNetVictory: Bool;
    private let m_pendingGunsBlazing: Bool;
    private let m_terminalPos: Vector4;
    private let m_relayPos: Vector4;
    private let m_serverPos: Vector4;
    private let m_combatStartedAt: Float;
    private let m_introWaitTicks: Int32;

    public final func Init(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
        this.ResetRuntimeFlags();
    }

    public final func GetArrivalPos() -> Vector4 = new Vector4(-994.50, 1622.50, 2.52, 1.00);
    public final func GetMast01Pos() -> Vector4 = new Vector4(-986.20, 1620.20, 2.50, 1.00);
    public final func GetMast02Pos() -> Vector4 = new Vector4(-977.20, 1633.80, 2.50, 1.00);
    public final func GetRelayPos() -> Vector4 = new Vector4(-983.80, 1625.60, 2.50, 1.00);
    public final func GetServerPos() -> Vector4 = new Vector4(-980.40, 1629.40, 2.50, 1.00);
    public final func GetTerminalPos() -> Vector4 = new Vector4(-978.40, 1635.20, 2.50, 1.00);

    public final func ResetRuntimeFlags() -> Void {
        this.m_spawned = false;
        this.m_mast01Id = new EntityID();
        this.m_mast02Id = new EntityID();
        this.m_cam01Id = new EntityID();
        this.m_cam02Id = new EntityID();
        this.m_relayId = new EntityID();
        this.m_serverId = new EntityID();
        this.m_terminalId = new EntityID();
        this.m_sectorId = new EntityID();
        this.m_cam01Configured = false;
        this.m_cam02Configured = false;
        this.m_serverConfigured = false;
        this.m_kostyaId = new EntityID();
        this.m_vadikId = new EntityID();
        this.m_zinaId = new EntityID();
        this.m_kostyaReady = false;
        this.m_vadikReady = false;
        this.m_zinaReady = false;
        this.m_pendingCamBark = false;
        this.m_pendingPingBark = false;
        this.m_pendingSubnetBoom = false;
        this.m_pendingNetVictory = false;
        this.m_pendingGunsBlazing = false;
        this.m_terminalPos = this.GetTerminalPos();
        this.m_relayPos = this.GetRelayPos();
        this.m_serverPos = this.GetServerPos();
        this.m_combatStartedAt = 0.00;
        this.m_introWaitTicks = 0;
    }

    private final func AllPinPaths() -> array<String> {
        return [
            "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/mp_ep01_kabuki",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/mp_ep01_terminal"
        ];
    }

    public final func CleanupEntities() -> Void {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) {
            des.DeleteTagged(n"ChispaEp01Kostya");
            des.DeleteTagged(n"ChispaEp01Vadik");
            des.DeleteTagged(n"ChispaEp01Zina");
        }
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp01Mast01");
            ses.DespawnTagged(n"ChispaEp01Mast02");
            ses.DespawnTagged(n"ChispaEp01Cam01");
            ses.DespawnTagged(n"ChispaEp01Cam02");
            ses.DespawnTagged(n"ChispaEp01Relay");
            ses.DespawnTagged(n"ChispaEp01Server");
            ses.DespawnTagged(n"ChispaEp01Terminal");
            ses.DespawnTagged(n"ChispaEp01Sector");
        }
        this.ResetRuntimeFlags();
    }

    public final func ResetJournalAndFacts() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);

        this.m_sys.DeactivateJournalPinList(this.AllPinPaths());

        let descPaths: array<String> = [
            "quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms/desc_ep01_01",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/desc_ep01_02",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/desc_ep01_03",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk/desc_ep01_04",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/desc_ep01_done"
        ];
        for dp in descPaths {
            jm.ChangeEntryState(dp, "gameJournalQuestDescription", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        let objPaths: array<String> = [
            "quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk"
        ];
        for op in objPaths {
            jm.ChangeEntryState(op, "gameJournalQuestObjective", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01", "gameJournalQuestPhase", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest", "gameJournalQuest", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        let smsPaths: array<String> = [
            "contacts/chispa_ai/conv_ep01/msg_ep01_hook",
            "contacts/chispa_ai/conv_ep01/msg_ep01_ghost",
            "contacts/chispa_ai/conv_ep01/msg_ep01_scavs",
            "contacts/chispa_ai/conv_ep01/msg_ep01_summary"
        ];
        for sp in smsPaths {
            jm.ChangeEntryState(sp, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/choices_ep01/reply_ep01_ghost", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/choices_ep01/reply_ep01_scavs", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/choices_ep01", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01", "gameJournalPhoneConversation", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep01", "gameJournalOnscreen", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        qs.SetFact(n"chispa_ep01_call_done", 0);
        qs.SetFact(n"chispa_ep01_sms_replied", 0);
        qs.SetFact(n"chispa_ep01_approach_played", 0);
        qs.SetFact(n"chispa_ep01_cam_hijacked", 0);
        qs.SetFact(n"chispa_ep01_ping_used", 0);
        qs.SetFact(n"chispa_ep01_scanned", 0);
        qs.SetFact(n"chispa_ep01_used_netrun", 0);
        qs.SetFact(n"chispa_ep01_relay_surged", 0);
        qs.SetFact(n"chispa_ep01_server_blown", 0);
        qs.SetFact(n"chispa_ep01_combat_started", 0);
        qs.SetFact(n"chispa_ep01_asked_bartmoss", 0);
        qs.SetFact(n"chispa_ep01_asked_krash", 0);
        qs.SetFact(n"chispa_ep01_asked_blackwall", 0);
        qs.SetFact(n"chispa_ep01_done", 0);
        qs.SetFact(n"chispa_ep01_stage", 0);
    }

    // --- Callbacks de Audio, Llamadas y SMS ---

    public final func GetCallSteps(stageTag: Int32, out completeAction: Int32) -> array<ref<ChispaSpeechStep>> {
        let steps: array<ref<ChispaSpeechStep>>;
        if !IsDefined(this.m_sys) || stageTag != 11 {
            return steps;
        }
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_call_01", n"phone", n"CHISPA", scnDialogLineType.Holocall, 14.19));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_v_call_01", n"player", n"V", scnDialogLineType.Regular, 6.90));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_call_02", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.61));
        completeAction = 201;
        return steps;
    }

    public final func OnCallRejected(stageTag: Int32) -> Void {
        if IsDefined(this.m_sys) && stageTag == 11 {
            GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance()).SetFact(n"chispa_ep01_call_done", 1);
            this.ActivateIntroSms();
        }
    }

    public final func OnPostSpeech(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if actionId == 201 {
            qs.SetFact(n"chispa_ep01_call_done", 1);
            this.m_sys.EndCustomCall(n"chispa_ai", this.m_sys.m_activeCallIsVideo);
            this.ActivateIntroSms();
            return;
        }
        if actionId == 209 || actionId == 210 || actionId == 211 || actionId == 212 {
            if qs.GetFact(n"chispa_ep01_stage") == 4 && !this.m_sys.IsUiBlockingWorldInput() {
                this.ShowDialogHub();
            }
            return;
        }
        if actionId == 220 {
            this.CompleteEpisode();
            return;
        }
    }

    public final func ActivateJournalQuest() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.m_sys.GetGameInstance());
        if !IsDefined(jm) {
            return;
        }
        let qEntry: wref<JournalEntry> = jm.GetEntryByString("quests/side_quest/chispa_ep01_quest", "gameJournalQuest");
        if !IsDefined(qEntry) {
            return;
        }
        let qState: gameJournalEntryState = jm.GetEntryState(qEntry);
        if Equals(qState, gameJournalEntryState.Active) || Equals(qState, gameJournalEntryState.Succeeded) {
            return;
        }
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest", "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01", "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms/desc_ep01_01", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        if !IsDefined(jm.GetTrackedEntry()) {
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms");
        }
    }

    public final func ActivateIntroSms() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.m_sys.GetGameInstance());
        if !IsDefined(jm) {
            return;
        }
        let msgEntry: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep01/msg_ep01_hook", "gameJournalPhoneMessage");
        if IsDefined(msgEntry) && Equals(jm.GetEntryState(msgEntry), gameJournalEntryState.Active) {
            return;
        }
        jm.ChangeEntryState("contacts/chispa_ai", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01", "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/msg_ep01_hook", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/choices_ep01", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/choices_ep01/reply_ep01_ghost", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/choices_ep01/reply_ep01_scavs", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    }

    public final func CheckSmsReply() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(jm) || qs.GetFact(n"chispa_ep01_stage") != 1 || qs.GetFact(n"chispa_ep01_sms_replied") > 0 {
            return;
        }
        let rGhost: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep01/choices_ep01/reply_ep01_ghost", "gameJournalPhoneChoiceEntry");
        let rScavs: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep01/choices_ep01/reply_ep01_scavs", "gameJournalPhoneChoiceEntry");

        let replyKind: Int32 = 0;
        if IsDefined(rGhost) && Equals(jm.GetEntryState(rGhost), gameJournalEntryState.Succeeded) {
            replyKind = 11;
        } else if IsDefined(rScavs) && Equals(jm.GetEntryState(rScavs), gameJournalEntryState.Succeeded) {
            replyKind = 12;
        }
        if replyKind == 0 {
            return;
        }

        qs.SetFact(n"chispa_ep01_sms_replied", replyKind);
        let cb: ref<ChispaSmsDelayCallback> = new ChispaSmsDelayCallback();
        cb.system = this.m_sys;
        cb.actionId = replyKind;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.90, false);
    }

    private final func GrantStarterPingQuickhack(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        if !IsDefined(ts) || !IsDefined(player) {
            return;
        }
        let hasPing: Bool = ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.PingProgram")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.PingLvl2Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.PingLvl3Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.PingLvl4Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.PingLvl4PlusPlusProgram")) > 0;
        if !hasPing {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.PingProgram"), 1);
            this.m_sys.ShowRelicBanner(n"ch_banner_ep01_ping_gift", "[CHISPA] ¡Daemon Ping instalado! Ruta a Kabuki Creek activa");
        }
    }

    public final func OnDelayedSmsAction(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if actionId == 11 {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/msg_ep01_ghost", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        } else {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/msg_ep01_scavs", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        }
        this.GrantStarterPingQuickhack(player);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        this.m_sys.ActivateObjectiveWithPin(
            12,
            "quests/side_quest/chispa_ep01_quest",
            "quests/side_quest/chispa_ep01_quest/phase_ep01",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/mp_ep01_kabuki",
            "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/desc_ep01_02",
            this.AllPinPaths(),
            true
        );
        qs.SetFact(n"chispa_ep01_stage", 2);
    }

    // --- Escena Netrunner del Paseo Fluvial de Kabuki Creek ---

    private final func EnsureSpawned(player: ref<PlayerPuppet>) -> Void {
        let mast01Base: Vector4 = this.GetMast01Pos();
        let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), mast01Base);
        if distSq > 4225.00 {
            return;
        }

        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep01_stage");
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();

        if IsDefined(ses) && ses.IsReady() {
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_mast01Id) {
                ses.DespawnTagged(n"ChispaEp01Mast01");
                let zM1: Float = this.m_sys.FindGroundZ(mast01Base);
                let pM1: Vector4 = new Vector4(mast01Base.X, mast01Base.Y, zM1, 1.00);
                this.m_mast01Id = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep01_cam_mast.ent", n"", pM1, 0.00, 35.00, n"ChispaEp01Mast01");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_cam01Id) {
                ses.DespawnTagged(n"ChispaEp01Cam01");
                this.m_cam01Configured = false;
                let zC1: Float = this.m_sys.FindGroundZ(mast01Base);
                let pC1: Vector4 = new Vector4(mast01Base.X, mast01Base.Y, zC1 + 2.75, 1.00);
                this.m_cam01Id = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\security_systems\\surveillance_cameras\\surveillance_camera.ent", n"appearances_camera_wall_old", pC1, -18.00, 35.00, n"ChispaEp01Cam01");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_mast02Id) {
                ses.DespawnTagged(n"ChispaEp01Mast02");
                let m2Base: Vector4 = this.GetMast02Pos();
                let zM2: Float = this.m_sys.FindGroundZ(m2Base);
                let pM2: Vector4 = new Vector4(m2Base.X, m2Base.Y, zM2, 1.00);
                this.m_mast02Id = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep01_cam_mast.ent", n"", pM2, 0.00, -145.00, n"ChispaEp01Mast02");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_cam02Id) {
                ses.DespawnTagged(n"ChispaEp01Cam02");
                this.m_cam02Configured = false;
                let m2Base: Vector4 = this.GetMast02Pos();
                let zC2: Float = this.m_sys.FindGroundZ(m2Base);
                let pC2: Vector4 = new Vector4(m2Base.X, m2Base.Y, zC2 + 2.75, 1.00);
                this.m_cam02Id = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\security_systems\\surveillance_cameras\\surveillance_camera.ent", n"appearances_camera_wall_old", pC2, -20.00, -145.00, n"ChispaEp01Cam02");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_terminalId) {
                ses.DespawnTagged(n"ChispaEp01Terminal");
                let termBase: Vector4 = this.GetTerminalPos();
                let zTerm: Float = this.m_sys.FindGroundZ(termBase);
                this.m_terminalPos = new Vector4(termBase.X, termBase.Y, zTerm, 1.00);
                this.m_terminalId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep01_entropy_terminal.ent", n"", this.m_terminalPos, 0.00, -140.00, n"ChispaEp01Terminal");
            }
            if (stage == 2 || stage == 3) && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_sectorId) {
                ses.DespawnTagged(n"ChispaEp01Sector");
                let termBase: Vector4 = this.GetTerminalPos();
                let zTerm: Float = this.m_sys.FindGroundZ(termBase);
                this.m_terminalPos = new Vector4(termBase.X, termBase.Y, zTerm, 1.00);
                this.m_sectorId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep01_sector_module.ent", n"", this.m_terminalPos, 0.00, -140.00, n"ChispaEp01Sector");
            }
            if qs.GetFact(n"chispa_ep01_relay_surged") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_relayId) {
                ses.DespawnTagged(n"ChispaEp01Relay");
                let relBase: Vector4 = this.GetRelayPos();
                let zRel: Float = this.m_sys.FindGroundZ(relBase);
                this.m_relayPos = new Vector4(relBase.X, relBase.Y, zRel, 1.00);
                this.m_relayId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep01_relay_node.ent", n"", this.m_relayPos, 0.00, -135.00, n"ChispaEp01Relay");
            }
            if qs.GetFact(n"chispa_ep01_server_blown") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_serverId) {
                ses.DespawnTagged(n"ChispaEp01Server");
                this.m_serverConfigured = false;
                let srvBase: Vector4 = this.GetServerPos();
                let zSrv: Float = this.m_sys.FindGroundZ(srvBase);
                this.m_serverPos = new Vector4(srvBase.X, srvBase.Y, zSrv, 1.00);
                this.m_serverId = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\explosives\\explosive_server.ent", n"explosive_server_appearance_entropy", this.m_serverPos, 0.00, -120.00, n"ChispaEp01Server");
            }

            if !this.m_cam01Configured && EntityID.IsDefined(this.m_cam01Id) && ses.IsSpawned(this.m_cam01Id) {
                let cam1: ref<SurveillanceCamera> = GameInstance.FindEntityByID(game, this.m_cam01Id) as SurveillanceCamera;
                if IsDefined(cam1) && IsDefined(cam1.GetDevicePS()) {
                    cam1.GetDevicePS().ChispaConfigureSecurityCamera();
                    this.m_cam01Configured = true;
                }
            }
            if !this.m_cam02Configured && EntityID.IsDefined(this.m_cam02Id) && ses.IsSpawned(this.m_cam02Id) {
                let cam2: ref<SurveillanceCamera> = GameInstance.FindEntityByID(game, this.m_cam02Id) as SurveillanceCamera;
                if IsDefined(cam2) && IsDefined(cam2.GetDevicePS()) {
                    cam2.GetDevicePS().ChispaConfigureSecurityCamera();
                    this.m_cam02Configured = true;
                }
            }
            if !this.m_serverConfigured && EntityID.IsDefined(this.m_serverId) && ses.IsSpawned(this.m_serverId) {
                let srv: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_serverId) as ExplosiveDevice;
                if IsDefined(srv) && IsDefined(srv.GetDevicePS()) {
                    srv.GetDevicePS().ChispaConfigureExplosiveServer();
                    this.m_serverConfigured = true;
                }
            }
        }

        if stage == 2 {
            let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
            if IsDefined(des) && des.IsReady() {
                if !EntityID.IsDefined(this.m_kostyaId) && !this.m_sys.IsDynamicEntityAliveOrSpawning(this.m_kostyaId) {
                    des.DeleteTagged(n"ChispaEp01Kostya");
                    des.DeleteTagged(n"ChispaEp01Vadik");
                    des.DeleteTagged(n"ChispaEp01Zina");

                    let kXY: Vector4 = new Vector4(-980.90, 1630.60, mast01Base.Z, 1.00);
                    let vXY: Vector4 = new Vector4(-982.80, 1627.40, mast01Base.Z, 1.00);
                    let zXY: Vector4 = new Vector4(-979.20, 1626.80, mast01Base.Z, 1.00);
                    let zK: Float = this.m_sys.FindGroundZ(kXY);
                    let zV: Float = this.m_sys.FindGroundZ(vXY);
                    let zZ: Float = this.m_sys.FindGroundZ(zXY);

                    this.m_kostyaReady = false;
                    this.m_vadikReady = false;
                    this.m_zinaReady = false;
                    this.m_kostyaId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep01_Kostya", new Vector4(kXY.X, kXY.Y, zK, 1.00), -135.00, n"ChispaEp01Kostya");
                    this.m_vadikId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep01_Vadik", new Vector4(vXY.X, vXY.Y, zV, 1.00), -150.00, n"ChispaEp01Vadik");
                    this.m_zinaId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep01_Zina", new Vector4(zXY.X, zXY.Y, zZ, 1.00), 175.00, n"ChispaEp01Zina");
                }
                if !this.m_kostyaReady && EntityID.IsDefined(this.m_kostyaId) && des.IsSpawned(this.m_kostyaId) {
                    let kNpc: ref<NPCPuppet> = des.GetEntity(this.m_kostyaId) as NPCPuppet;
                    if IsDefined(kNpc) && ScriptedPuppet.IsActive(kNpc) {
                        this.m_kostyaReady = true;
                    }
                }
                if !this.m_vadikReady && EntityID.IsDefined(this.m_vadikId) && des.IsSpawned(this.m_vadikId) {
                    let vNpc: ref<NPCPuppet> = des.GetEntity(this.m_vadikId) as NPCPuppet;
                    if IsDefined(vNpc) && ScriptedPuppet.IsActive(vNpc) {
                        this.m_vadikReady = true;
                    }
                }
                if !this.m_zinaReady && EntityID.IsDefined(this.m_zinaId) && des.IsSpawned(this.m_zinaId) {
                    let zNpc: ref<NPCPuppet> = des.GetEntity(this.m_zinaId) as NPCPuppet;
                    if IsDefined(zNpc) && ScriptedPuppet.IsActive(zNpc) {
                        this.m_zinaReady = true;
                    }
                }
            }
        }
        this.m_spawned = true;
    }

    // --- Encadenado de Cámaras y Telemetría de Quickhacks ---

    public final func IsEp01Camera(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && (Equals(id, this.m_cam01Id) || Equals(id, this.m_cam02Id));
    }

    public final func IsEp01ExplosiveServer(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && Equals(id, this.m_serverId);
    }

    private final func IsEp01Target(id: EntityID) -> Bool {
        return EntityID.IsDefined(id)
            && (Equals(id, this.m_cam01Id)
                || Equals(id, this.m_cam02Id)
                || Equals(id, this.m_serverId)
                || Equals(id, this.m_kostyaId)
                || Equals(id, this.m_vadikId)
                || Equals(id, this.m_zinaId));
    }

    public final func PopulateEp01CameraChain(activeCamId: EntityID) -> Void {
        if !IsDefined(this.m_sys) || !EntityID.IsDefined(this.m_cam01Id) || !EntityID.IsDefined(this.m_cam02Id) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let chainBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().DeviceTakeControl);
        if !IsDefined(chainBB) {
            return;
        }
        let chain: array<SWidgetPackage>;

        let cd1: ref<ControlledDeviceData> = new ControlledDeviceData();
        cd1.m_isActive = Equals(this.m_cam01Id, activeCamId);
        let p1: SWidgetPackage;
        p1.displayName = this.m_sys.GetLoc(n"ch_cam_ep01_perim", "CAM-01 PERÍMETRO");
        p1.ownerID = CreatePersistentID(this.m_cam01Id, n"controller");
        p1.ownerIDClassName = n"SurveillanceCameraControllerPS";
        p1.customData = cd1;
        p1.libraryID = n"device";
        ArrayPush(chain, p1);

        let cd2: ref<ControlledDeviceData> = new ControlledDeviceData();
        cd2.m_isActive = Equals(this.m_cam02Id, activeCamId);
        let p2: SWidgetPackage;
        p2.displayName = this.m_sys.GetLoc(n"ch_cam_ep01_server", "CAM-02 NODO RABIDS");
        p2.ownerID = CreatePersistentID(this.m_cam02Id, n"controller");
        p2.ownerIDClassName = n"SurveillanceCameraControllerPS";
        p2.customData = cd2;
        p2.libraryID = n"device";
        ArrayPush(chain, p2);

        chainBB.SetVariant(GetAllBlackboardDefs().DeviceTakeControl.DevicesChain, ToVariant(chain));
    }

    private final func ApplyPingHighlights(player: ref<PlayerPuppet>) -> Void {
        if !IsDefined(this.m_sys) || !IsDefined(player) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) {
            let ids: array<EntityID> = [this.m_kostyaId, this.m_vadikId, this.m_zinaId];
            for nid in ids {
                if EntityID.IsDefined(nid) && des.IsSpawned(nid) {
                    let npc: ref<NPCPuppet> = des.GetEntity(nid) as NPCPuppet;
                    if IsDefined(npc) && !npc.IsDead() {
                        StatusEffectHelper.ApplyStatusEffect(npc, t"BaseStatusEffect.PingLvl2MarkStatusEffect", player.GetEntityID());
                    }
                }
            }
        }
        if EntityID.IsDefined(this.m_serverId) {
            let srvObj: ref<GameObject> = GameInstance.FindEntityByID(game, this.m_serverId) as GameObject;
            if IsDefined(srvObj) {
                let hi: ref<FocusForcedHighlightData> = new FocusForcedHighlightData();
                hi.sourceID = player.GetEntityID();
                hi.sourceName = n"ChispaPing";
                hi.highlightType = EFocusForcedHighlightType.BACKDOOR;
                hi.outlineType = EFocusOutlineType.BACKDOOR;
                hi.priority = EPriority.VeryHigh;
                hi.isRevealed = true;
                GameObject.ForceVisionAppearance(srvObj, hi);
            }
        }
    }

    public final func OnTargetScanned(recID: TweakDBID) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep01_stage") != 2 {
            return;
        }
        if qs.GetFact(n"chispa_ep01_scanned") == 0 {
            qs.SetFact(n"chispa_ep01_scanned", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
        }
    }

    public final func OnCameraTakenOver(camId: EntityID, switchedChain: Bool) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep01_stage") != 2 {
            return;
        }
        qs.SetFact(n"chispa_ep01_used_netrun", 1);
        if qs.GetFact(n"chispa_ep01_cam_hijacked") == 0 {
            qs.SetFact(n"chispa_ep01_cam_hijacked", 1);
            this.m_sys.PlaySfx(n"ch_sfx_net_breach");
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingCamBark = true;
            } else {
                this.m_pendingCamBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_cam_hijack", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.53));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
    }

    public final func OnQuickHackApplied(actionOwner: EntityID, actionClassName: CName, objectActionID: TweakDBID) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep01_stage") != 2 || !IsDefined(player) {
            return;
        }
        let nearKabuki: Bool = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), this.GetMast01Pos()) <= 5625.00;
        if !this.IsEp01Target(actionOwner) && !nearKabuki {
            return;
        }
        if Equals(actionClassName, n"ToggleTakeOverControl") || Equals(objectActionID, t"DeviceAction.TakeControlCameraClassHack") {
            qs.SetFact(n"chispa_ep01_used_netrun", 1);
            return;
        }
        let isPing: Bool = Equals(actionClassName, n"PingDevice")
            || Equals(objectActionID, t"QuickHack.PingHack")
            || Equals(objectActionID, t"QuickHack.FreePingHack");
        qs.SetFact(n"chispa_ep01_used_netrun", 1);
        if isPing {
            this.ApplyPingHighlights(player);
        }
        if qs.GetFact(n"chispa_ep01_ping_used") == 0 && (isPing || this.IsEp01Target(actionOwner)) {
            qs.SetFact(n"chispa_ep01_ping_used", 1);
            this.m_sys.PlaySfx(n"ch_sfx_net_breach");
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingPingBark = true;
            } else {
                this.m_pendingPingBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_ping_react", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.36));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        if !isPing && (Equals(actionOwner, this.m_kostyaId) || Equals(actionOwner, this.m_vadikId) || Equals(actionOwner, this.m_zinaId)) {
            this.OnScavsProvoked(player, true);
        }
    }

    public final func OnExplosiveServerOverloaded() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep01_stage") != 2 || !IsDefined(player) || qs.GetFact(n"chispa_ep01_server_blown") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep01_server_blown", 1);
        qs.SetFact(n"chispa_ep01_used_netrun", 1);
        this.ApplySubnetSurgeDamage(player, true);
    }

    private final func ApplySubnetSurgeDamage(player: ref<PlayerPuppet>, detonateServerMesh: Bool) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);

        this.m_sys.PlaySfx(n"ch_sfx_capacitor_arc");
        if detonateServerMesh && EntityID.IsDefined(this.m_serverId) {
            let srv: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_serverId) as ExplosiveDevice;
            if IsDefined(srv) && IsDefined(srv.GetDevicePS()) && !srv.GetDevicePS().IsExploded() {
                srv.QueueEvent(new ForceDetonate());
            }
        }

        if IsDefined(des) {
            let zina: ref<NPCPuppet> = des.GetEntity(this.m_zinaId) as NPCPuppet;
            if IsDefined(zina) && !zina.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(zina, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(zina, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(zina.GetEntityID()), gamedataStatPoolType.Health, -100.0, player, true, true);
                }
                zina.Kill(player);
            }
            let kostya: ref<NPCPuppet> = des.GetEntity(this.m_kostyaId) as NPCPuppet;
            if IsDefined(kostya) && !kostya.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(kostya, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(kostya, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(kostya.GetEntityID()), gamedataStatPoolType.Health, -70.0, player, true, true);
                }
            }
            let vadik: ref<NPCPuppet> = des.GetEntity(this.m_vadikId) as NPCPuppet;
            if IsDefined(vadik) && !vadik.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(vadik, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(vadik, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(vadik.GetEntityID()), gamedataStatPoolType.Health, -65.0, player, true, true);
                }
            }
        }

        this.OnScavsProvoked(player, true);
        if qs.GetFact(n"chispa_ep01_stage") == 2 {
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingSubnetBoom = true;
            } else {
                this.m_pendingSubnetBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_subnet_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 8.34));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
    }

    public final func TriggerRelaySurge() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep01_relay_surged") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep01_relay_surged", 1);
        qs.SetFact(n"chispa_ep01_server_blown", 1);
        qs.SetFact(n"chispa_ep01_used_netrun", 1);

        this.m_sys.ShowRelicBanner(n"ch_banner_ep01_surge", "[CHISPA] ¡Sobrecarga RABIDS ejecutada! Retorno eléctrico en subred");

        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp01Relay");
        }
        this.m_relayId = new EntityID();
        this.ApplySubnetSurgeDamage(player, true);
    }

    public final func OnScavsProvoked(player: ref<PlayerPuppet>, silent: Bool) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || qs.GetFact(n"chispa_ep01_stage") != 2 {
            return;
        }
        let alreadyCombat: Bool = qs.GetFact(n"chispa_ep01_combat_started") > 0;
        if !alreadyCombat {
            qs.SetFact(n"chispa_ep01_combat_started", 1);
            this.m_combatStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        }
        let kostya: ref<NPCPuppet> = des.GetEntity(this.m_kostyaId) as NPCPuppet;
        let vadik: ref<NPCPuppet> = des.GetEntity(this.m_vadikId) as NPCPuppet;
        let zina: ref<NPCPuppet> = des.GetEntity(this.m_zinaId) as NPCPuppet;
        if IsDefined(kostya) && !kostya.IsDead() {
            this.m_sys.MakeNpcHostile(kostya, player);
            if !silent && !alreadyCombat && !this.m_sys.m_isPlayingDialogueSequence {
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_kostya_bark", n"ChispaEp01Kostya", n"Kostya", scnDialogLineType.Regular, 4.25));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        if IsDefined(vadik) && !vadik.IsDead() {
            this.m_sys.MakeNpcHostile(vadik, player);
        }
        if IsDefined(zina) && !zina.IsDead() {
            this.m_sys.MakeNpcHostile(zina, player);
        }
    }

    private final func IsSquadDefeated() -> Bool {
        if !EntityID.IsDefined(this.m_kostyaId) || !EntityID.IsDefined(this.m_vadikId) || !EntityID.IsDefined(this.m_zinaId) {
            return false;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep01_server_blown") == 0 && (!this.m_kostyaReady || !this.m_vadikReady || !this.m_zinaReady) {
            return false;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let anchor: Vector4 = this.GetTerminalPos();
        if !IsDefined(player) || this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), anchor) > 3600.00 {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        let elapsed: Float = this.m_combatStartedAt > 0.01 ? (now - this.m_combatStartedAt) : 0.00;
        let kostyaDown: Bool = this.m_sys.IsNpcNeutralized(this.m_kostyaId, anchor, elapsed, false);
        let vadikDown: Bool = this.m_sys.IsNpcNeutralized(this.m_vadikId, anchor, elapsed, kostyaDown && elapsed >= 10.00 && !player.IsInCombat());
        let zinaDown: Bool = this.m_sys.IsNpcNeutralized(this.m_zinaId, anchor, elapsed, kostyaDown && elapsed >= 10.00 && !player.IsInCombat());
        return kostyaDown && vadikDown && zinaDown;
    }

    public final func HandleInteraction(kind: Int32) -> Bool {
        if !IsDefined(this.m_sys) {
            return false;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        if !IsDefined(player) {
            return false;
        }

        if kind == 20 {
            this.TriggerRelaySurge();
            return true;
        }

        if kind == 21 {
            this.m_pendingCamBark = false;
            this.m_pendingPingBark = false;
            this.m_pendingSubnetBoom = false;
            this.m_pendingNetVictory = false;
            this.m_pendingGunsBlazing = false;

            let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
            if IsDefined(ses) {
                ses.DespawnTagged(n"ChispaEp01Sector");
            }
            this.m_sectorId = new EntityID();

            let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector01"), 1);
            ts.GiveMoney(player, 2200, n"money");
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.EMPOverloadLvl2Program"), 1);
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.OverheatLvl2Program"), 1);
            this.m_sys.GiveItemDelayed(t"Items.Preset_Saratoga_Chispa", 1, 1.15);
            GameObject.PlaySoundEvent(player, n"ui_loot_cash");
            this.m_sys.PlaySfx(n"ch_sfx_dongle_sync");
            this.m_sys.ShowRelicBanner(n"ch_banner_ep01_claimed", "[CHISPA] Sector #01 conectado (+2.200 €$, hackeos y «Frecuencia Fantasma»)");

            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
            this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
            this.m_sys.ClearMappin();
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk/desc_ep01_04", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk");
            qs.SetFact(n"chispa_ep01_stage", 4);

            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_sector_pickup", n"phone", n"CHISPA", scnDialogLineType.Holocall, 14.68));
            this.m_sys.StartSpeechSequence(steps, 209);
            return true;
        }
        return false;
    }

    public final func ShowDialogHub() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        let choices: array<ListChoiceData>;
        let ids: array<Int32>;

        if qs.GetFact(n"chispa_ep01_asked_bartmoss") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep01_bartmoss", "¿Quién fue Rache Bartmoss realmente y cómo tumbó toda la Red?"), false, false));
            ArrayPush(ids, 20);
        }
        if qs.GetFact(n"chispa_ep01_asked_krash") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep01_krash", "¿Qué pasó exactamente con el virus RABIDS y el DataKrash de 2022?"), false, false));
            ArrayPush(ids, 21);
        }
        if qs.GetFact(n"chispa_ep01_asked_blackwall") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep01_blackwall", "¿Por qué nadie tumba el Muro Negro de NetWatch y recupera la vieja Red?"), false, false));
            ArrayPush(ids, 22);
        }
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep01_accept", "Recibido, Chispa. Avísame cuando fijes el Sector #02 en Northside."), true, false));
        ArrayPush(ids, 23);

        this.m_sys.PushDialogHub(n"chispa_ep01", this.m_sys.GetLoc(n"ch_hub_ep01_talk_title", "C.H.I.S.P.A. // SECTOR #01 (Enlace Kiroshi)"), choices, ids);
    }

    public final func HandleDialogOption(optionId: Int32) -> Bool {
        if !IsDefined(this.m_sys) {
            return false;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        let steps: array<ref<ChispaSpeechStep>>;

        if optionId == 20 {
            qs.SetFact(n"chispa_ep01_asked_bartmoss", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_v_ask_bartmoss", n"player", n"V", scnDialogLineType.Regular, 5.47));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_ans_bartmoss", n"phone", n"CHISPA", scnDialogLineType.Holocall, 25.00));
            this.m_sys.StartSpeechSequence(steps, 210);
            return true;
        }
        if optionId == 21 {
            qs.SetFact(n"chispa_ep01_asked_krash", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_v_ask_krash", n"player", n"V", scnDialogLineType.Regular, 5.42));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_ans_krash", n"phone", n"CHISPA", scnDialogLineType.Holocall, 26.93));
            this.m_sys.StartSpeechSequence(steps, 211);
            return true;
        }
        if optionId == 22 {
            qs.SetFact(n"chispa_ep01_asked_blackwall", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_v_ask_blackwall", n"player", n"V", scnDialogLineType.Regular, 5.27));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_ans_blackwall", n"phone", n"CHISPA", scnDialogLineType.Holocall, 23.53));
            this.m_sys.StartSpeechSequence(steps, 212);
            return true;
        }
        if optionId == 23 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_v_outro_accept", n"player", n"V", scnDialogLineType.Regular, 5.19));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_outro", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.96));
            this.m_sys.StartSpeechSequence(steps, 220);
            return true;
        }
        return false;
    }

    private final func CompleteEpisode() -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);

        this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
        this.m_sys.ClearMappin();

        jm.ChangeEntryState("contacts/chispa_ai/conv_ep01/msg_ep01_summary", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep01", "gameJournalOnscreen", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/desc_ep01_done", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);

        this.m_sys.ShowRelicBanner(n"ch_banner_ep01_done", "[CHISPA] Episodio 1 completado — Próxima pista en Northside");
        qs.SetFact(n"chispa_ep01_done", 1);
        qs.SetFact(n"chispa_season_stage", 200);
        qs.SetFact(n"chispa_ep01_stage", 5);
    }

    public final func Tick(player: ref<PlayerPuppet>, phoneOpen: Bool, fullGameplay: Bool) -> Float {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep01_stage");

        if stage <= 0 {
            this.m_sys.HideDialogChoices();
            this.m_sys.HideWorldInteraction();
            this.m_sys.ClearMappin();
            if this.m_sys.m_sessionReadyTicks >= 6 && fullGameplay && !this.m_sys.IsExternalPhoneCallBusy() && !this.m_sys.m_isPlayingDialogueSequence {
                if this.m_introWaitTicks < 5 {
                    this.m_introWaitTicks += 1;
                    return 0.60;
                }
                qs.SetFact(n"chispa_ep01_stage", 1);
                qs.SetFact(n"chispa_ep01_call_done", 0);
                this.ActivateJournalQuest();
                this.m_sys.ShowRelicBanner(n"ch_banner_ep01_start", "[CHISPA] Eco detectado en Kabuki — Revisa tu holoteléfono");
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 11);
                return 0.45;
            }
            return 0.60;
        }

        if stage == 1 {
            this.ActivateJournalQuest();
            this.CheckSmsReply();
            if qs.GetFact(n"chispa_ep01_call_done") == 0
                && !this.m_sys.m_activeCallPendingPickup
                && !this.m_sys.m_isPlayingDialogueSequence
                && this.m_sys.m_sessionReadyTicks >= 6
                && fullGameplay
                && !this.m_sys.IsExternalPhoneCallBusy() {
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 11);
            }
            return 0.25;
        }

        if stage == 2 {
            this.m_sys.HideDialogChoices();
            this.m_sys.SyncObjectivePinLoop(
                12,
                "quests/side_quest/chispa_ep01_quest",
                "quests/side_quest/chispa_ep01_quest/phase_ep01",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/mp_ep01_kabuki",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let cam1Pos: Vector4 = this.GetMast01Pos();
            this.m_sys.UpdateFallbackMappin(
                12,
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate",
                new Vector4(cam1Pos.X, cam1Pos.Y, cam1Pos.Z + 1.80, 1.00),
                n"ch_mappin_ep01_kabuki",
                "CHISPA Ep. 1: Subred Kabuki Creek"
            );

            let distAreaSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), cam1Pos);
            if distAreaSq <= 900.00 && qs.GetFact(n"chispa_ep01_approach_played") == 0 && !this.m_sys.m_isPlayingDialogueSequence {
                qs.SetFact(n"chispa_ep01_approach_played", 1);
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_approach", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.43));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            if this.m_pendingCamBark && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingCamBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_cam_hijack", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.53));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingPingBark && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingPingBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_ping_react", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.36));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingSubnetBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingSubnetBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_subnet_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 8.34));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            let relPos: Vector4 = this.m_spawned ? this.m_relayPos : this.GetRelayPos();
            let distRelSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), relPos);

            if distRelSq <= 36.00 && qs.GetFact(n"chispa_ep01_combat_started") == 0 {
                this.OnScavsProvoked(player, false);
            }

            let scannedFlag: Bool = qs.GetFact(n"chispa_ep01_scanned") > 0;
            let canReachRelay: Bool = qs.GetFact(n"chispa_ep01_relay_surged") == 0
                && ((scannedFlag && distRelSq <= 324.00) || distRelSq <= 16.00);
            if canReachRelay && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(20, n"ch_hub_relay_title", "NODO REPETIDOR RABIDS", n"ch_act_surge_relay", "Sobrecargar repetidor RABIDS [Kiroshi]", false);
            } else {
                this.m_sys.HideWorldInteraction();
            }

            if EntityID.IsDefined(this.m_kostyaId) && this.IsSquadDefeated() {
                this.m_sys.HideWorldInteraction();
                jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
                this.m_sys.ActivateObjectiveWithPin(
                    13,
                    "quests/side_quest/chispa_ep01_quest",
                    "quests/side_quest/chispa_ep01_quest/phase_ep01",
                    "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract",
                    "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/mp_ep01_terminal",
                    "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/desc_ep01_03",
                    this.AllPinPaths(),
                    true
                );
                qs.SetFact(n"chispa_ep01_stage", 3);
                if qs.GetFact(n"chispa_ep01_used_netrun") > 0 {
                    if this.m_sys.m_isPlayingDialogueSequence {
                        this.m_pendingNetVictory = true;
                    } else {
                        this.m_pendingNetVictory = false;
                        let steps: array<ref<ChispaSpeechStep>>;
                        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_net_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.88));
                        this.m_sys.StartSpeechSequence(steps, 0);
                    }
                } else {
                    if this.m_sys.m_isPlayingDialogueSequence {
                        this.m_pendingGunsBlazing = true;
                    } else {
                        this.m_pendingGunsBlazing = false;
                        let steps: array<ref<ChispaSpeechStep>>;
                        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 13.63));
                        this.m_sys.StartSpeechSequence(steps, 0);
                    }
                }
            }
            return distAreaSq <= 400.00 ? 0.12 : 0.45;
        }

        if stage == 3 {
            this.m_sys.HideDialogChoices();
            if this.m_pendingSubnetBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingSubnetBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_subnet_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 8.34));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingNetVictory && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingNetVictory = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_net_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.88));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingGunsBlazing && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingGunsBlazing = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep01_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 13.63));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            this.m_sys.SyncObjectivePinLoop(
                13,
                "quests/side_quest/chispa_ep01_quest",
                "quests/side_quest/chispa_ep01_quest/phase_ep01",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/mp_ep01_terminal",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let termPos: Vector4 = this.m_spawned ? this.m_terminalPos : this.GetTerminalPos();
            this.m_sys.UpdateFallbackMappin(
                13,
                "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract",
                new Vector4(termPos.X, termPos.Y, termPos.Z + 1.55, 1.00),
                n"ch_mappin_ep01_terminal",
                "CHISPA Ep. 1: Terminal Entropy"
            );
            let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), termPos);
            if distSq <= 14.00 && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(21, n"ch_hub_ep01_term_title", "TERMINAL DE DATOS ENTROPY", n"ch_act_claim_sec01", "Extraer Sector de Memoria #01 [C.H.I.S.P.A.]", false, distSq <= 7.84);
            } else {
                this.m_sys.HideWorldInteraction();
            }
            return distSq <= 144.00 ? 0.12 : 0.45;
        }

        if stage == 4 {
            this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
            this.m_sys.ClearMappin();
            this.m_sys.HideWorldInteraction();
            if !this.m_sys.m_isPlayingDialogueSequence && !this.m_sys.IsUiBlockingWorldInput() {
                this.ShowDialogHub();
            } else {
                this.m_sys.HideDialogChoices();
            }
            return 0.15;
        }

        this.m_sys.HideDialogChoices();
        this.m_sys.HideWorldInteraction();
        this.m_sys.ClearMappin();
        return 1.00;
    }

    public final func ReplayCall() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep01_stage") < 1 {
            qs.SetFact(n"chispa_ep01_stage", 1);
            this.ActivateJournalQuest();
        }
        qs.SetFact(n"chispa_ep01_call_done", 0);
        this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 11);
    }

    public final func TeleportToKabuki() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        if !IsDefined(player) {
            return;
        }
        if qs.GetFact(n"chispa_ep01_stage") < 2 {
            this.ActivateJournalQuest();
            this.ActivateIntroSms();
            this.GrantStarterPingQuickhack(player);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            this.m_sys.ActivateObjectiveWithPin(
                12,
                "quests/side_quest/chispa_ep01_quest",
                "quests/side_quest/chispa_ep01_quest/phase_ep01",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/mp_ep01_kabuki",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/desc_ep01_02",
                this.AllPinPaths(),
                true
            );
            qs.SetFact(n"chispa_ep01_call_done", 1);
            qs.SetFact(n"chispa_ep01_sms_replied", 12);
            qs.SetFact(n"chispa_ep01_stage", 2);
        }
        let dest: Vector4 = this.GetArrivalPos();
        let ang: EulerAngles;
        ang.Yaw = -75.00;
        GameInstance.GetTeleportationFacility(game).Teleport(player, dest, ang);
        this.EnsureSpawned(player);
    }
}
