// Protocolo CHISPA / SPARKY Protocol — Episodio 5: «Más Allá del Muro Negro» (Final Temporada 1)
module ChispaNC

public class ChispaEp05Handler {
    private let m_sys: wref<ChispaSystem>;
    private let m_spawned: Bool;

    // Entidades estáticas: nodo Blackwall Coastview, sector maestro, pilón NetWatch, servidor criogénico y cámaras
    private let m_rigId: EntityID;
    private let m_sectorId: EntityID;
    private let m_pylonId: EntityID;
    private let m_cryoServerId: EntityID;
    private let m_mast01Id: EntityID;
    private let m_mast02Id: EntityID;
    private let m_cam01Id: EntityID;
    private let m_cam02Id: EntityID;
    private let m_cam01Configured: Bool;
    private let m_cam02Configured: Bool;
    private let m_serverConfigured: Bool;

    // Célula Hijos del Vudú + Animales (Coastview, Pacifica)
    private let m_tilucId: EntityID;
    private let m_mireilleId: EntityID;
    private let m_brutusId: EntityID;
    private let m_tilucReady: Bool;
    private let m_mireilleReady: Bool;
    private let m_brutusReady: Bool;

    // Cola de locuciones no solapadas y posiciones sobre suelo
    private let m_pendingStyleNet: Bool;
    private let m_pendingStyleBallistic: Bool;
    private let m_pendingCryoBoom: Bool;
    private let m_pendingVictory: Bool;
    private let m_rigPos: Vector4;
    private let m_pylonPos: Vector4;
    private let m_cryoPos: Vector4;
    private let m_combatStartedAt: Float;
    private let m_introWaitTicks: Int32;

    public final func Init(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
    }

    // Coastview, Pacifica (exterior_-40_-37_0_0 — libre de mappins vanilla a Z=8.95m, 100% juego base 2.x)
    public final func GetArrivalPos() -> Vector4 = new Vector4(-2526.50, -2356.50, 9.00, 1.00);
    public final func GetRigPos() -> Vector4 = new Vector4(-2518.50, -2336.80, 8.95, 1.00);
    public final func GetPylonPos() -> Vector4 = new Vector4(-2525.80, -2345.20, 8.95, 1.00);
    public final func GetCryoServerPos() -> Vector4 = new Vector4(-2516.40, -2340.60, 8.95, 1.00);
    public final func GetMast01Pos() -> Vector4 = new Vector4(-2523.60, -2346.80, 8.95, 1.00);
    public final func GetMast02Pos() -> Vector4 = new Vector4(-2512.20, -2337.20, 8.95, 1.00);

    public final func ResetRuntimeFlags() -> Void {
        this.m_spawned = false;
        this.m_rigId = new EntityID();
        this.m_sectorId = new EntityID();
        this.m_pylonId = new EntityID();
        this.m_cryoServerId = new EntityID();
        this.m_mast01Id = new EntityID();
        this.m_mast02Id = new EntityID();
        this.m_cam01Id = new EntityID();
        this.m_cam02Id = new EntityID();
        this.m_cam01Configured = false;
        this.m_cam02Configured = false;
        this.m_serverConfigured = false;
        this.m_tilucId = new EntityID();
        this.m_mireilleId = new EntityID();
        this.m_brutusId = new EntityID();
        this.m_tilucReady = false;
        this.m_mireilleReady = false;
        this.m_brutusReady = false;
        this.m_pendingStyleNet = false;
        this.m_pendingStyleBallistic = false;
        this.m_pendingCryoBoom = false;
        this.m_pendingVictory = false;
        this.m_rigPos = this.GetRigPos();
        this.m_pylonPos = this.GetPylonPos();
        this.m_cryoPos = this.GetCryoServerPos();
        this.m_combatStartedAt = 0.00;
        this.m_introWaitTicks = 0;
    }

    private final func AllPinPaths() -> array<String> {
        return [
            "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear/mp_ep05_pacifica",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract/mp_ep05_rig"
        ];
    }

