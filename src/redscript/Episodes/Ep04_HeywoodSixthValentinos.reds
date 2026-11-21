// Protocolo CHISPA / SPARKY Protocol — Episodio 4: «Honor, Chatarra y Patriotas de Cartón»
module ChispaNC

public class ChispaEp04Handler {
    private let m_sys: wref<ChispaSystem>;
    private let m_spawned: Bool;

    // Entidades estáticas: caja de contrabando (Arroyo), relé balístico, depósito explosivo NUSA y sector
    private let m_rigId: EntityID;
    private let m_sectorId: EntityID;
    private let m_relayId: EntityID;
    private let m_ammoTankId: EntityID;
    private let m_tankConfigured: Bool;

    // Célula fronteriza Calle 6 + enlace Valentinos
    private let m_buckId: EntityID;
    private let m_tammyId: EntityID;
    private let m_mateoId: EntityID;
    private let m_buckReady: Bool;
    private let m_tammyReady: Bool;
    private let m_mateoReady: Bool;

    // Telemetría de rebote, explosión y posiciones sobre suelo
    private let m_pendingRicochetBark: Bool;
    private let m_pendingCacheBoom: Bool;
    private let m_pendingRicochetVictory: Bool;
    private let m_pendingGunsBlazing: Bool;
    private let m_rigPos: Vector4;
    private let m_relayPos: Vector4;
    private let m_ammoTankPos: Vector4;
    private let m_combatStartedAt: Float;
    private let m_introWaitTicks: Int32;

    public final func Init(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
    }

    // Frontera Arroyo / Heywood (exterior_-15_-17_0_0 / -15_-16_0_0 — libre de mappins vanilla a Z=11.80m)
    public final func GetArrivalPos() -> Vector4 = new Vector4(-914.50, -1042.50, 11.88, 1.00);
    public final func GetRigPos() -> Vector4 = new Vector4(-913.50, -1022.40, 11.80, 1.00);
    public final func GetRelayPos() -> Vector4 = new Vector4(-907.80, -1028.80, 11.80, 1.00);
    public final func GetAmmoTankPos() -> Vector4 = new Vector4(-916.80, -1024.20, 11.80, 1.00);

    public final func ResetRuntimeFlags() -> Void {
        this.m_spawned = false;
        this.m_rigId = new EntityID();
        this.m_sectorId = new EntityID();
        this.m_relayId = new EntityID();
        this.m_ammoTankId = new EntityID();
        this.m_tankConfigured = false;
        this.m_buckId = new EntityID();
        this.m_tammyId = new EntityID();
        this.m_mateoId = new EntityID();
        this.m_buckReady = false;
        this.m_tammyReady = false;
        this.m_mateoReady = false;
        this.m_pendingRicochetBark = false;
        this.m_pendingCacheBoom = false;
        this.m_pendingRicochetVictory = false;
        this.m_pendingGunsBlazing = false;
        this.m_rigPos = this.GetRigPos();
        this.m_relayPos = this.GetRelayPos();
        this.m_ammoTankPos = this.GetAmmoTankPos();
        this.m_combatStartedAt = 0.00;
        this.m_introWaitTicks = 0;
    }

    private final func AllPinPaths() -> array<String> {
        return [
            "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/mp_ep04_border",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract/mp_ep04_rig"
        ];
    }

