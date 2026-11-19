// Protocolo CHISPA / SPARKY Protocol — Episodio 2: «Más Hierro que Carne»
module ChispaNC

public class ChispaEp02Handler {
    private let m_sys: wref<ChispaSystem>;
    private let m_spawned: Bool;

    // Entidades estáticas, torreta y depósito explosivo CHOOH2 (Northside Docks)
    private let m_regulatorId: EntityID;
    private let m_plinthId: EntityID;
    private let m_turretId: EntityID;
    private let m_fuelTankId: EntityID;
    private let m_rigId: EntityID;
    private let m_sectorId: EntityID;
    private let m_turretConfigured: Bool;
    private let m_turretCombatArmed: Bool;

    // Cuadrilla Maelstrom
    private let m_kragId: EntityID;
    private let m_vexId: EntityID;
    private let m_tuercaId: EntityID;
    private let m_kragReady: Bool;
    private let m_vexReady: Bool;
    private let m_tuercaReady: Bool;

    // Cola de locuciones no solapadas y posiciones reales sobre suelo
    private let m_pendingTurretBark: Bool;
    private let m_pendingTankBoom: Bool;
    private let m_pendingTechVictory: Bool;
    private let m_pendingGunsBlazing: Bool;
    private let m_regulatorPos: Vector4;
    private let m_plinthPos: Vector4;
    private let m_fuelTankPos: Vector4;
    private let m_rigPos: Vector4;
    private let m_combatStartedAt: Float;
    private let m_introWaitTicks: Int32;

    public final func Init(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
        this.ResetRuntimeFlags();
    }

    public final func GetArrivalPos() -> Vector4 = new Vector4(-1549.50, 2642.50, 7.20, 1.00);
    public final func GetRegulatorPos() -> Vector4 = new Vector4(-1555.80, 2647.80, 7.15, 1.00);
    public final func GetPlinthPos() -> Vector4 = new Vector4(-1559.60, 2651.20, 7.15, 1.00);
    public final func GetFuelTankPos() -> Vector4 = new Vector4(-1558.60, 2655.40, 7.15, 1.00);
    public final func GetRigPos() -> Vector4 = new Vector4(-1556.90, 2659.20, 7.15, 1.00);

    public final func ResetRuntimeFlags() -> Void {
        this.m_spawned = false;
        this.m_regulatorId = new EntityID();
        this.m_plinthId = new EntityID();
        this.m_turretId = new EntityID();
        this.m_fuelTankId = new EntityID();
        this.m_rigId = new EntityID();
        this.m_sectorId = new EntityID();
        this.m_turretConfigured = false;
        this.m_turretCombatArmed = false;
        this.m_kragId = new EntityID();
        this.m_vexId = new EntityID();
        this.m_tuercaId = new EntityID();
        this.m_kragReady = false;
        this.m_vexReady = false;
        this.m_tuercaReady = false;
        this.m_pendingTurretBark = false;
        this.m_pendingTankBoom = false;
        this.m_pendingTechVictory = false;
        this.m_pendingGunsBlazing = false;
        this.m_regulatorPos = this.GetRegulatorPos();
        this.m_plinthPos = this.GetPlinthPos();
        this.m_fuelTankPos = this.GetFuelTankPos();
        this.m_rigPos = this.GetRigPos();
        this.m_combatStartedAt = 0.00;
        this.m_introWaitTicks = 0;
    }

    private final func AllPinPaths() -> array<String> {
        return [
            "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/mp_ep02_northside",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract/mp_ep02_rig"
        ];
    }