    public final func CleanupEntities() -> Void {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) {
            des.DeleteTagged(n"ChispaEp05TiLuc");
            des.DeleteTagged(n"ChispaEp05Mireille");
            des.DeleteTagged(n"ChispaEp05Brutus");
        }
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp05Rig");
            ses.DespawnTagged(n"ChispaEp05Sector");
            ses.DespawnTagged(n"ChispaEp05Pylon");
            ses.DespawnTagged(n"ChispaEp05Cryo");
            ses.DespawnTagged(n"ChispaEp05Mast01");
            ses.DespawnTagged(n"ChispaEp05Mast02");
            ses.DespawnTagged(n"ChispaEp05Cam01");
            ses.DespawnTagged(n"ChispaEp05Cam02");
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
            "quests/side_quest/chispa_ep05_quest/phase_ep05/01_ep05_sms/desc_ep05_01",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear/desc_ep05_02",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract/desc_ep05_03",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/04_ep05_talk/desc_ep05_04",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/desc_ep05_done"
        ];
        for dp in descPaths {
            jm.ChangeEntryState(dp, "gameJournalQuestDescription", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        let objPaths: array<String> = [
            "quests/side_quest/chispa_ep05_quest/phase_ep05/01_ep05_sms",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/04_ep05_talk"
        ];
        for op in objPaths {
            jm.ChangeEntryState(op, "gameJournalQuestObjective", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05", "gameJournalQuestPhase", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest", "gameJournalQuest", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        let smsPaths: array<String> = [
            "contacts/chispa_ai/conv_ep05/msg_ep05_hook",
            "contacts/chispa_ai/conv_ep05/msg_ep05_voodoo",
            "contacts/chispa_ai/conv_ep05/msg_ep05_pacifica",
            "contacts/chispa_ai/conv_ep05/msg_ep05_summary"
        ];
        for sp in smsPaths {
            jm.ChangeEntryState(sp, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/choices_ep05/reply_ep05_voodoo", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/choices_ep05/reply_ep05_pacifica", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/choices_ep05", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05", "gameJournalPhoneConversation", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep05", "gameJournalOnscreen", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        qs.SetFact(n"chispa_ep05_call_done", 0);
        qs.SetFact(n"chispa_ep05_sms_replied", 0);
        qs.SetFact(n"chispa_ep05_approach_played", 0);
        qs.SetFact(n"chispa_ep05_scanned", 0);
        qs.SetFact(n"chispa_ep05_used_netrun", 0);
        qs.SetFact(n"chispa_ep05_net_bark", 0);
        qs.SetFact(n"chispa_ep05_used_ballistic", 0);
        qs.SetFact(n"chispa_ep05_ball_bark", 0);
        qs.SetFact(n"chispa_ep05_cryo_blown", 0);
        qs.SetFact(n"chispa_ep05_combat_started", 0);
        qs.SetFact(n"chispa_ep05_asked_pacifica", 0);
        qs.SetFact(n"chispa_ep05_asked_voodoo", 0);
        qs.SetFact(n"chispa_ep05_asked_origin", 0);
        qs.SetFact(n"chispa_ep05_ending", 0);
        qs.SetFact(n"chispa_permanent_partner", 0);
        qs.SetFact(n"chispa_ep05_done", 0);
        qs.SetFact(n"chispa_ep05_stage", 0);
        qs.SetFact(n"chispa_ep05_xp_sector", 0);
        qs.SetFact(n"chispa_ep05_xp_done", 0);
        qs.SetFact(n"chispa_qh_ep05_emp", 0);
        qs.SetFact(n"chispa_qh_ep05_collapse", 0);
        qs.SetFact(n"chispa_qh_ep05_ending", 0);
    }

    // --- Holollamada e Hilo de SMS Inicial ---

    public final func GetCallSteps(stageTag: Int32, out completeAction: Int32) -> array<ref<ChispaSpeechStep>> {
        let steps: array<ref<ChispaSpeechStep>>;
        if !IsDefined(this.m_sys) || stageTag != 51 {
            return steps;
        }
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_call_01", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.20));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_v_call_01", n"player", n"V", scnDialogLineType.Regular, 6.23));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_call_02", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.25));
        completeAction = 601;
        return steps;
    }

    public final func OnCallRejected(stageTag: Int32) -> Void {
        if IsDefined(this.m_sys) && stageTag == 51 {
            GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance()).SetFact(n"chispa_ep05_call_done", 1);
            this.ActivateIntroSms();
        }
    }

    public final func OnPostSpeech(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if actionId == 601 {
            qs.SetFact(n"chispa_ep05_call_done", 1);
            this.m_sys.EndCustomCall(n"chispa_ai", this.m_sys.m_activeCallIsVideo);
            this.ActivateIntroSms();
            return;
        }
        if actionId == 609 || actionId == 610 || actionId == 611 || actionId == 612 {
            if qs.GetFact(n"chispa_ep05_stage") == 4 && !this.m_sys.IsUiBlockingWorldInput() {
                this.ShowDialogHub();
            }
            return;
        }
        if actionId == 621 {
            this.CompleteEpisode(1);
            return;
        }
        if actionId == 622 {
            this.CompleteEpisode(2);
            return;
        }
        if actionId == 623 {
            this.CompleteEpisode(3);
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
        let qEntry: wref<JournalEntry> = jm.GetEntryByString("quests/side_quest/chispa_ep05_quest", "gameJournalQuest");
        if !IsDefined(qEntry) {
            return;
        }
        let qState: gameJournalEntryState = jm.GetEntryState(qEntry);
        if Equals(qState, gameJournalEntryState.Active) || Equals(qState, gameJournalEntryState.Succeeded) {
            return;
        }
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest", "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05", "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/01_ep05_sms/desc_ep05_01", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/01_ep05_sms", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        if !IsDefined(jm.GetTrackedEntry()) {
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep05_quest/phase_ep05/01_ep05_sms");
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
        let msgEntry: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep05/msg_ep05_hook", "gameJournalPhoneMessage");
        if IsDefined(msgEntry) && Equals(jm.GetEntryState(msgEntry), gameJournalEntryState.Active) {
            return;
        }
        jm.ChangeEntryState("contacts/chispa_ai", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05", "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/msg_ep05_hook", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/choices_ep05", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/choices_ep05/reply_ep05_voodoo", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/choices_ep05/reply_ep05_pacifica", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    }

    public final func CheckSmsReply() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(jm) || qs.GetFact(n"chispa_ep05_stage") != 1 || qs.GetFact(n"chispa_ep05_sms_replied") > 0 {
            return;
        }
        let rVoodoo: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep05/choices_ep05/reply_ep05_voodoo", "gameJournalPhoneChoiceEntry");
        let rPacifica: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep05/choices_ep05/reply_ep05_pacifica", "gameJournalPhoneChoiceEntry");

        let replyKind: Int32 = 0;
        if IsDefined(rVoodoo) && Equals(jm.GetEntryState(rVoodoo), gameJournalEntryState.Succeeded) {
            replyKind = 51;
        } else if IsDefined(rPacifica) && Equals(jm.GetEntryState(rPacifica), gameJournalEntryState.Succeeded) {
            replyKind = 52;
        }
        if replyKind == 0 {
            return;
        }

        qs.SetFact(n"chispa_ep05_sms_replied", replyKind);
        let cb: ref<ChispaSmsDelayCallback> = new ChispaSmsDelayCallback();
        cb.system = this.m_sys;
        cb.actionId = replyKind;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.90, false);
    }

    private final func GrantStarterFinaleKit(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        if !IsDefined(ts) || !IsDefined(player) {
            return;
        }
        let granted: Bool = false;
        let empQty: Int32 = ts.GetItemQuantity(player, ItemID.CreateQuery(t"Items.GrenadeEMPRegular"));
        if empQty < 2 {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.GrenadeEMPRegular"), 2 - empQty);
            granted = true;
        }
        if this.m_sys.AwardMilestoneProgram(player, n"chispa_qh_ep05_emp", n"EMPOverload", 4) {
            granted = true;
        }
        this.m_sys.EnsureSmartBridgeActive(player);
        this.m_sys.EnsureRicochetBridgeActive(player);
        if granted {
            this.m_sys.ShowRelicBanner(n"ch_banner_ep05_gear", "[CHISPA] ¡Kit PEM y puentes Kiroshi completos activos! Ruta a Pacifica abierta");
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
        if actionId == 51 {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/msg_ep05_voodoo", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        } else {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/msg_ep05_pacifica", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        }
        this.GrantStarterFinaleKit(player);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/01_ep05_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        this.m_sys.ActivateObjectiveWithPin(
            52,
            "quests/side_quest/chispa_ep05_quest",
            "quests/side_quest/chispa_ep05_quest/phase_ep05",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear/mp_ep05_pacifica",
            "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear/desc_ep05_02",
            this.AllPinPaths(),
            true
        );
        qs.SetFact(n"chispa_ep05_stage", 2);
    }

    // --- Escena Táctica Coastview / Muro Negro (Cámaras Encadenadas + Balística + Contención) ---

    private final func EnsureSpawned(player: ref<PlayerPuppet>) -> Void {
        let rigBase: Vector4 = this.GetRigPos();
        let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigBase);
        if distSq > 4225.00 {
            return;
        }

        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep05_stage");
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();

        if IsDefined(ses) && ses.IsReady() {
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_mast01Id) {
                ses.DespawnTagged(n"ChispaEp05Mast01");
                let m1Base: Vector4 = this.GetMast01Pos();
                let zM1: Float = this.m_sys.FindGroundZ(m1Base);
                let pM1: Vector4 = new Vector4(m1Base.X, m1Base.Y, zM1, 1.00);
                this.m_mast01Id = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep01_cam_mast.ent", n"", pM1, 0.00, 35.00, n"ChispaEp05Mast01");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_cam01Id) {
                ses.DespawnTagged(n"ChispaEp05Cam01");
                this.m_cam01Configured = false;
                let m1Base: Vector4 = this.GetMast01Pos();
                let zC1: Float = this.m_sys.FindGroundZ(m1Base);
                let pC1: Vector4 = new Vector4(m1Base.X, m1Base.Y, zC1 + 2.05, 1.00);
                this.m_cam01Id = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\security_systems\\surveillance_cameras\\surveillance_camera.ent", n"appearances_camera_wall_old", pC1, -18.00, 35.00, n"ChispaEp05Cam01");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_mast02Id) {
                ses.DespawnTagged(n"ChispaEp05Mast02");
                let m2Base: Vector4 = this.GetMast02Pos();
                let zM2: Float = this.m_sys.FindGroundZ(m2Base);
                let pM2: Vector4 = new Vector4(m2Base.X, m2Base.Y, zM2, 1.00);
                this.m_mast02Id = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep01_cam_mast.ent", n"", pM2, 0.00, 215.00, n"ChispaEp05Mast02");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_cam02Id) {
                ses.DespawnTagged(n"ChispaEp05Cam02");
                this.m_cam02Configured = false;
                let m2Base: Vector4 = this.GetMast02Pos();
                let zC2: Float = this.m_sys.FindGroundZ(m2Base);
                let pC2: Vector4 = new Vector4(m2Base.X, m2Base.Y, zC2 + 2.05, 1.00);
                this.m_cam02Id = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\security_systems\\surveillance_cameras\\surveillance_camera.ent", n"appearances_camera_wall_old", pC2, -20.00, 215.00, n"ChispaEp05Cam02");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_rigId) {
                ses.DespawnTagged(n"ChispaEp05Rig");
                let zR: Float = this.m_sys.FindGroundZ(rigBase);
                this.m_rigPos = new Vector4(rigBase.X, rigBase.Y, zR, 1.00);
                this.m_rigId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep05_blackwall_rig.ent", n"", this.m_rigPos, 0.00, -155.00, n"ChispaEp05Rig");
            }
            if (stage == 2 || stage == 3) && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_sectorId) {
                ses.DespawnTagged(n"ChispaEp05Sector");
                let zR: Float = this.m_sys.FindGroundZ(rigBase);
                this.m_rigPos = new Vector4(rigBase.X, rigBase.Y, zR, 1.00);
                this.m_sectorId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep05_master_sector.ent", n"", this.m_rigPos, 0.00, -155.00, n"ChispaEp05Sector");
            }
            if qs.GetFact(n"chispa_ep05_cryo_blown") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_pylonId) {
                ses.DespawnTagged(n"ChispaEp05Pylon");
                let pyBase: Vector4 = this.GetPylonPos();
                let zPy: Float = this.m_sys.FindGroundZ(pyBase);
                this.m_pylonPos = new Vector4(pyBase.X, pyBase.Y, zPy, 1.00);
                this.m_pylonId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep05_containment_pylon.ent", n"", this.m_pylonPos, 0.00, 25.00, n"ChispaEp05Pylon");
            }
            if qs.GetFact(n"chispa_ep05_cryo_blown") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_cryoServerId) {
                ses.DespawnTagged(n"ChispaEp05Cryo");
                this.m_serverConfigured = false;
                let cBase: Vector4 = this.GetCryoServerPos();
                let zC: Float = this.m_sys.FindGroundZ(cBase);
                this.m_cryoPos = new Vector4(cBase.X, cBase.Y, zC, 1.00);
                this.m_cryoServerId = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\explosives\\explosive_server.ent", n"explosive_server_appearance_entropy", this.m_cryoPos, 0.00, 195.00, n"ChispaEp05Cryo");
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
            if !this.m_serverConfigured && EntityID.IsDefined(this.m_cryoServerId) && ses.IsSpawned(this.m_cryoServerId) {
                let srvObj: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_cryoServerId) as ExplosiveDevice;
                if IsDefined(srvObj) && IsDefined(srvObj.GetDevicePS()) {
                    srvObj.GetDevicePS().ChispaConfigureExplosiveServer();
                    this.m_serverConfigured = true;
                }
            }
        }

        if stage == 2 {
            let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
            if IsDefined(des) && des.IsReady() {
                if !EntityID.IsDefined(this.m_tilucId) && !this.m_sys.IsDynamicEntityAliveOrSpawning(this.m_tilucId) {
                    des.DeleteTagged(n"ChispaEp05TiLuc");
                    des.DeleteTagged(n"ChispaEp05Mireille");
                    des.DeleteTagged(n"ChispaEp05Brutus");

                    let tXY: Vector4 = new Vector4(-2517.80, -2339.40, rigBase.Z, 1.00);
                    let mXY: Vector4 = new Vector4(-2521.20, -2340.80, rigBase.Z, 1.00);
                    let bXY: Vector4 = new Vector4(-2515.20, -2342.40, rigBase.Z, 1.00);
                    let zT: Float = this.m_sys.FindGroundZ(tXY);
                    let zM: Float = this.m_sys.FindGroundZ(mXY);
                    let zB: Float = this.m_sys.FindGroundZ(bXY);

                    this.m_tilucReady = false;
                    this.m_mireilleReady = false;
                    this.m_brutusReady = false;
                    this.m_tilucId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep05_TiLuc", new Vector4(tXY.X, tXY.Y, zT, 1.00), 205.00, n"ChispaEp05TiLuc");
                    this.m_mireilleId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep05_Mireille", new Vector4(mXY.X, mXY.Y, zM, 1.00), 195.00, n"ChispaEp05Mireille");
                    this.m_brutusId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep05_Brutus", new Vector4(bXY.X, bXY.Y, zB, 1.00), 215.00, n"ChispaEp05Brutus");
                }
                if !this.m_tilucReady && EntityID.IsDefined(this.m_tilucId) && des.IsSpawned(this.m_tilucId) {
                    let tNpc: ref<NPCPuppet> = des.GetEntity(this.m_tilucId) as NPCPuppet;
                    if IsDefined(tNpc) && ScriptedPuppet.IsActive(tNpc) {
                        this.m_tilucReady = true;
                    }
                }
                if !this.m_mireilleReady && EntityID.IsDefined(this.m_mireilleId) && des.IsSpawned(this.m_mireilleId) {
                    let mNpc: ref<NPCPuppet> = des.GetEntity(this.m_mireilleId) as NPCPuppet;
                    if IsDefined(mNpc) && ScriptedPuppet.IsActive(mNpc) {
                        this.m_mireilleReady = true;
                    }
                }
                if !this.m_brutusReady && EntityID.IsDefined(this.m_brutusId) && des.IsSpawned(this.m_brutusId) {
                    let bNpc: ref<NPCPuppet> = des.GetEntity(this.m_brutusId) as NPCPuppet;
                    if IsDefined(bNpc) && ScriptedPuppet.IsActive(bNpc) {
                        this.m_brutusReady = true;
                    }
                }
            }
        }
        this.m_spawned = true;
    }

    // --- Cámaras Encadenadas, Telemetría Multi-Estilo y Purga Criogénica ---

    public final func IsEp05Camera(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && (Equals(id, this.m_cam01Id) || Equals(id, this.m_cam02Id));
    }

    public final func IsEp05CryoServer(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && Equals(id, this.m_cryoServerId);
    }

    public final func IsEp05Npc(id: EntityID) -> Bool {
        return EntityID.IsDefined(id)
            && (Equals(id, this.m_tilucId)
                || Equals(id, this.m_mireilleId)
                || Equals(id, this.m_brutusId));
    }

    private final func IsEp05Target(id: EntityID) -> Bool {
        return this.IsEp05Camera(id) || this.IsEp05CryoServer(id) || this.IsEp05Npc(id);
    }

    public final func PopulateEp05CameraChain(activeCamId: EntityID) -> Void {
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
        p1.displayName = this.m_sys.GetLoc(n"ch_cam_ep05_perim", "CAM-01 PERÍMETRO PACIFICA");
        p1.ownerID = CreatePersistentID(this.m_cam01Id, n"controller");
        p1.ownerIDClassName = n"SurveillanceCameraControllerPS";
        p1.customData = cd1;
        p1.libraryID = n"device";
        ArrayPush(chain, p1);

        let cd2: ref<ControlledDeviceData> = new ControlledDeviceData();
        cd2.m_isActive = Equals(this.m_cam02Id, activeCamId);
        let p2: SWidgetPackage;
        p2.displayName = this.m_sys.GetLoc(n"ch_cam_ep05_server", "CAM-02 NODO MURO NEGRO");
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
            let ids: array<EntityID> = [this.m_tilucId, this.m_mireilleId, this.m_brutusId];
            for nid in ids {
                if EntityID.IsDefined(nid) && des.IsSpawned(nid) {
                    let npc: ref<NPCPuppet> = des.GetEntity(nid) as NPCPuppet;
                    if IsDefined(npc) && !npc.IsDead() {
                        StatusEffectHelper.ApplyStatusEffect(npc, t"BaseStatusEffect.PingLvl2MarkStatusEffect", player.GetEntityID());
                    }
                }
            }
        }
        if EntityID.IsDefined(this.m_cryoServerId) {
            let srvObj: ref<GameObject> = GameInstance.FindEntityByID(game, this.m_cryoServerId) as GameObject;
            if IsDefined(srvObj) {
                let hi: ref<FocusForcedHighlightData> = new FocusForcedHighlightData();
                hi.sourceID = player.GetEntityID();
                hi.sourceName = n"ChispaEp05Ping";
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
        if qs.GetFact(n"chispa_ep05_stage") != 2 {
            return;
        }
        if qs.GetFact(n"chispa_ep05_scanned") == 0 {
            qs.SetFact(n"chispa_ep05_scanned", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
        }
    }

    public final func OnCameraOrQuickHackUsed() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep05_stage") != 2 {
            return;
        }
        qs.SetFact(n"chispa_ep05_used_netrun", 1);
        if qs.GetFact(n"chispa_ep05_net_bark") == 0 {
            qs.SetFact(n"chispa_ep05_net_bark", 1);
            this.m_sys.PlaySfx(n"ch_sfx_net_breach");
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingStyleNet = true;
            } else {
                this.m_pendingStyleNet = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_style_net", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.48));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
    }

    public final func OnBallisticMasteryLanded() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep05_stage") != 2 {
            return;
        }
        qs.SetFact(n"chispa_ep05_used_ballistic", 1);
        if qs.GetFact(n"chispa_ep05_ball_bark") == 0 {
            qs.SetFact(n"chispa_ep05_ball_bark", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingStyleBallistic = true;
            } else {
                this.m_pendingStyleBallistic = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_style_ballistic", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.38));
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
        if qs.GetFact(n"chispa_ep05_stage") != 2 || !IsDefined(player) {
            return;
        }
        let nearPacifica: Bool = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), this.GetRigPos()) <= 5625.00;
        if !this.IsEp05Target(actionOwner) && !nearPacifica {
            return;
        }
        if Equals(actionClassName, n"ToggleTakeOverControl") || Equals(objectActionID, t"DeviceAction.TakeControlCameraClassHack") {
            return;
        }
        let isPing: Bool = Equals(actionClassName, n"PingDevice")
            || Equals(objectActionID, t"QuickHack.PingHack")
            || Equals(objectActionID, t"QuickHack.FreePingHack");
        if isPing {
            this.ApplyPingHighlights(player);
        }
        this.OnCameraOrQuickHackUsed();
        if !isPing && this.IsEp05Npc(actionOwner) {
            this.OnVoodooSquadProvoked(player, true);
        }
    }

    private final func ApplyContainmentSurgeToSquad(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);

        this.m_sys.PlaySfx(n"ch_sfx_capacitor_arc");
        if IsDefined(des) {
            let mireille: ref<NPCPuppet> = des.GetEntity(this.m_mireilleId) as NPCPuppet;
            if IsDefined(mireille) && !mireille.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(mireille, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(mireille, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(mireille.GetEntityID()), gamedataStatPoolType.Health, -100.0, player, true, true);
                }
                mireille.Kill(player);
            }
            let brutus: ref<NPCPuppet> = des.GetEntity(this.m_brutusId) as NPCPuppet;
            if IsDefined(brutus) && !brutus.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(brutus, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(brutus, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(brutus.GetEntityID()), gamedataStatPoolType.Health, -75.0, player, true, true);
                }
            }
            let tiluc: ref<NPCPuppet> = des.GetEntity(this.m_tilucId) as NPCPuppet;
            if IsDefined(tiluc) && !tiluc.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(tiluc, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(tiluc, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(tiluc.GetEntityID()), gamedataStatPoolType.Health, -60.0, player, true, true);
                }
            }
        }
        this.OnVoodooSquadProvoked(player, true);
    }

    public final func OnCryoServerDetonated() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep05_stage") != 2 || !IsDefined(player) || qs.GetFact(n"chispa_ep05_cryo_blown") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep05_cryo_blown", 1);
        qs.SetFact(n"chispa_ep05_used_netrun", 1);
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp05Pylon");
        }
        this.m_pylonId = new EntityID();

        this.m_sys.ShowRelicBanner(n"ch_banner_ep05_cryo", "[CHISPA] ¡Baliza NetWatch y servidor criogénico purgados en Pacifica!");
        this.ApplyContainmentSurgeToSquad(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingCryoBoom = true;
        } else {
            this.m_pendingCryoBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_cryo_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.29));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func TriggerContainmentPurge() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep05_cryo_blown") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep05_cryo_blown", 1);
        qs.SetFact(n"chispa_ep05_used_netrun", 1);

        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp05Pylon");
        }
        this.m_pylonId = new EntityID();

        if EntityID.IsDefined(this.m_cryoServerId) {
            let srvObj: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_cryoServerId) as ExplosiveDevice;
            if IsDefined(srvObj) && IsDefined(srvObj.GetDevicePS()) && !srvObj.GetDevicePS().IsExploded() {
                srvObj.QueueEvent(new ForceDetonate());
            }
        }
        this.m_sys.ShowRelicBanner(n"ch_banner_ep05_cryo", "[CHISPA] ¡Baliza NetWatch y servidor criogénico purgados en Pacifica!");
        this.ApplyContainmentSurgeToSquad(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingCryoBoom = true;
        } else {
            this.m_pendingCryoBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_cryo_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.29));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func OnVoodooSquadProvoked(player: ref<PlayerPuppet>, silent: Bool) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || qs.GetFact(n"chispa_ep05_stage") != 2 {
            return;
        }
        let alreadyCombat: Bool = qs.GetFact(n"chispa_ep05_combat_started") > 0;
        if !alreadyCombat {
            qs.SetFact(n"chispa_ep05_combat_started", 1);
            this.m_combatStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        }

        let tiluc: ref<NPCPuppet> = des.GetEntity(this.m_tilucId) as NPCPuppet;
        let mireille: ref<NPCPuppet> = des.GetEntity(this.m_mireilleId) as NPCPuppet;
        let brutus: ref<NPCPuppet> = des.GetEntity(this.m_brutusId) as NPCPuppet;
        if IsDefined(tiluc) && !tiluc.IsDead() {
            this.m_sys.MakeNpcHostile(tiluc, player);
            if !silent && !alreadyCombat && !this.m_sys.m_isPlayingDialogueSequence {
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_tiluc_bark", n"ChispaEp05TiLuc", n"Ti-Luc", scnDialogLineType.Regular, 5.51));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        if IsDefined(mireille) && !mireille.IsDead() {
            this.m_sys.MakeNpcHostile(mireille, player);
        }
        if IsDefined(brutus) && !brutus.IsDead() {
            this.m_sys.MakeNpcHostile(brutus, player);
        }
    }

    private final func IsSquadDefeated() -> Bool {
        if !EntityID.IsDefined(this.m_tilucId) || !EntityID.IsDefined(this.m_mireilleId) || !EntityID.IsDefined(this.m_brutusId) {
            return false;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep05_cryo_blown") == 0 && (!this.m_tilucReady || !this.m_mireilleReady || !this.m_brutusReady) {
            return false;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let anchor: Vector4 = this.GetRigPos();
        if !IsDefined(player) || this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), anchor) > 3600.00 {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        let elapsed: Float = this.m_combatStartedAt > 0.01 ? (now - this.m_combatStartedAt) : 0.00;
        let tilucDown: Bool = this.m_sys.IsNpcNeutralized(this.m_tilucId, anchor, elapsed, false);
        let mireilleDown: Bool = this.m_sys.IsNpcNeutralized(this.m_mireilleId, anchor, elapsed, tilucDown && elapsed >= 10.00 && !player.IsInCombat());
        let brutusDown: Bool = this.m_sys.IsNpcNeutralized(this.m_brutusId, anchor, elapsed, tilucDown && elapsed >= 10.00 && !player.IsInCombat());
        return tilucDown && mireilleDown && brutusDown;
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

        if kind == 60 {
            this.TriggerContainmentPurge();
            return true;
        }

        if kind == 61 {
            this.m_pendingStyleNet = false;
            this.m_pendingStyleBallistic = false;
            this.m_pendingCryoBoom = false;
            this.m_pendingVictory = false;

            let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
            if IsDefined(ses) {
                ses.DespawnTagged(n"ChispaEp05Sector");
            }
            this.m_sectorId = new EntityID();

            let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector05"), 1);
            ts.GiveMoney(player, 5000, n"money");
            this.m_sys.AwardMilestoneProgram(player, n"chispa_qh_ep05_collapse", n"SystemCollapse", 4);
            this.m_sys.GiveItemDelayed(t"Items.Preset_Kenshin_Chispa", 1, 1.15);
            GameObject.PlaySoundEvent(player, n"ui_loot_cash");
            this.m_sys.PlaySfx(n"ch_sfx_dongle_sync");
            this.m_sys.ShowRelicBanner(n"ch_banner_ep05_claimed", "[CHISPA] Sector Maestro #05 conectado (+5.000 €$, Colapso Sistema y «Cortafuegos del 22»)");

            jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
            this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
            this.m_sys.ClearMappin();
            jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/04_ep05_talk/desc_ep05_04", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/04_ep05_talk", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep05_quest/phase_ep05/04_ep05_talk");
            qs.SetFact(n"chispa_ep05_stage", 4);
            this.m_sys.EnsureCoprocessorRamBridgeActive(player);
            this.m_sys.AwardMilestoneXP(n"chispa_ep05_xp_sector", 1000, 1250, gamedataProficiencyType.IntelligenceSkill, 500);

            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_sector_pickup", n"phone", n"CHISPA", scnDialogLineType.Holocall, 14.94));
            this.m_sys.StartSpeechSequence(steps, 609);
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

        if qs.GetFact(n"chispa_ep05_asked_pacifica") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep05_pacifica", "¿Cómo pasó Pacifica de proyecto de resort corporativo a esta ruina sin ley?"), false, false));
            ArrayPush(ids, 60);
        }
        if qs.GetFact(n"chispa_ep05_asked_voodoo") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep05_voodoo", "¿Por qué se juegan el cuello los Hijos del Vudú hurgando tras el Muro Negro?"), false, false));
            ArrayPush(ids, 61);
        }
        if qs.GetFact(n"chispa_ep05_asked_origin") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep05_origin", "Con los cinco sectores enteros... ¿quién te programó realmente en 2022, Chispa?"), false, false));
            ArrayPush(ids, 62);
        }
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep05_end_partner", "[Socio v1.0] Quédate autónomo en mis Kiroshi; seguimos patrullando juntos Night City."), true, false));
        ArrayPush(ids, 63);
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep05_end_leak", "[Filtración N54] Filtra todo el archivo oculto de 2022 a la prensa libre y reparte el cheque."), true, false));
        ArrayPush(ids, 64);
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep05_end_gunsmith", "[Protocolo Armero] Vuelca tu subrutina balística en un último prototipo icónico Overture."), true, false));
        ArrayPush(ids, 65);

        this.m_sys.PushDialogHub(n"chispa_ep05", this.m_sys.GetLoc(n"ch_hub_ep05_talk_title", "C.H.I.S.P.A. // NÚCLEO MAESTRO 2022 (Enlace Kiroshi)"), choices, ids);
    }

    public final func HandleDialogOption(optionId: Int32) -> Bool {
        if !IsDefined(this.m_sys) {
            return false;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        let steps: array<ref<ChispaSpeechStep>>;

        if optionId == 60 {
            qs.SetFact(n"chispa_ep05_asked_pacifica", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_v_ask_pacifica", n"player", n"V", scnDialogLineType.Regular, 4.65));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_ans_pacifica", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.30));
            this.m_sys.StartSpeechSequence(steps, 610);
            return true;
        }
        if optionId == 61 {
            qs.SetFact(n"chispa_ep05_asked_voodoo", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_v_ask_voodoo", n"player", n"V", scnDialogLineType.Regular, 3.93));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_ans_voodoo", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.40));
            this.m_sys.StartSpeechSequence(steps, 611);
            return true;
        }
        if optionId == 62 {
            qs.SetFact(n"chispa_ep05_asked_origin", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_v_ask_origin", n"player", n"V", scnDialogLineType.Regular, 5.32));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_ans_origin", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.04));
            this.m_sys.StartSpeechSequence(steps, 612);
            return true;
        }
        if optionId == 63 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_v_end_partner", n"player", n"V", scnDialogLineType.Regular, 7.76));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_outro_partner", n"phone", n"CHISPA", scnDialogLineType.Holocall, 13.21));
            this.m_sys.StartSpeechSequence(steps, 621);
            return true;
        }
        if optionId == 64 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_v_end_leak", n"player", n"V", scnDialogLineType.Regular, 8.24));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_outro_leak", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.12));
            this.m_sys.StartSpeechSequence(steps, 622);
            return true;
        }
        if optionId == 65 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_v_end_gunsmith", n"player", n"V", scnDialogLineType.Regular, 7.84));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_outro_gunsmith", n"phone", n"CHISPA", scnDialogLineType.Holocall, 13.80));
            this.m_sys.StartSpeechSequence(steps, 623);
            return true;
        }
        return false;
    }

    private final func CompleteEpisode(endingId: Int32) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;

        this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
        this.m_sys.ClearMappin();

        jm.ChangeEntryState("contacts/chispa_ai/conv_ep05/msg_ep05_summary", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep05", "gameJournalOnscreen", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/04_ep05_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/desc_ep05_done", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);

        qs.SetFact(n"chispa_ep05_ending", endingId);
        qs.SetFact(n"chispa_ep05_done", 1);
        qs.SetFact(n"chispa_season_stage", 600);
        qs.SetFact(n"chispa_ep05_stage", 5);

        if endingId == 1 {
            qs.SetFact(n"chispa_permanent_partner", 1);
            if IsDefined(player) && IsDefined(ts) {
                ts.GiveMoney(player, 1500, n"money");
                this.m_sys.AwardMilestoneProgram(player, n"chispa_qh_ep05_ending", n"BrainMelt", 4);
                GameObject.PlaySoundEvent(player, n"ui_loot_cash");
                this.m_sys.EnsureSmartBridgeActive(player);
                this.m_sys.EnsureRicochetBridgeActive(player);
            }
            this.m_sys.ShowRelicBanner(n"ch_banner_ep05_end_partner", "[CHISPA v1.0] Socio autónomo fijado en tus Kiroshi (+1.500 €$ y Sinapsis Calcinada)");
        } else if endingId == 2 {
            if IsDefined(player) && IsDefined(ts) {
                ts.GiveMoney(player, 4500, n"money");
                this.m_sys.AwardMilestoneProgram(player, n"chispa_qh_ep05_ending", n"DisableCyberware", 4);
                GameObject.PlaySoundEvent(player, n"ui_loot_cash");
            }
            this.m_sys.ShowRelicBanner(n"ch_banner_ep05_end_leak", "[CHISPA // N54] ¡Archivo 2022 filtrado a N54! (+4.500 €$ y Fallo Ciberware)");
        } else {
            if IsDefined(player) && IsDefined(ts) {
                ts.GiveMoney(player, 1500, n"money");
                GameObject.PlaySoundEvent(player, n"ui_loot_cash");
                this.m_sys.GiveItemDelayed(t"Items.Preset_Overture_Chispa", 1, 1.15);
                this.m_sys.EnsureRicochetBridgeActive(player);
            }
            this.m_sys.ShowRelicBanner(n"ch_banner_ep05_end_gunsmith", "[CHISPA // ARMERÍA] ¡Temporada 1 completada! Forjada «Última Palabra de Sargento»");
        }
        this.m_sys.AwardMilestoneXP(n"chispa_ep05_xp_done", 1400, 1500, gamedataProficiencyType.Level, 0);
    }

    public final func Tick(player: ref<PlayerPuppet>, phoneOpen: Bool, fullGameplay: Bool) -> Float {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep05_stage");

        if qs.GetFact(n"chispa_ep05_done") == 0 && stage == 0 {
            if !fullGameplay || this.m_sys.m_sessionReadyTicks < 6 || !this.m_sys.HasLiftedWatsonLockdown(player) {
                return 0.60;
            }
            if this.m_sys.m_isPlayingDialogueSequence || this.m_sys.IsExternalPhoneCallBusy() {
                this.m_introWaitTicks = 0;
                return 0.60;
            }
            this.m_introWaitTicks += 1;
            if this.m_introWaitTicks >= 5 {
                this.ActivateJournalQuest();
                this.ActivateIntroSms();
                this.m_sys.ShowRelicBanner(n"ch_banner_ep05_start", "[CHISPA] ¡Núcleo Maestro #05 localizado en Coastview, Pacifica!");
                qs.SetFact(n"chispa_ep05_stage", 1);
                qs.SetFact(n"chispa_ep05_call_done", 0);
                if !this.m_sys.m_activeCallPendingPickup {
                    this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 51);
                }
            }
            return 0.60;
        }

        if stage == 1 {
            this.ActivateJournalQuest();
            this.CheckSmsReply();
            if qs.GetFact(n"chispa_ep05_call_done") == 0
                && !this.m_sys.m_activeCallPendingPickup
                && !this.m_sys.m_isPlayingDialogueSequence
                && this.m_sys.m_sessionReadyTicks >= 6
                && fullGameplay
                && this.m_sys.HasLiftedWatsonLockdown(player)
                && !this.m_sys.IsExternalPhoneCallBusy() {
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 51);
            }
            return 0.25;
        }

        if stage == 2 {
            this.m_sys.HideDialogChoices();
            this.m_sys.SyncObjectivePinLoop(
                52,
                "quests/side_quest/chispa_ep05_quest",
                "quests/side_quest/chispa_ep05_quest/phase_ep05",
                "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear",
                "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear/mp_ep05_pacifica",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let pylonPos: Vector4 = this.m_spawned ? this.m_pylonPos : this.GetPylonPos();
            let rigPos: Vector4 = this.m_spawned ? this.m_rigPos : this.GetRigPos();
            this.m_sys.UpdateFallbackMappin(
                52,
                "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear",
                new Vector4(rigPos.X, rigPos.Y - 4.20, rigPos.Z + 1.55, 1.00),
                n"ch_mappin_ep05_pacifica",
                "CHISPA Ep. 5: Nodo Coastview (Pacifica)"
            );

            let distRigSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigPos);
            if distRigSq <= 1024.00 && qs.GetFact(n"chispa_ep05_approach_played") == 0 && !this.m_sys.m_isPlayingDialogueSequence {
                qs.SetFact(n"chispa_ep05_approach_played", 1);
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_approach", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.40));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            if this.m_pendingStyleNet && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingStyleNet = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_style_net", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.48));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingStyleBallistic && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingStyleBallistic = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_style_ballistic", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.38));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingCryoBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingCryoBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_cryo_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.29));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            let centerCombatPos: Vector4 = new Vector4(-2518.50, -2341.00, rigPos.Z, 1.00);
            if this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), centerCombatPos) <= 64.00 && qs.GetFact(n"chispa_ep05_combat_started") == 0 {
                this.OnVoodooSquadProvoked(player, false);
            }

            let distPylonSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), pylonPos);
            let scannedFlag: Bool = qs.GetFact(n"chispa_ep05_scanned") > 0;
            let canReachPylon: Bool = qs.GetFact(n"chispa_ep05_cryo_blown") == 0
                && ((scannedFlag && distPylonSq <= 324.00) || distPylonSq <= 64.00);
            if canReachPylon && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(60, n"ch_hub_ep05_pylon_title", "BALIZA DE CONTENCIÓN // NETWATCH", n"ch_act_purge_ep05", "Purgar pulso de contención contra el servidor vudú [Kiroshi]", false);
            } else {
                this.m_sys.HideWorldInteraction();
            }

            if EntityID.IsDefined(this.m_tilucId) && this.IsSquadDefeated() {
                this.m_sys.HideWorldInteraction();
                jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
                this.m_sys.ActivateObjectiveWithPin(
                    53,
                    "quests/side_quest/chispa_ep05_quest",
                    "quests/side_quest/chispa_ep05_quest/phase_ep05",
                    "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract",
                    "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract/mp_ep05_rig",
                    "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract/desc_ep05_03",
                    this.AllPinPaths(),
                    true
                );
                qs.SetFact(n"chispa_ep05_stage", 3);
                if this.m_sys.m_isPlayingDialogueSequence {
                    this.m_pendingVictory = true;
                } else {
                    this.m_pendingVictory = false;
                    let steps: array<ref<ChispaSpeechStep>>;
                    ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.82));
                    this.m_sys.StartSpeechSequence(steps, 0);
                }
            }
            return distRigSq <= 256.00 ? 0.12 : 0.45;
        }

        if stage == 3 {
            this.m_sys.HideDialogChoices();
            if this.m_pendingStyleNet && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingStyleNet = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_style_net", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.48));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingStyleBallistic && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingStyleBallistic = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_style_ballistic", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.38));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingCryoBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingCryoBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_cryo_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.29));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingVictory && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingVictory = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep05_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.82));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
            this.m_sys.SyncObjectivePinLoop(
                53,
                "quests/side_quest/chispa_ep05_quest",
                "quests/side_quest/chispa_ep05_quest/phase_ep05",
                "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract",
                "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract/mp_ep05_rig",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let rigPos: Vector4 = this.m_spawned ? this.m_rigPos : this.GetRigPos();
            this.m_sys.UpdateFallbackMappin(
                53,
                "quests/side_quest/chispa_ep05_quest/phase_ep05/03_ep05_extract",
                new Vector4(rigPos.X, rigPos.Y, rigPos.Z + 1.55, 1.00),
                n"ch_mappin_ep05_rig",
                "CHISPA Ep. 5: Bóveda Sector Maestro #05"
            );
            let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigPos);
            if distSq <= 14.00 && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(61, n"ch_hub_ep05_rig_title", "NODO MAESTRO #05 // COASTVIEW", n"ch_act_claim_sec05", "Recuperar Sector Maestro #05 [C.H.I.S.P.A.]", false, distSq <= 7.84);
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
        if qs.GetFact(n"chispa_ep05_stage") < 1 {
            qs.SetFact(n"chispa_ep05_stage", 1);
            this.ActivateJournalQuest();
        }
        qs.SetFact(n"chispa_ep05_call_done", 0);
        this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 51);
    }

    public final func TeleportToPacifica() -> Void {
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
        if qs.GetFact(n"watson_prolog_lock") > 0 {
            this.m_sys.UnlockFullNightCityMap();
        }
        if qs.GetFact(n"chispa_ep05_stage") < 2 {
            this.ActivateJournalQuest();
            this.ActivateIntroSms();
            this.GrantStarterFinaleKit(player);
            jm.ChangeEntryState("quests/side_quest/chispa_ep05_quest/phase_ep05/01_ep05_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            this.m_sys.ActivateObjectiveWithPin(
                52,
                "quests/side_quest/chispa_ep05_quest",
                "quests/side_quest/chispa_ep05_quest/phase_ep05",
                "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear",
                "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear/mp_ep05_pacifica",
                "quests/side_quest/chispa_ep05_quest/phase_ep05/02_ep05_clear/desc_ep05_02",
                this.AllPinPaths(),
                true
            );
            qs.SetFact(n"chispa_ep05_call_done", 1);
            qs.SetFact(n"chispa_ep05_sms_replied", 52);
            qs.SetFact(n"chispa_ep05_stage", 2);
        }
        this.m_sys.EnsureSmartBridgeActive(player);
        this.m_sys.EnsureRicochetBridgeActive(player);
        let dest: Vector4 = this.GetArrivalPos();
        let ang: EulerAngles;
        ang.Yaw = 22.00;
        GameInstance.GetTeleportationFacility(game).Teleport(player, dest, ang);
        this.EnsureSpawned(player);
    }
}