    public final func CleanupEntities() -> Void {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) {
            des.DeleteTagged(n"ChispaEp04Buck");
            des.DeleteTagged(n"ChispaEp04Tammy");
            des.DeleteTagged(n"ChispaEp04Mateo");
        }
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp04Rig");
            ses.DespawnTagged(n"ChispaEp04Sector");
            ses.DespawnTagged(n"ChispaEp04Relay");
            ses.DespawnTagged(n"ChispaEp04AmmoTank");
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
            "quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms/desc_ep04_01",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/desc_ep04_02",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract/desc_ep04_03",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/04_ep04_talk/desc_ep04_04",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/desc_ep04_done"
        ];
        for dp in descPaths {
            jm.ChangeEntryState(dp, "gameJournalQuestDescription", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        let objPaths: array<String> = [
            "quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/04_ep04_talk"
        ];
        for op in objPaths {
            jm.ChangeEntryState(op, "gameJournalQuestObjective", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04", "gameJournalQuestPhase", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest", "gameJournalQuest", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        let smsPaths: array<String> = [
            "contacts/chispa_ai/conv_ep04/msg_ep04_hook",
            "contacts/chispa_ai/conv_ep04/msg_ep04_gangs",
            "contacts/chispa_ai/conv_ep04/msg_ep04_coords",
            "contacts/chispa_ai/conv_ep04/msg_ep04_summary"
        ];
        for sp in smsPaths {
            jm.ChangeEntryState(sp, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/choices_ep04/reply_ep04_gangs", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/choices_ep04/reply_ep04_coords", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/choices_ep04", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04", "gameJournalPhoneConversation", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep04", "gameJournalOnscreen", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        qs.SetFact(n"chispa_ep04_call_done", 0);
        qs.SetFact(n"chispa_ep04_sms_replied", 0);
        qs.SetFact(n"chispa_ep04_approach_played", 0);
        qs.SetFact(n"chispa_ep04_scanned", 0);
        qs.SetFact(n"chispa_ep04_ricochet_used", 0);
        qs.SetFact(n"chispa_ep04_ricochet_bark", 0);
        qs.SetFact(n"chispa_ep04_cache_blown", 0);
        qs.SetFact(n"chispa_ep04_used_tactics", 0);
        qs.SetFact(n"chispa_ep04_combat_started", 0);
        qs.SetFact(n"chispa_ep04_asked_valentinos", 0);
        qs.SetFact(n"chispa_ep04_asked_sixth", 0);
        qs.SetFact(n"chispa_ep04_asked_chrome", 0);
        qs.SetFact(n"chispa_ep04_done", 0);
        qs.SetFact(n"chispa_ep04_stage", 0);
        qs.SetFact(n"chispa_ep04_xp_sector", 0);
        qs.SetFact(n"chispa_ep04_xp_done", 0);
        qs.SetFact(n"chispa_qh_ep04_cyber", 0);
    }

    // --- Holollamada e Hilo de SMS Inicial ---

    public final func GetCallSteps(stageTag: Int32, out completeAction: Int32) -> array<ref<ChispaSpeechStep>> {
        let steps: array<ref<ChispaSpeechStep>>;
        if !IsDefined(this.m_sys) || stageTag != 41 {
            return steps;
        }
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_call_01", n"phone", n"CHISPA", scnDialogLineType.Holocall, 10.17));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_v_call_01", n"player", n"V", scnDialogLineType.Regular, 5.94));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_call_02", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.62));
        completeAction = 501;
        return steps;
    }

    public final func OnCallRejected(stageTag: Int32) -> Void {
        if IsDefined(this.m_sys) && stageTag == 41 {
            GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance()).SetFact(n"chispa_ep04_call_done", 1);
            this.ActivateIntroSms();
        }
    }

    public final func OnPostSpeech(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if actionId == 501 {
            qs.SetFact(n"chispa_ep04_call_done", 1);
            this.m_sys.EndCustomCall(n"chispa_ai", this.m_sys.m_activeCallIsVideo);
            this.ActivateIntroSms();
            return;
        }
        if actionId == 509 || actionId == 510 || actionId == 511 || actionId == 512 {
            if qs.GetFact(n"chispa_ep04_stage") == 4 && !this.m_sys.IsUiBlockingWorldInput() {
                this.ShowDialogHub();
            }
            return;
        }
        if actionId == 520 {
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
        let qEntry: wref<JournalEntry> = jm.GetEntryByString("quests/side_quest/chispa_ep04_quest", "gameJournalQuest");
        if !IsDefined(qEntry) {
            return;
        }
        let qState: gameJournalEntryState = jm.GetEntryState(qEntry);
        if Equals(qState, gameJournalEntryState.Active) || Equals(qState, gameJournalEntryState.Succeeded) {
            return;
        }
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest", "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04", "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms/desc_ep04_01", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        if !IsDefined(jm.GetTrackedEntry()) {
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms");
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
        let msgEntry: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep04/msg_ep04_hook", "gameJournalPhoneMessage");
        if IsDefined(msgEntry) && Equals(jm.GetEntryState(msgEntry), gameJournalEntryState.Active) {
            return;
        }
        jm.ChangeEntryState("contacts/chispa_ai", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04", "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/msg_ep04_hook", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/choices_ep04", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/choices_ep04/reply_ep04_gangs", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/choices_ep04/reply_ep04_coords", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    }

    public final func CheckSmsReply() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(jm) || qs.GetFact(n"chispa_ep04_stage") != 1 || qs.GetFact(n"chispa_ep04_sms_replied") > 0 {
            return;
        }
        let rGangs: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep04/choices_ep04/reply_ep04_gangs", "gameJournalPhoneChoiceEntry");
        let rCoords: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep04/choices_ep04/reply_ep04_coords", "gameJournalPhoneChoiceEntry");

        let replyKind: Int32 = 0;
        if IsDefined(rGangs) && Equals(jm.GetEntryState(rGangs), gameJournalEntryState.Succeeded) {
            replyKind = 41;
        } else if IsDefined(rCoords) && Equals(jm.GetEntryState(rCoords), gameJournalEntryState.Succeeded) {
            replyKind = 42;
        }
        if replyKind == 0 {
            return;
        }

        qs.SetFact(n"chispa_ep04_sms_replied", replyKind);
        let cb: ref<ChispaSmsDelayCallback> = new ChispaSmsDelayCallback();
        cb.system = this.m_sys;
        cb.actionId = replyKind;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.90, false);
    }

    private final func GrantStarterPowerKit(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        if !IsDefined(ts) || !IsDefined(player) {
            return;
        }
        let granted: Bool = false;
        if !this.m_sys.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Copperhead_Default") {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Copperhead_Default"), 1);
            granted = true;
        }
        let fragQty: Int32 = ts.GetItemQuantity(player, ItemID.CreateQuery(t"Items.GrenadeFragRegular"));
        if fragQty < 2 {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.GrenadeFragRegular"), 2 - fragQty);
            granted = true;
        }
        let healQty: Int32 = ts.GetItemQuantity(player, ItemID.CreateQuery(t"Items.BonesMcCoy70V0"));
        if healQty < 2 {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.BonesMcCoy70V0"), 2 - healQty);
        }
        this.m_sys.EnsureRicochetBridgeActive(player);
        if granted {
            this.m_sys.ShowRelicBanner(n"ch_banner_ep04_gear", "[CHISPA] ¡Copperhead y visor de rebote activos! Ruta a Arroyo fijada");
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
        if actionId == 41 {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/msg_ep04_gangs", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        } else {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/msg_ep04_coords", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        }
        this.GrantStarterPowerKit(player);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        this.m_sys.ActivateObjectiveWithPin(
            42,
            "quests/side_quest/chispa_ep04_quest",
            "quests/side_quest/chispa_ep04_quest/phase_ep04",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/mp_ep04_border",
            "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/desc_ep04_02",
            this.AllPinPaths(),
            true
        );
        qs.SetFact(n"chispa_ep04_stage", 2);
    }

    // --- Escena Táctica Frontera Arroyo (Calle 6 + Valentinos) ---

    private final func EnsureSpawned(player: ref<PlayerPuppet>) -> Void {
        let rigBase: Vector4 = this.GetRigPos();
        let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigBase);
        if distSq > 4225.00 {
            return;
        }

        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep04_stage");
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();

        if IsDefined(ses) && ses.IsReady() {
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_rigId) {
                ses.DespawnTagged(n"ChispaEp04Rig");
                let zR: Float = this.m_sys.FindGroundZ(rigBase);
                this.m_rigPos = new Vector4(rigBase.X, rigBase.Y, zR, 1.00);
                this.m_rigId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep04_smuggler_rig.ent", n"", this.m_rigPos, 0.00, 180.00, n"ChispaEp04Rig");
            }
            if (stage == 2 || stage == 3) && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_sectorId) {
                ses.DespawnTagged(n"ChispaEp04Sector");
                let zR: Float = this.m_sys.FindGroundZ(rigBase);
                this.m_rigPos = new Vector4(rigBase.X, rigBase.Y, zR, 1.00);
                this.m_sectorId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep04_sector_module.ent", n"", this.m_rigPos, 0.00, 180.00, n"ChispaEp04Sector");
            }
            if qs.GetFact(n"chispa_ep04_cache_blown") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_relayId) {
                ses.DespawnTagged(n"ChispaEp04Relay");
                let relBase: Vector4 = this.GetRelayPos();
                let zRel: Float = this.m_sys.FindGroundZ(relBase);
                this.m_relayPos = new Vector4(relBase.X, relBase.Y, zRel, 1.00);
                this.m_relayId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep04_ballistic_relay.ent", n"", this.m_relayPos, 0.00, -140.00, n"ChispaEp04Relay");
            }
            if qs.GetFact(n"chispa_ep04_cache_blown") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_ammoTankId) {
                ses.DespawnTagged(n"ChispaEp04AmmoTank");
                this.m_tankConfigured = false;
                let tBase: Vector4 = this.GetAmmoTankPos();
                let zT: Float = this.m_sys.FindGroundZ(tBase);
                this.m_ammoTankPos = new Vector4(tBase.X, tBase.Y, zT, 1.00);
                this.m_ammoTankId = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\explosives\\fuel_tank_extended_streaming_range.ent", n"default", this.m_ammoTankPos, 0.00, 95.00, n"ChispaEp04AmmoTank");
            }
            if !this.m_tankConfigured && EntityID.IsDefined(this.m_ammoTankId) && ses.IsSpawned(this.m_ammoTankId) {
                let tankObj: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_ammoTankId) as ExplosiveDevice;
                if IsDefined(tankObj) && IsDefined(tankObj.GetDevicePS()) {
                    tankObj.GetDevicePS().ChispaConfigureExplosiveServer();
                    this.m_tankConfigured = true;
                }
            }
        }

        if stage == 2 {
            let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
            if IsDefined(des) && des.IsReady() {
                if !EntityID.IsDefined(this.m_buckId) && !this.m_sys.IsDynamicEntityAliveOrSpawning(this.m_buckId) {
                    des.DeleteTagged(n"ChispaEp04Buck");
                    des.DeleteTagged(n"ChispaEp04Tammy");
                    des.DeleteTagged(n"ChispaEp04Mateo");

                    let bXY: Vector4 = new Vector4(-915.20, -1025.00, rigBase.Z, 1.00);
                    let tXY: Vector4 = new Vector4(-911.20, -1025.80, rigBase.Z, 1.00);
                    let mXY: Vector4 = new Vector4(-913.80, -1027.20, rigBase.Z, 1.00);
                    let zB: Float = this.m_sys.FindGroundZ(bXY);
                    let zT: Float = this.m_sys.FindGroundZ(tXY);
                    let zM: Float = this.m_sys.FindGroundZ(mXY);

                    this.m_buckReady = false;
                    this.m_tammyReady = false;
                    this.m_mateoReady = false;
                    this.m_buckId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep04_Buck", new Vector4(bXY.X, bXY.Y, zB, 1.00), 180.00, n"ChispaEp04Buck");
                    this.m_tammyId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep04_Tammy", new Vector4(tXY.X, tXY.Y, zT, 1.00), 195.00, n"ChispaEp04Tammy");
                    this.m_mateoId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep04_Mateo", new Vector4(mXY.X, mXY.Y, zM, 1.00), 175.00, n"ChispaEp04Mateo");
                }
                if !this.m_buckReady && EntityID.IsDefined(this.m_buckId) && des.IsSpawned(this.m_buckId) {
                    let bNpc: ref<NPCPuppet> = des.GetEntity(this.m_buckId) as NPCPuppet;
                    if IsDefined(bNpc) && ScriptedPuppet.IsActive(bNpc) {
                        this.m_buckReady = true;
                    }
                }
                if !this.m_tammyReady && EntityID.IsDefined(this.m_tammyId) && des.IsSpawned(this.m_tammyId) {
                    let tNpc: ref<NPCPuppet> = des.GetEntity(this.m_tammyId) as NPCPuppet;
                    if IsDefined(tNpc) && ScriptedPuppet.IsActive(tNpc) {
                        this.m_tammyReady = true;
                    }
                }
                if !this.m_mateoReady && EntityID.IsDefined(this.m_mateoId) && des.IsSpawned(this.m_mateoId) {
                    let mNpc: ref<NPCPuppet> = des.GetEntity(this.m_mateoId) as NPCPuppet;
                    if IsDefined(mNpc) && ScriptedPuppet.IsActive(mNpc) {
                        this.m_mateoReady = true;
                    }
                }
            }
        }
        this.m_spawned = true;
    }

    // --- Telemetría de Rebote Balístico, Relé y Depósito NUSA ---

    public final func IsEp04AmmoTank(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && Equals(id, this.m_ammoTankId);
    }

    public final func IsEp04Npc(id: EntityID) -> Bool {
        return EntityID.IsDefined(id)
            && (Equals(id, this.m_buckId)
                || Equals(id, this.m_tammyId)
                || Equals(id, this.m_mateoId));
    }

    private final func IsEp04Target(id: EntityID) -> Bool {
        return this.IsEp04AmmoTank(id) || this.IsEp04Npc(id);
    }

    public final func OnTargetScanned(recID: TweakDBID) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep04_stage") != 2 {
            return;
        }
        if qs.GetFact(n"chispa_ep04_scanned") == 0 {
            qs.SetFact(n"chispa_ep04_scanned", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
        }
    }

    public final func OnRicochetHitLanded() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep04_stage") != 2 {
            return;
        }
        qs.SetFact(n"chispa_ep04_ricochet_used", 1);
        qs.SetFact(n"chispa_ep04_used_tactics", 1);
        if qs.GetFact(n"chispa_ep04_ricochet_bark") == 0 {
            qs.SetFact(n"chispa_ep04_ricochet_bark", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingRicochetBark = true;
            } else {
                this.m_pendingRicochetBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ricochet_hit", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.29));
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
        if qs.GetFact(n"chispa_ep04_stage") != 2 || !IsDefined(player) {
            return;
        }
        let nearBorder: Bool = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), this.GetRigPos()) <= 5625.00;
        if !this.IsEp04Target(actionOwner) && !nearBorder {
            return;
        }
        qs.SetFact(n"chispa_ep04_used_tactics", 1);
        if this.IsEp04Npc(actionOwner) {
            this.OnBorderSquadProvoked(player, true);
        }
    }

    private final func ApplyCacheBlastToSquad(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);

        this.m_sys.PlaySfx(n"ch_sfx_capacitor_arc");
        if IsDefined(des) {
            let tammy: ref<NPCPuppet> = des.GetEntity(this.m_tammyId) as NPCPuppet;
            if IsDefined(tammy) && !tammy.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(tammy, t"BaseStatusEffect.Burning");
                StatusEffectHelper.ApplyStatusEffect(tammy, t"BaseStatusEffect.Overload");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(tammy.GetEntityID()), gamedataStatPoolType.Health, -100.0, player, true, true);
                }
                tammy.Kill(player);
            }
            let buck: ref<NPCPuppet> = des.GetEntity(this.m_buckId) as NPCPuppet;
            if IsDefined(buck) && !buck.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(buck, t"BaseStatusEffect.Burning");
                StatusEffectHelper.ApplyStatusEffect(buck, t"BaseStatusEffect.Overload");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(buck.GetEntityID()), gamedataStatPoolType.Health, -55.0, player, true, true);
                }
            }
            let mateo: ref<NPCPuppet> = des.GetEntity(this.m_mateoId) as NPCPuppet;
            if IsDefined(mateo) && !mateo.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(mateo, t"BaseStatusEffect.Burning");
                StatusEffectHelper.ApplyStatusEffect(mateo, t"BaseStatusEffect.Overload");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(mateo.GetEntityID()), gamedataStatPoolType.Health, -65.0, player, true, true);
                }
            }
        }
        this.OnBorderSquadProvoked(player, true);
    }

    public final func OnAmmoTankDetonated() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep04_stage") != 2 || !IsDefined(player) || qs.GetFact(n"chispa_ep04_cache_blown") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep04_cache_blown", 1);
        qs.SetFact(n"chispa_ep04_used_tactics", 1);
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp04Relay");
        }
        this.m_relayId = new EntityID();

        this.m_sys.ShowRelicBanner(n"ch_banner_ep04_cache", "[CHISPA] ¡Relé balístico y depósito NUSA reventados!");
        this.ApplyCacheBlastToSquad(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingCacheBoom = true;
        } else {
            this.m_pendingCacheBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_cache_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.83));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func TriggerRelayOverload() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep04_cache_blown") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep04_cache_blown", 1);
        qs.SetFact(n"chispa_ep04_used_tactics", 1);

        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp04Relay");
        }
        this.m_relayId = new EntityID();

        if EntityID.IsDefined(this.m_ammoTankId) {
            let tankObj: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_ammoTankId) as ExplosiveDevice;
            if IsDefined(tankObj) && IsDefined(tankObj.GetDevicePS()) && !tankObj.GetDevicePS().IsExploded() {
                tankObj.QueueEvent(new ForceDetonate());
            }
        }
        this.m_sys.ShowRelicBanner(n"ch_banner_ep04_cache", "[CHISPA] ¡Relé balístico y depósito NUSA reventados!");
        this.ApplyCacheBlastToSquad(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingCacheBoom = true;
        } else {
            this.m_pendingCacheBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_cache_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.83));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func OnBorderSquadProvoked(player: ref<PlayerPuppet>, silent: Bool) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || qs.GetFact(n"chispa_ep04_stage") != 2 {
            return;
        }
        let alreadyCombat: Bool = qs.GetFact(n"chispa_ep04_combat_started") > 0;
        if !alreadyCombat {
            qs.SetFact(n"chispa_ep04_combat_started", 1);
            this.m_combatStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        }

        let buck: ref<NPCPuppet> = des.GetEntity(this.m_buckId) as NPCPuppet;
        let tammy: ref<NPCPuppet> = des.GetEntity(this.m_tammyId) as NPCPuppet;
        let mateo: ref<NPCPuppet> = des.GetEntity(this.m_mateoId) as NPCPuppet;
        if IsDefined(buck) && !buck.IsDead() {
            this.m_sys.MakeNpcHostile(buck, player);
            if !silent && !alreadyCombat && !this.m_sys.m_isPlayingDialogueSequence {
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_buck_bark", n"ChispaEp04Buck", n"Buck", scnDialogLineType.Regular, 6.02));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        if IsDefined(tammy) && !tammy.IsDead() {
            this.m_sys.MakeNpcHostile(tammy, player);
        }
        if IsDefined(mateo) && !mateo.IsDead() {
            this.m_sys.MakeNpcHostile(mateo, player);
        }
    }

    private final func IsSquadDefeated() -> Bool {
        if !EntityID.IsDefined(this.m_buckId) || !EntityID.IsDefined(this.m_tammyId) || !EntityID.IsDefined(this.m_mateoId) {
            return false;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep04_cache_blown") == 0 && (!this.m_buckReady || !this.m_tammyReady || !this.m_mateoReady) {
            return false;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let anchor: Vector4 = this.GetRigPos();
        if !IsDefined(player) || this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), anchor) > 3600.00 {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        let elapsed: Float = this.m_combatStartedAt > 0.01 ? (now - this.m_combatStartedAt) : 0.00;
        let buckDown: Bool = this.m_sys.IsNpcNeutralized(this.m_buckId, anchor, elapsed, false);
        let tammyDown: Bool = this.m_sys.IsNpcNeutralized(this.m_tammyId, anchor, elapsed, buckDown && elapsed >= 10.00 && !player.IsInCombat());
        let mateoDown: Bool = this.m_sys.IsNpcNeutralized(this.m_mateoId, anchor, elapsed, buckDown && elapsed >= 10.00 && !player.IsInCombat());
        return buckDown && tammyDown && mateoDown;
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

        if kind == 50 {
            this.TriggerRelayOverload();
            return true;
        }

        if kind == 51 {
            this.m_pendingRicochetBark = false;
            this.m_pendingCacheBoom = false;
            this.m_pendingRicochetVictory = false;
            this.m_pendingGunsBlazing = false;

            let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
            if IsDefined(ses) {
                ses.DespawnTagged(n"ChispaEp04Sector");
            }
            this.m_sectorId = new EntityID();

            let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector04"), 1);
            ts.GiveMoney(player, 4200, n"money");
            this.m_sys.AwardMilestoneProgram(player, n"chispa_qh_ep04_cyber", n"DisableCyberware", 3);
            this.m_sys.GiveItemDelayed(t"Items.Preset_Masamune_Chispa", 1, 1.15);
            this.m_sys.EnsureRicochetBridgeActive(player);
            GameObject.PlaySoundEvent(player, n"ui_loot_cash");
            this.m_sys.PlaySfx(n"ch_sfx_dongle_sync");
            this.m_sys.ShowRelicBanner(n"ch_banner_ep04_claimed", "[CHISPA] Sector #04 conectado (+4.200 €$, Fallo Ciberware y «Geometría Callejera»)");

            jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
            this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
            this.m_sys.ClearMappin();
            jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/04_ep04_talk/desc_ep04_04", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/04_ep04_talk", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep04_quest/phase_ep04/04_ep04_talk");
            qs.SetFact(n"chispa_ep04_stage", 4);
            this.m_sys.EnsureCoprocessorRamBridgeActive(player);
            this.m_sys.AwardMilestoneXP(n"chispa_ep04_xp_sector", 850, 1000, gamedataProficiencyType.ReflexesSkill, 400);

            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_sector_pickup", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.75));
            this.m_sys.StartSpeechSequence(steps, 509);
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

        if qs.GetFact(n"chispa_ep04_asked_valentinos") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep04_valentinos", "¿Cómo acabó Heywood tan metido entre el culto, el oro y las guerras de los Valentinos?"), false, false));
            ArrayPush(ids, 50);
        }
        if qs.GetFact(n"chispa_ep04_asked_sixth") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep04_sixth", "¿En qué momento pasó Calle 6 de veteranos vecinales a traficantes armados?"), false, false));
            ArrayPush(ids, 51);
        }
        if qs.GetFact(n"chispa_ep04_asked_chrome") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep04_chrome", "¿Cómo aguanta la gente de a pie tanta operación de cromo sin acabar desguazada por las deudas?"), false, false));
            ArrayPush(ids, 52);
        }
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep04_accept", "Recibido, Chispa. Vamos a cazar el último Sector #05 en Pacifica."), true, false));
        ArrayPush(ids, 53);

        this.m_sys.PushDialogHub(n"chispa_ep04", this.m_sys.GetLoc(n"ch_hub_ep04_talk_title", "C.H.I.S.P.A. // SECTOR #04 (Enlace Kiroshi)"), choices, ids);
    }

    public final func HandleDialogOption(optionId: Int32) -> Bool {
        if !IsDefined(this.m_sys) {
            return false;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        let steps: array<ref<ChispaSpeechStep>>;

        if optionId == 50 {
            qs.SetFact(n"chispa_ep04_asked_valentinos", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_v_ask_valentinos", n"player", n"V", scnDialogLineType.Regular, 4.81));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ans_valentinos", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.68));
            this.m_sys.StartSpeechSequence(steps, 510);
            return true;
        }
        if optionId == 51 {
            qs.SetFact(n"chispa_ep04_asked_sixth", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_v_ask_sixth", n"player", n"V", scnDialogLineType.Regular, 4.44));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ans_sixth", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.98));
            this.m_sys.StartSpeechSequence(steps, 511);
            return true;
        }
        if optionId == 52 {
            qs.SetFact(n"chispa_ep04_asked_chrome", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_v_ask_chrome", n"player", n"V", scnDialogLineType.Regular, 4.97));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ans_chrome", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.00));
            this.m_sys.StartSpeechSequence(steps, 512);
            return true;
        }
        if optionId == 53 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_v_outro_accept", n"player", n"V", scnDialogLineType.Regular, 6.41));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_outro", n"phone", n"CHISPA", scnDialogLineType.Holocall, 9.38));
            this.m_sys.StartSpeechSequence(steps, 520);
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

        jm.ChangeEntryState("contacts/chispa_ai/conv_ep04/msg_ep04_summary", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep04", "gameJournalOnscreen", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/04_ep04_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/desc_ep04_done", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);

        this.m_sys.ShowRelicBanner(n"ch_banner_ep04_done", "[CHISPA] Episodio 4 completado — Último rastro detectado en Pacifica");
        qs.SetFact(n"chispa_ep04_done", 1);
        qs.SetFact(n"chispa_season_stage", 500);
        qs.SetFact(n"chispa_ep04_stage", 5);
        this.m_sys.AwardMilestoneXP(n"chispa_ep04_xp_done", 1000, 1050, gamedataProficiencyType.Level, 0);
    }

    public final func Tick(player: ref<PlayerPuppet>, phoneOpen: Bool, fullGameplay: Bool) -> Float {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep04_stage");

        if qs.GetFact(n"chispa_ep04_done") == 0 && stage == 0 {
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
                this.m_sys.ShowRelicBanner(n"ch_banner_ep04_start", "[CHISPA] Puentes abiertos — Eco del Sector #04 en Arroyo");
                qs.SetFact(n"chispa_ep04_stage", 1);
                qs.SetFact(n"chispa_ep04_call_done", 0);
                if !this.m_sys.m_activeCallPendingPickup {
                    this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 41);
                }
            }
            return 0.60;
        }

        if stage == 1 {
            this.ActivateJournalQuest();
            this.CheckSmsReply();
            if qs.GetFact(n"chispa_ep04_call_done") == 0
                && !this.m_sys.m_activeCallPendingPickup
                && !this.m_sys.m_isPlayingDialogueSequence
                && this.m_sys.m_sessionReadyTicks >= 6
                && fullGameplay
                && this.m_sys.HasLiftedWatsonLockdown(player)
                && !this.m_sys.IsExternalPhoneCallBusy() {
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 41);
            }
            return 0.25;
        }

        if stage == 2 {
            this.m_sys.HideDialogChoices();
            this.m_sys.SyncObjectivePinLoop(
                42,
                "quests/side_quest/chispa_ep04_quest",
                "quests/side_quest/chispa_ep04_quest/phase_ep04",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/mp_ep04_border",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let relayPos: Vector4 = this.m_spawned ? this.m_relayPos : this.GetRelayPos();
            let rigPos: Vector4 = this.m_spawned ? this.m_rigPos : this.GetRigPos();
            this.m_sys.UpdateFallbackMappin(
                42,
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear",
                new Vector4(rigPos.X, rigPos.Y - 3.40, rigPos.Z + 1.55, 1.00),
                n"ch_mappin_ep04_border",
                "CHISPA Ep. 4: Patio de Contrabando (Arroyo)"
            );

            let distRigSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigPos);
            if distRigSq <= 1024.00 && qs.GetFact(n"chispa_ep04_approach_played") == 0 && !this.m_sys.m_isPlayingDialogueSequence {
                qs.SetFact(n"chispa_ep04_approach_played", 1);
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_approach", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.26));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            if this.m_pendingRicochetBark && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingRicochetBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ricochet_hit", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.29));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingCacheBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingCacheBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_cache_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.83));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            let centerCombatPos: Vector4 = new Vector4(-913.50, -1025.80, rigPos.Z, 1.00);
            if this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), centerCombatPos) <= 56.25 && qs.GetFact(n"chispa_ep04_combat_started") == 0 {
                this.OnBorderSquadProvoked(player, false);
            }

            let distRelaySq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), relayPos);
            let scannedFlag: Bool = qs.GetFact(n"chispa_ep04_scanned") > 0;
            let canReachRelay: Bool = qs.GetFact(n"chispa_ep04_cache_blown") == 0
                && ((scannedFlag && distRelaySq <= 324.00) || distRelaySq <= 64.00);
            if canReachRelay && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(50, n"ch_hub_ep04_relay_title", "RELÉ BALÍSTICO // CALLE 6", n"ch_act_overload_ep04", "Sobrecargar relé hacia el depósito de munición NUSA [Kiroshi]", false);
            } else {
                this.m_sys.HideWorldInteraction();
            }

            if EntityID.IsDefined(this.m_buckId) && this.IsSquadDefeated() {
                this.m_sys.HideWorldInteraction();
                jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
                this.m_sys.ActivateObjectiveWithPin(
                    43,
                    "quests/side_quest/chispa_ep04_quest",
                    "quests/side_quest/chispa_ep04_quest/phase_ep04",
                    "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract",
                    "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract/mp_ep04_rig",
                    "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract/desc_ep04_03",
                    this.AllPinPaths(),
                    true
                );
                qs.SetFact(n"chispa_ep04_stage", 3);
                let usedTactical: Bool = qs.GetFact(n"chispa_ep04_ricochet_used") > 0 || qs.GetFact(n"chispa_ep04_cache_blown") > 0;
                if this.m_sys.m_isPlayingDialogueSequence {
                    this.m_pendingRicochetVictory = usedTactical;
                    this.m_pendingGunsBlazing = !usedTactical;
                } else if usedTactical {
                    let steps: array<ref<ChispaSpeechStep>>;
                    ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ricochet_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.90));
                    this.m_sys.StartSpeechSequence(steps, 0);
                } else {
                    let steps: array<ref<ChispaSpeechStep>>;
                    ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 8.36));
                    this.m_sys.StartSpeechSequence(steps, 0);
                }
            }
            return distRigSq <= 256.00 ? 0.12 : 0.45;
        }

        if stage == 3 {
            this.m_sys.HideDialogChoices();
            if this.m_pendingRicochetBark && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingRicochetBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ricochet_hit", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.29));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingCacheBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingCacheBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_cache_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 6.83));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingRicochetVictory && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingRicochetVictory = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_ricochet_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 7.90));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingGunsBlazing && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingGunsBlazing = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep04_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 8.36));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
            this.m_sys.SyncObjectivePinLoop(
                43,
                "quests/side_quest/chispa_ep04_quest",
                "quests/side_quest/chispa_ep04_quest/phase_ep04",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract/mp_ep04_rig",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let rigPos: Vector4 = this.m_spawned ? this.m_rigPos : this.GetRigPos();
            this.m_sys.UpdateFallbackMappin(
                43,
                "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract",
                new Vector4(rigPos.X, rigPos.Y, rigPos.Z + 1.55, 1.00),
                n"ch_mappin_ep04_rig",
                "CHISPA Ep. 4: Alijo Fronterizo"
            );
            let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigPos);
            if distSq <= 14.00 && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(51, n"ch_hub_ep04_rig_title", "ALIJO FRONTERIZO // ARROYO", n"ch_act_claim_sec04", "Extraer Sector de Memoria #04 [C.H.I.S.P.A.]", false, distSq <= 7.84);
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
        if qs.GetFact(n"chispa_ep04_stage") < 1 {
            qs.SetFact(n"chispa_ep04_stage", 1);
            this.ActivateJournalQuest();
        }
        qs.SetFact(n"chispa_ep04_call_done", 0);
        this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 41);
    }

    public final func TeleportToBorder() -> Void {
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
        if qs.GetFact(n"chispa_ep04_stage") < 2 {
            this.ActivateJournalQuest();
            this.ActivateIntroSms();
            this.GrantStarterPowerKit(player);
            jm.ChangeEntryState("quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            this.m_sys.ActivateObjectiveWithPin(
                42,
                "quests/side_quest/chispa_ep04_quest",
                "quests/side_quest/chispa_ep04_quest/phase_ep04",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/mp_ep04_border",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/desc_ep04_02",
                this.AllPinPaths(),
                true
            );
            qs.SetFact(n"chispa_ep04_call_done", 1);
            qs.SetFact(n"chispa_ep04_sms_replied", 42);
            qs.SetFact(n"chispa_ep04_stage", 2);
        }
        this.m_sys.EnsureRicochetBridgeActive(player);
        let dest: Vector4 = this.GetArrivalPos();
        let ang: EulerAngles;
        ang.Yaw = 0.00;
        GameInstance.GetTeleportationFacility(game).Teleport(player, dest, ang);
        this.EnsureSpawned(player);
    }
}