    public final func CleanupEntities() -> Void {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) {
            des.DeleteTagged(n"ChispaEp02Krag");
            des.DeleteTagged(n"ChispaEp02Vex");
            des.DeleteTagged(n"ChispaEp02Tuerca");
        }
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp02Regulator");
            ses.DespawnTagged(n"ChispaEp02Plinth");
            ses.DespawnTagged(n"ChispaEp02Turret");
            ses.DespawnTagged(n"ChispaEp02FuelTank");
            ses.DespawnTagged(n"ChispaEp02Rig");
            ses.DespawnTagged(n"ChispaEp02Sector");
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
            "quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms/desc_ep02_01",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/desc_ep02_02",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract/desc_ep02_03",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk/desc_ep02_04",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/desc_ep02_done"
        ];
        for dp in descPaths {
            jm.ChangeEntryState(dp, "gameJournalQuestDescription", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        let objPaths: array<String> = [
            "quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk"
        ];
        for op in objPaths {
            jm.ChangeEntryState(op, "gameJournalQuestObjective", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02", "gameJournalQuestPhase", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest", "gameJournalQuest", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        let smsPaths: array<String> = [
            "contacts/chispa_ai/conv_ep02/msg_ep02_hook",
            "contacts/chispa_ai/conv_ep02/msg_ep02_cult",
            "contacts/chispa_ai/conv_ep02/msg_ep02_docks",
            "contacts/chispa_ai/conv_ep02/msg_ep02_summary"
        ];
        for sp in smsPaths {
            jm.ChangeEntryState(sp, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/choices_ep02/reply_ep02_cult", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/choices_ep02/reply_ep02_docks", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/choices_ep02", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02", "gameJournalPhoneConversation", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep02", "gameJournalOnscreen", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        qs.SetFact(n"chispa_ep02_call_done", 0);
        qs.SetFact(n"chispa_ep02_sms_replied", 0);
        qs.SetFact(n"chispa_ep02_approach_played", 0);
        qs.SetFact(n"chispa_ep02_scanned", 0);
        qs.SetFact(n"chispa_ep02_turret_hacked", 0);
        qs.SetFact(n"chispa_ep02_tank_blown", 0);
        qs.SetFact(n"chispa_ep02_reg_purged", 0);
        qs.SetFact(n"chispa_ep02_used_tech", 0);
        qs.SetFact(n"chispa_ep02_combat_started", 0);
        qs.SetFact(n"chispa_ep02_asked_maelstrom", 0);
        qs.SetFact(n"chispa_ep02_asked_psycho", 0);
        qs.SetFact(n"chispa_ep02_asked_maxtac", 0);
        qs.SetFact(n"chispa_ep02_done", 0);
        qs.SetFact(n"chispa_ep02_stage", 0);
    }

    // --- Callbacks de Audio, Llamadas y SMS ---

    public final func GetCallSteps(stageTag: Int32, out completeAction: Int32) -> array<ref<ChispaSpeechStep>> {
        let steps: array<ref<ChispaSpeechStep>>;
        if !IsDefined(this.m_sys) || stageTag != 21 {
            return steps;
        }
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_call_01", n"phone", n"CHISPA", scnDialogLineType.Holocall, 13.66));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_v_call_01", n"player", n"V", scnDialogLineType.Regular, 6.54));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_call_02", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.34));
        completeAction = 301;
        return steps;
    }

    public final func OnCallRejected(stageTag: Int32) -> Void {
        if IsDefined(this.m_sys) && stageTag == 21 {
            GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance()).SetFact(n"chispa_ep02_call_done", 1);
            this.ActivateIntroSms();
        }
    }

    public final func OnPostSpeech(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if actionId == 301 {
            qs.SetFact(n"chispa_ep02_call_done", 1);
            this.m_sys.EndCustomCall(n"chispa_ai", this.m_sys.m_activeCallIsVideo);
            this.ActivateIntroSms();
            return;
        }
        if actionId == 309 || actionId == 310 || actionId == 311 || actionId == 312 {
            if qs.GetFact(n"chispa_ep02_stage") == 4 && !this.m_sys.IsUiBlockingWorldInput() {
                this.ShowDialogHub();
            }
            return;
        }
        if actionId == 320 {
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
        let qEntry: wref<JournalEntry> = jm.GetEntryByString("quests/side_quest/chispa_ep02_quest", "gameJournalQuest");
        if !IsDefined(qEntry) {
            return;
        }
        let qState: gameJournalEntryState = jm.GetEntryState(qEntry);
        if Equals(qState, gameJournalEntryState.Active) || Equals(qState, gameJournalEntryState.Succeeded) {
            return;
        }
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest", "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02", "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms/desc_ep02_01", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        if !IsDefined(jm.GetTrackedEntry()) {
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms");
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
        let msgEntry: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep02/msg_ep02_hook", "gameJournalPhoneMessage");
        if IsDefined(msgEntry) && Equals(jm.GetEntryState(msgEntry), gameJournalEntryState.Active) {
            return;
        }
        jm.ChangeEntryState("contacts/chispa_ai", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02", "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/msg_ep02_hook", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/choices_ep02", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/choices_ep02/reply_ep02_cult", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/choices_ep02/reply_ep02_docks", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    }

    public final func CheckSmsReply() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(jm) || qs.GetFact(n"chispa_ep02_stage") != 1 || qs.GetFact(n"chispa_ep02_sms_replied") > 0 {
            return;
        }
        let rCult: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep02/choices_ep02/reply_ep02_cult", "gameJournalPhoneChoiceEntry");
        let rDocks: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep02/choices_ep02/reply_ep02_docks", "gameJournalPhoneChoiceEntry");

        let replyKind: Int32 = 0;
        if IsDefined(rCult) && Equals(jm.GetEntryState(rCult), gameJournalEntryState.Succeeded) {
            replyKind = 21;
        } else if IsDefined(rDocks) && Equals(jm.GetEntryState(rDocks), gameJournalEntryState.Succeeded) {
            replyKind = 22;
        }
        if replyKind == 0 {
            return;
        }

        qs.SetFact(n"chispa_ep02_sms_replied", replyKind);
        let cb: ref<ChispaSmsDelayCallback> = new ChispaSmsDelayCallback();
        cb.system = this.m_sys;
        cb.actionId = replyKind;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.90, false);
    }

    private final func GrantStarterTacticalKit(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        if !IsDefined(ts) || !IsDefined(player) {
            return;
        }
        let granted: Bool = false;
        if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.GrenadeEMPRegular")) == 0 {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.GrenadeEMPRegular"), 1);
            granted = true;
        }
        let hasGlitch: Bool = ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.WeaponMalfunctionProgram")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.WeaponMalfunctionLvl2Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.WeaponMalfunctionLvl3Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.WeaponMalfunctionLvl4Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.WeaponMalfunctionLvl4PlusPlusProgram")) > 0;
        if !hasGlitch {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.WeaponMalfunctionLvl2Program"), 1);
            granted = true;
        }
        if granted {
            this.m_sys.ShowRelicBanner(n"ch_banner_ep02_gear", "[CHISPA] ¡Granada PEM y Avería de Armas cargadas! Ruta a Northside activa");
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
        if actionId == 21 {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/msg_ep02_cult", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        } else {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/msg_ep02_docks", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        }
        this.GrantStarterTacticalKit(player);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        this.m_sys.ActivateObjectiveWithPin(
            22,
            "quests/side_quest/chispa_ep02_quest",
            "quests/side_quest/chispa_ep02_quest/phase_ep02",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/mp_ep02_northside",
            "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/desc_ep02_02",
            this.AllPinPaths(),
            true
        );
        qs.SetFact(n"chispa_ep02_stage", 2);
    }

    // --- Escena Táctica del Muelle de Northside ---

    private final func EnsureSpawned(player: ref<PlayerPuppet>) -> Void {
        let regBase: Vector4 = this.GetRegulatorPos();
        let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), regBase);
        if distSq > 4225.00 {
            return;
        }

        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep02_stage");
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();

        if IsDefined(ses) && ses.IsReady() {
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_plinthId) {
                ses.DespawnTagged(n"ChispaEp02Plinth");
                let pBase: Vector4 = this.GetPlinthPos();
                let zP: Float = this.m_sys.FindGroundZ(pBase);
                this.m_plinthPos = new Vector4(pBase.X, pBase.Y, zP, 1.00);
                this.m_plinthId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep02_turret_plinth.ent", n"", this.m_plinthPos, 0.00, 140.00, n"ChispaEp02Plinth");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_turretId) {
                ses.DespawnTagged(n"ChispaEp02Turret");
                this.m_turretConfigured = false;
                this.m_turretCombatArmed = false;
                let pBase: Vector4 = this.GetPlinthPos();
                let zP: Float = this.m_sys.FindGroundZ(pBase);
                this.m_plinthPos = new Vector4(pBase.X, pBase.Y, zP, 1.00);
                let tPos: Vector4 = new Vector4(pBase.X, pBase.Y, zP + 1.045, 1.00);
                this.m_turretId = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\security_systems\\security_turret\\security_turret_1_nav.ent", n"security_turret_1_default", tPos, 0.00, 140.00, n"ChispaEp02Turret");
            }
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_rigId) {
                ses.DespawnTagged(n"ChispaEp02Rig");
                let rBase: Vector4 = this.GetRigPos();
                let zR: Float = this.m_sys.FindGroundZ(rBase);
                this.m_rigPos = new Vector4(rBase.X, rBase.Y, zR, 1.00);
                this.m_rigId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep02_maelstrom_rig.ent", n"", this.m_rigPos, 0.00, -140.00, n"ChispaEp02Rig");
            }
            if (stage == 2 || stage == 3) && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_sectorId) {
                ses.DespawnTagged(n"ChispaEp02Sector");
                let rBase: Vector4 = this.GetRigPos();
                let zR: Float = this.m_sys.FindGroundZ(rBase);
                this.m_rigPos = new Vector4(rBase.X, rBase.Y, zR, 1.00);
                this.m_sectorId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep02_sector_module.ent", n"", this.m_rigPos, 0.00, -140.00, n"ChispaEp02Sector");
            }
            if qs.GetFact(n"chispa_ep02_reg_purged") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_regulatorId) {
                ses.DespawnTagged(n"ChispaEp02Regulator");
                let zReg: Float = this.m_sys.FindGroundZ(regBase);
                this.m_regulatorPos = new Vector4(regBase.X, regBase.Y, zReg, 1.00);
                this.m_regulatorId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep02_power_regulator.ent", n"", this.m_regulatorPos, 0.00, -40.00, n"ChispaEp02Regulator");
            }
            if qs.GetFact(n"chispa_ep02_tank_blown") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_fuelTankId) {
                ses.DespawnTagged(n"ChispaEp02FuelTank");
                let ftBase: Vector4 = this.GetFuelTankPos();
                let zFt: Float = this.m_sys.FindGroundZ(ftBase);
                this.m_fuelTankPos = new Vector4(ftBase.X, ftBase.Y, zFt, 1.00);
                this.m_fuelTankId = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\explosives\\fuel_tank_extended_streaming_range.ent", n"fuel_tank_appearances_default", this.m_fuelTankPos, 0.00, -135.00, n"ChispaEp02FuelTank");
            }

            if !this.m_turretConfigured && EntityID.IsDefined(this.m_turretId) && ses.IsSpawned(this.m_turretId) {
                let turret: ref<SecurityTurret> = GameInstance.FindEntityByID(game, this.m_turretId) as SecurityTurret;
                if IsDefined(turret) && IsDefined(turret.GetDevicePS()) {
                    let ps: ref<SecurityTurretControllerPS> = turret.GetDevicePS() as SecurityTurretControllerPS;
                    if IsDefined(ps) {
                        if qs.GetFact(n"chispa_ep02_turret_hacked") > 0 || stage > 2 {
                            ps.ChispaDisableSecurityTurret();
                        } else {
                            let combatActive: Bool = qs.GetFact(n"chispa_ep02_combat_started") > 0;
                            ps.ChispaConfigureSecurityTurret(combatActive);
                            this.m_turretCombatArmed = combatActive;
                        }
                        this.m_turretConfigured = true;
                    }
                }
            }
        }

        if stage == 2 {
            let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
            if IsDefined(des) && des.IsReady() {
                if !EntityID.IsDefined(this.m_kragId) && !this.m_sys.IsDynamicEntityAliveOrSpawning(this.m_kragId) {
                    des.DeleteTagged(n"ChispaEp02Krag");
                    des.DeleteTagged(n"ChispaEp02Vex");
                    des.DeleteTagged(n"ChispaEp02Tuerca");

                    let kXY: Vector4 = new Vector4(-1557.20, 2657.20, regBase.Z, 1.00);
                    let vXY: Vector4 = new Vector4(-1554.90, 2654.20, regBase.Z, 1.00);
                    let tXY: Vector4 = new Vector4(-1559.10, 2654.20, regBase.Z, 1.00);
                    let zK: Float = this.m_sys.FindGroundZ(kXY);
                    let zV: Float = this.m_sys.FindGroundZ(vXY);
                    let zT: Float = this.m_sys.FindGroundZ(tXY);

                    this.m_kragReady = false;
                    this.m_vexReady = false;
                    this.m_tuercaReady = false;
                    this.m_kragId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep02_Krag", new Vector4(kXY.X, kXY.Y, zK, 1.00), -140.00, n"ChispaEp02Krag");
                    this.m_vexId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep02_Vex", new Vector4(vXY.X, vXY.Y, zV, 1.00), -150.00, n"ChispaEp02Vex");
                    this.m_tuercaId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep02_Tuerca", new Vector4(tXY.X, tXY.Y, zT, 1.00), 160.00, n"ChispaEp02Tuerca");
                }
                if !this.m_kragReady && EntityID.IsDefined(this.m_kragId) && des.IsSpawned(this.m_kragId) {
                    let kNpc: ref<NPCPuppet> = des.GetEntity(this.m_kragId) as NPCPuppet;
                    if IsDefined(kNpc) && ScriptedPuppet.IsActive(kNpc) {
                        this.m_kragReady = true;
                    }
                }
                if !this.m_vexReady && EntityID.IsDefined(this.m_vexId) && des.IsSpawned(this.m_vexId) {
                    let vNpc: ref<NPCPuppet> = des.GetEntity(this.m_vexId) as NPCPuppet;
                    if IsDefined(vNpc) && ScriptedPuppet.IsActive(vNpc) {
                        this.m_vexReady = true;
                    }
                }
                if !this.m_tuercaReady && EntityID.IsDefined(this.m_tuercaId) && des.IsSpawned(this.m_tuercaId) {
                    let tNpc: ref<NPCPuppet> = des.GetEntity(this.m_tuercaId) as NPCPuppet;
                    if IsDefined(tNpc) && ScriptedPuppet.IsActive(tNpc) {
                        this.m_tuercaReady = true;
                    }
                }
            }
        }
        this.m_spawned = true;
    }

    // --- Telemetría de Torreta, Tanque CHOOH2, Hackeos y Regulador ---

    public final func IsEp02Turret(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && Equals(id, this.m_turretId);
    }

    public final func IsEp02FuelTank(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && Equals(id, this.m_fuelTankId);
    }

    private final func IsEp02Target(id: EntityID) -> Bool {
        return EntityID.IsDefined(id)
            && (Equals(id, this.m_turretId)
                || Equals(id, this.m_fuelTankId)
                || Equals(id, this.m_kragId)
                || Equals(id, this.m_vexId)
                || Equals(id, this.m_tuercaId));
    }

    private final func DisableEp02TurretNow() -> Void {
        if !EntityID.IsDefined(this.m_turretId) || !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let turret: ref<SecurityTurret> = GameInstance.FindEntityByID(game, this.m_turretId) as SecurityTurret;
        if IsDefined(turret) {
            let ps: ref<SecurityTurretControllerPS> = turret.GetDevicePS() as SecurityTurretControllerPS;
            if IsDefined(ps) {
                ps.ChispaDisableSecurityTurret();
            }
        }
    }

    public final func OnTargetScanned(recID: TweakDBID) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep02_stage") != 2 {
            return;
        }
        if qs.GetFact(n"chispa_ep02_scanned") == 0 {
            qs.SetFact(n"chispa_ep02_scanned", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
        }
    }

    public final func OnTurretSubverted(isPhysicalOrKill: Bool, isFriendlyHack: Bool) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep02_stage") != 2 || !IsDefined(player) {
            return;
        }
        qs.SetFact(n"chispa_ep02_used_tech", 1);

        if isPhysicalOrKill {
            this.DisableEp02TurretNow();
        }
        if isFriendlyHack {
            let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
            let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);
            if IsDefined(des) {
                let ids: array<EntityID> = [this.m_tuercaId, this.m_vexId, this.m_kragId];
                let dmgs: array<Float> = [-75.0, -55.0, -45.0];
                let i: Int32 = 0;
                while i < ArraySize(ids) {
                    let npc: ref<NPCPuppet> = des.GetEntity(ids[i]) as NPCPuppet;
                    if IsDefined(npc) && !npc.IsDead() {
                        StatusEffectHelper.ApplyStatusEffect(npc, t"BaseStatusEffect.Overload");
                        if IsDefined(poolSys) {
                            poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(npc.GetEntityID()), gamedataStatPoolType.Health, dmgs[i], player, true, true);
                        }
                    }
                    i += 1;
                }
            }
            this.OnMaelstromProvoked(player, true);
        }

        if qs.GetFact(n"chispa_ep02_turret_hacked") == 0 {
            qs.SetFact(n"chispa_ep02_turret_hacked", 1);
            this.m_sys.PlaySfx(n"ch_sfx_net_breach");
            this.m_sys.ShowRelicBanner(n"ch_banner_ep02_turret", "[CHISPA] ¡Torreta Maelstrom saboteada! Defensa automática neutralizada");
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingTurretBark = true;
            } else {
                this.m_pendingTurretBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_turret_hijack", n"phone", n"CHISPA", scnDialogLineType.Holocall, 10.86));
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
        if qs.GetFact(n"chispa_ep02_stage") != 2 || !IsDefined(player) {
            return;
        }
        let nearNorthside: Bool = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), this.GetRegulatorPos()) <= 5625.00;
        if !this.IsEp02Target(actionOwner) && !nearNorthside {
            return;
        }

        if Equals(actionOwner, this.m_turretId) {
            if Equals(actionClassName, n"ToggleTakeOverControl") || Equals(objectActionID, t"DeviceAction.TakeControlClassHack") {
                this.OnTurretSubverted(false, false);
                return;
            }
            let isFriendly: Bool = Equals(actionClassName, n"SetDeviceAttitude")
                || Equals(objectActionID, t"DeviceAction.TurretOverrideAttitudeClassHack")
                || Equals(objectActionID, t"DeviceAction.TurretOverrideAttitudeClassLvl5Hack");
            if isFriendly {
                this.OnTurretSubverted(false, true);
                return;
            }
            let isOff: Bool = Equals(actionClassName, n"QuickHackToggleON")
                || Equals(objectActionID, t"DeviceAction.TurretToggleStateClassHack")
                || Equals(objectActionID, t"DeviceAction.TurretToggleStateClassLvl2Hack")
                || Equals(objectActionID, t"DeviceAction.TurretToggleStateClassLvl3Hack")
                || Equals(objectActionID, t"DeviceAction.TurretToggleStateClassLvl4Hack")
                || Equals(objectActionID, t"DeviceAction.TurretToggleStateClassLvl5Hack");
            if isOff {
                this.OnTurretSubverted(true, false);
                return;
            }
        }

        qs.SetFact(n"chispa_ep02_used_tech", 1);
        if Equals(actionOwner, this.m_kragId) || Equals(actionOwner, this.m_vexId) || Equals(actionOwner, this.m_tuercaId) {
            this.OnMaelstromProvoked(player, true);
        }
    }

    private final func ApplyChooh2BlastDamage(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);

        this.m_sys.PlaySfx(n"ch_sfx_capacitor_arc");
        if IsDefined(des) {
            let tuerca: ref<NPCPuppet> = des.GetEntity(this.m_tuercaId) as NPCPuppet;
            if IsDefined(tuerca) && !tuerca.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(tuerca, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(tuerca, t"BaseStatusEffect.Burning");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(tuerca.GetEntityID()), gamedataStatPoolType.Health, -100.0, player, true, true);
                }
                tuerca.Kill(player);
            }
            let vex: ref<NPCPuppet> = des.GetEntity(this.m_vexId) as NPCPuppet;
            if IsDefined(vex) && !vex.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(vex, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(vex, t"BaseStatusEffect.Burning");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(vex.GetEntityID()), gamedataStatPoolType.Health, -70.0, player, true, true);
                }
            }
            let krag: ref<NPCPuppet> = des.GetEntity(this.m_kragId) as NPCPuppet;
            if IsDefined(krag) && !krag.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(krag, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(krag, t"BaseStatusEffect.Burning");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(krag.GetEntityID()), gamedataStatPoolType.Health, -60.0, player, true, true);
                }
            }
        }
        this.OnMaelstromProvoked(player, true);
    }

    public final func OnFuelTankDetonated() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep02_stage") != 2 || !IsDefined(player) || qs.GetFact(n"chispa_ep02_tank_blown") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep02_tank_blown", 1);
        qs.SetFact(n"chispa_ep02_used_tech", 1);
        this.ApplyChooh2BlastDamage(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingTankBoom = true;
        } else {
            this.m_pendingTankBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_tank_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.07));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func TriggerRegulatorPurge() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep02_reg_purged") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep02_reg_purged", 1);
        qs.SetFact(n"chispa_ep02_turret_hacked", 1);
        qs.SetFact(n"chispa_ep02_tank_blown", 1);
        qs.SetFact(n"chispa_ep02_used_tech", 1);

        this.m_sys.ShowRelicBanner(n"ch_banner_ep02_purge", "[CHISPA] ¡Regulador CHOOH2 purgado! Depósito presurizado detonado");

        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp02Regulator");
        }
        this.m_regulatorId = new EntityID();

        this.DisableEp02TurretNow();
        if EntityID.IsDefined(this.m_fuelTankId) {
            let ftObj: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_fuelTankId) as ExplosiveDevice;
            if IsDefined(ftObj) && IsDefined(ftObj.GetDevicePS()) && !ftObj.GetDevicePS().IsExploded() {
                ftObj.QueueEvent(new ForceDetonate());
            }
        }
        this.ApplyChooh2BlastDamage(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingTankBoom = true;
        } else {
            this.m_pendingTankBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_tank_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.07));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func OnMaelstromProvoked(player: ref<PlayerPuppet>, silent: Bool) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || qs.GetFact(n"chispa_ep02_stage") != 2 {
            return;
        }
        let alreadyCombat: Bool = qs.GetFact(n"chispa_ep02_combat_started") > 0;
        if !alreadyCombat {
            qs.SetFact(n"chispa_ep02_combat_started", 1);
            this.m_combatStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        }

        if qs.GetFact(n"chispa_ep02_turret_hacked") == 0 && !this.m_turretCombatArmed && EntityID.IsDefined(this.m_turretId) {
            let turret: ref<SecurityTurret> = GameInstance.FindEntityByID(game, this.m_turretId) as SecurityTurret;
            if IsDefined(turret) && IsDefined(turret.GetDevicePS()) {
                let ps: ref<SecurityTurretControllerPS> = turret.GetDevicePS() as SecurityTurretControllerPS;
                if IsDefined(ps) && ps.IsON() {
                    ps.ChispaConfigureSecurityTurret(true);
                    this.m_turretCombatArmed = true;
                }
            }
        }

        let krag: ref<NPCPuppet> = des.GetEntity(this.m_kragId) as NPCPuppet;
        let vex: ref<NPCPuppet> = des.GetEntity(this.m_vexId) as NPCPuppet;
        let tuerca: ref<NPCPuppet> = des.GetEntity(this.m_tuercaId) as NPCPuppet;
        if IsDefined(krag) && !krag.IsDead() {
            this.m_sys.MakeNpcHostile(krag, player);
            if !silent && !alreadyCombat && !this.m_sys.m_isPlayingDialogueSequence {
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_krag_bark", n"ChispaEp02Krag", n"Krag", scnDialogLineType.Regular, 3.77));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        if IsDefined(vex) && !vex.IsDead() {
            this.m_sys.MakeNpcHostile(vex, player);
        }
        if IsDefined(tuerca) && !tuerca.IsDead() {
            this.m_sys.MakeNpcHostile(tuerca, player);
        }
    }

    private final func IsSquadDefeated() -> Bool {
        if !EntityID.IsDefined(this.m_kragId) || !EntityID.IsDefined(this.m_vexId) || !EntityID.IsDefined(this.m_tuercaId) {
            return false;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep02_tank_blown") == 0 && qs.GetFact(n"chispa_ep02_turret_hacked") == 0 && (!this.m_kragReady || !this.m_vexReady || !this.m_tuercaReady) {
            return false;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let anchor: Vector4 = this.GetRigPos();
        if !IsDefined(player) || this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), anchor) > 3600.00 {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        let elapsed: Float = this.m_combatStartedAt > 0.01 ? (now - this.m_combatStartedAt) : 0.00;
        let kragDown: Bool = this.m_sys.IsNpcNeutralized(this.m_kragId, anchor, elapsed, false);
        let vexDown: Bool = this.m_sys.IsNpcNeutralized(this.m_vexId, anchor, elapsed, kragDown && elapsed >= 10.00 && !player.IsInCombat());
        let tuercaDown: Bool = this.m_sys.IsNpcNeutralized(this.m_tuercaId, anchor, elapsed, kragDown && elapsed >= 10.00 && !player.IsInCombat());
        return kragDown && vexDown && tuercaDown;
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

        if kind == 30 {
            this.TriggerRegulatorPurge();
            return true;
        }

        if kind == 31 {
            this.m_pendingTurretBark = false;
            this.m_pendingTankBoom = false;
            this.m_pendingTechVictory = false;
            this.m_pendingGunsBlazing = false;

            let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
            if IsDefined(ses) {
                ses.DespawnTagged(n"ChispaEp02Sector");
            }
            this.m_sectorId = new EntityID();

            let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector02"), 1);
            ts.GiveMoney(player, 2800, n"money");
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.BlindLvl2Program"), 1);
            this.m_sys.GiveItemDelayed(t"Items.Preset_Achilles_Chispa", 1, 1.15);
            GameObject.PlaySoundEvent(player, n"ui_loot_cash");
            this.m_sys.PlaySfx(n"ch_sfx_dongle_sync");
            this.m_sys.ShowRelicBanner(n"ch_banner_ep02_claimed", "[CHISPA] Sector #02 conectado (+2.800 €$, hackeo y «Cláusula Perforante»)");

            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
            this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
            this.m_sys.ClearMappin();
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk/desc_ep02_04", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk");
            qs.SetFact(n"chispa_ep02_stage", 4);

            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_sector_pickup", n"phone", n"CHISPA", scnDialogLineType.Holocall, 18.06));
            this.m_sys.StartSpeechSequence(steps, 309);
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

        if qs.GetFact(n"chispa_ep02_asked_maelstrom") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep02_maelstrom", "¿De dónde salieron exactamente Maelstrom y este cementerio industrial de Northside?"), false, false));
            ArrayPush(ids, 30);
        }
        if qs.GetFact(n"chispa_ep02_asked_psycho") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep02_psycho", "¿La ciberpsicosis ocurre de verdad solo por pasarse metiendo demasiado cromo?"), false, false));
            ArrayPush(ids, 31);
        }
        if qs.GetFact(n"chispa_ep02_asked_maxtac") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep02_maxtac", "¿Quiénes son en realidad los de MaxTac? ¿Policías de élite o perros con correa?"), false, false));
            ArrayPush(ids, 32);
        }
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep02_accept", "Anotado, Chispa. Avísame en cuanto tengas fijado el Sector #03."), true, false));
        ArrayPush(ids, 33);

        this.m_sys.PushDialogHub(n"chispa_ep02", this.m_sys.GetLoc(n"ch_hub_ep02_talk_title", "C.H.I.S.P.A. // SECTOR #02 (Enlace Kiroshi)"), choices, ids);
    }

    public final func HandleDialogOption(optionId: Int32) -> Bool {
        if !IsDefined(this.m_sys) {
            return false;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        let steps: array<ref<ChispaSpeechStep>>;

        if optionId == 30 {
            qs.SetFact(n"chispa_ep02_asked_maelstrom", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_v_ask_maelstrom", n"player", n"V", scnDialogLineType.Regular, 5.51));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_ans_maelstrom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 24.30));
            this.m_sys.StartSpeechSequence(steps, 310);
            return true;
        }
        if optionId == 31 {
            qs.SetFact(n"chispa_ep02_asked_psycho", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_v_ask_psycho", n"player", n"V", scnDialogLineType.Regular, 5.69));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_ans_psycho", n"phone", n"CHISPA", scnDialogLineType.Holocall, 24.83));
            this.m_sys.StartSpeechSequence(steps, 311);
            return true;
        }
        if optionId == 32 {
            qs.SetFact(n"chispa_ep02_asked_maxtac", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_v_ask_maxtac", n"player", n"V", scnDialogLineType.Regular, 5.45));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_ans_maxtac", n"phone", n"CHISPA", scnDialogLineType.Holocall, 25.35));
            this.m_sys.StartSpeechSequence(steps, 312);
            return true;
        }
        if optionId == 33 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_v_outro_accept", n"player", n"V", scnDialogLineType.Regular, 5.44));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_outro", n"phone", n"CHISPA", scnDialogLineType.Holocall, 17.66));
            this.m_sys.StartSpeechSequence(steps, 320);
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

        jm.ChangeEntryState("contacts/chispa_ai/conv_ep02/msg_ep02_summary", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep02", "gameJournalOnscreen", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/desc_ep02_done", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);

        this.m_sys.ShowRelicBanner(n"ch_banner_ep02_done", "[CHISPA] Episodio 2 completado — Próximo barrido en camino");
        qs.SetFact(n"chispa_ep02_done", 1);
        qs.SetFact(n"chispa_season_stage", 300);
        qs.SetFact(n"chispa_ep02_stage", 5);
    }

    public final func Tick(player: ref<PlayerPuppet>, phoneOpen: Bool, fullGameplay: Bool) -> Float {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep02_stage");

        if stage <= 0 {
            this.m_sys.HideDialogChoices();
            this.m_sys.HideWorldInteraction();
            this.m_sys.ClearMappin();
            if this.m_sys.m_sessionReadyTicks >= 6 && fullGameplay && !this.m_sys.IsExternalPhoneCallBusy() && !this.m_sys.m_isPlayingDialogueSequence {
                if this.m_introWaitTicks < 5 {
                    this.m_introWaitTicks += 1;
                    return 0.60;
                }
                qs.SetFact(n"chispa_ep02_stage", 1);
                qs.SetFact(n"chispa_ep02_call_done", 0);
                this.ActivateJournalQuest();
                this.m_sys.ShowRelicBanner(n"ch_banner_ep02_start", "[CHISPA] Señal cromada en Northside — Revisa tu holoteléfono");
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 21);
                return 0.45;
            }
            return 0.60;
        }

        if stage == 1 {
            this.ActivateJournalQuest();
            this.CheckSmsReply();
            if qs.GetFact(n"chispa_ep02_call_done") == 0
                && !this.m_sys.m_activeCallPendingPickup
                && !this.m_sys.m_isPlayingDialogueSequence
                && this.m_sys.m_sessionReadyTicks >= 6
                && fullGameplay
                && !this.m_sys.IsExternalPhoneCallBusy() {
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 21);
            }
            return 0.25;
        }

        if stage == 2 {
            this.m_sys.HideDialogChoices();
            this.m_sys.SyncObjectivePinLoop(
                22,
                "quests/side_quest/chispa_ep02_quest",
                "quests/side_quest/chispa_ep02_quest/phase_ep02",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/mp_ep02_northside",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let regPos: Vector4 = this.m_spawned ? this.m_regulatorPos : this.GetRegulatorPos();
            this.m_sys.UpdateFallbackMappin(
                22,
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear",
                new Vector4(regPos.X, regPos.Y, regPos.Z + 1.55, 1.00),
                n"ch_mappin_ep02_northside",
                "CHISPA Ep. 2: Muelles de Northside"
            );

            let distRegSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), regPos);
            if distRegSq <= 900.00 && qs.GetFact(n"chispa_ep02_approach_played") == 0 && !this.m_sys.m_isPlayingDialogueSequence {
                qs.SetFact(n"chispa_ep02_approach_played", 1);
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_approach", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.28));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            if this.m_pendingTurretBark && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingTurretBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_turret_hijack", n"phone", n"CHISPA", scnDialogLineType.Holocall, 10.86));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingTankBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingTankBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_tank_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.07));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            let centerCombatPos: Vector4 = new Vector4(-1557.20, 2657.20, regPos.Z, 1.00);
            if this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), centerCombatPos) <= 56.25 && qs.GetFact(n"chispa_ep02_combat_started") == 0 {
                this.OnMaelstromProvoked(player, false);
            }

            let scannedFlag: Bool = qs.GetFact(n"chispa_ep02_scanned") > 0;
            let canReachReg: Bool = qs.GetFact(n"chispa_ep02_reg_purged") == 0
                && ((scannedFlag && distRegSq <= 324.00) || distRegSq <= 16.00);
            if canReachReg && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(30, n"ch_hub_ep02_reg_title", "REGULADOR DE PRESIÓN CHOOH2", n"ch_act_purge_reg", "Purgar regulador CHOOH2 y tumbar torreta [Kiroshi]", false);
            } else {
                this.m_sys.HideWorldInteraction();
            }

            if EntityID.IsDefined(this.m_kragId) && this.IsSquadDefeated() {
                this.m_sys.HideWorldInteraction();
                this.DisableEp02TurretNow();
                jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
                this.m_sys.ActivateObjectiveWithPin(
                    23,
                    "quests/side_quest/chispa_ep02_quest",
                    "quests/side_quest/chispa_ep02_quest/phase_ep02",
                    "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract",
                    "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract/mp_ep02_rig",
                    "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract/desc_ep02_03",
                    this.AllPinPaths(),
                    true
                );
                qs.SetFact(n"chispa_ep02_stage", 3);
                if qs.GetFact(n"chispa_ep02_used_tech") > 0 {
                    if this.m_sys.m_isPlayingDialogueSequence {
                        this.m_pendingTechVictory = true;
                    } else {
                        this.m_pendingTechVictory = false;
                        let steps: array<ref<ChispaSpeechStep>>;
                        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_tech_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.66));
                        this.m_sys.StartSpeechSequence(steps, 0);
                    }
                } else {
                    if this.m_sys.m_isPlayingDialogueSequence {
                        this.m_pendingGunsBlazing = true;
                    } else {
                        this.m_pendingGunsBlazing = false;
                        let steps: array<ref<ChispaSpeechStep>>;
                        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.31));
                        this.m_sys.StartSpeechSequence(steps, 0);
                    }
                }
            }
            return distRegSq <= 400.00 ? 0.12 : 0.45;
        }

        if stage == 3 {
            this.m_sys.HideDialogChoices();
            if this.m_pendingTankBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingTankBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_tank_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.07));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingTechVictory && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingTechVictory = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_tech_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.66));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingGunsBlazing && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingGunsBlazing = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep02_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.31));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            this.m_sys.SyncObjectivePinLoop(
                23,
                "quests/side_quest/chispa_ep02_quest",
                "quests/side_quest/chispa_ep02_quest/phase_ep02",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract/mp_ep02_rig",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let rigPos: Vector4 = this.m_spawned ? this.m_rigPos : this.GetRigPos();
            this.m_sys.UpdateFallbackMappin(
                23,
                "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract",
                new Vector4(rigPos.X, rigPos.Y, rigPos.Z + 1.55, 1.00),
                n"ch_mappin_ep02_rig",
                "CHISPA Ep. 2: Terminal Quirúrgico"
            );
            let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigPos);
            if distSq <= 14.00 && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(31, n"ch_hub_ep02_rig_title", "ESTACIÓN QUIRÚRGICA MAELSTROM", n"ch_act_claim_sec02", "Extraer Sector de Memoria #02 [C.H.I.S.P.A.]", false, distSq <= 7.84);
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
        if qs.GetFact(n"chispa_ep02_stage") < 1 {
            qs.SetFact(n"chispa_ep02_stage", 1);
            this.ActivateJournalQuest();
        }
        qs.SetFact(n"chispa_ep02_call_done", 0);
        this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 21);
    }

    public final func TeleportToNorthside() -> Void {
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
        if qs.GetFact(n"chispa_ep02_stage") < 2 {
            this.ActivateJournalQuest();
            this.ActivateIntroSms();
            this.GrantStarterTacticalKit(player);
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            this.m_sys.ActivateObjectiveWithPin(
                22,
                "quests/side_quest/chispa_ep02_quest",
                "quests/side_quest/chispa_ep02_quest/phase_ep02",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/mp_ep02_northside",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/desc_ep02_02",
                this.AllPinPaths(),
                true
            );
            qs.SetFact(n"chispa_ep02_call_done", 1);
            qs.SetFact(n"chispa_ep02_sms_replied", 22);
            qs.SetFact(n"chispa_ep02_stage", 2);
        }
        let dest: Vector4 = this.GetArrivalPos();
        let ang: EulerAngles;
        ang.Yaw = 45.00;
        GameInstance.GetTeleportationFacility(game).Teleport(player, dest, ang);
        this.EnsureSpawned(player);
    }
}
