// Protocolo CHISPA / SPARKY Protocol — Episodio 3: «Balas que Doblan Esquinas»
module ChispaNC

public class ChispaEp03Handler {
    private let m_sys: wref<ChispaSystem>;
    private let m_spawned: Bool;

    // Entidades estáticas: baliza IFF inhibidora, antena explosiva Arasaka, contenedor y sector
    private let m_pylonId: EntityID;
    private let m_jammerBombId: EntityID;
    private let m_rigId: EntityID;
    private let m_sectorId: EntityID;
    private let m_bombConfigured: Bool;

    // Célula Garra de Tigre
    private let m_aikoId: EntityID;
    private let m_kenjiId: EntityID;
    private let m_renId: EntityID;
    private let m_aikoReady: Bool;
    private let m_kenjiReady: Bool;
    private let m_renReady: Bool;
    private let m_aikoJamApplied: Bool;
    private let m_kenjiJamApplied: Bool;
    private let m_renJamApplied: Bool;

    // Cola de locuciones no solapadas y posiciones sobre suelo
    private let m_pendingSmartJamBark: Bool;
    private let m_pendingJammerBoom: Bool;
    private let m_pendingSmartVictory: Bool;
    private let m_pendingGunsBlazing: Bool;
    private let m_pylonPos: Vector4;
    private let m_jammerBombPos: Vector4;
    private let m_rigPos: Vector4;
    private let m_combatStartedAt: Float;
    private let m_introWaitTicks: Int32;

    public final func Init(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
    }

    // Muelle Sur de Watson / Arasaka Waterfront (exterior_-32_24_0_0 — libre y plano a Z=9.05m)
    public final func GetArrivalPos() -> Vector4 = new Vector4(-2020.50, 1546.50, 9.10, 1.00);
    public final func GetPylonPos() -> Vector4 = new Vector4(-2021.20, 1556.80, 9.05, 1.00);
    public final func GetJammerBombPos() -> Vector4 = new Vector4(-2024.40, 1563.40, 9.05, 1.00);
    public final func GetRigPos() -> Vector4 = new Vector4(-2022.40, 1571.60, 9.05, 1.00);

    public final func ResetRuntimeFlags() -> Void {
        this.m_spawned = false;
        this.m_pylonId = new EntityID();
        this.m_jammerBombId = new EntityID();
        this.m_rigId = new EntityID();
        this.m_sectorId = new EntityID();
        this.m_bombConfigured = false;
        this.m_aikoId = new EntityID();
        this.m_kenjiId = new EntityID();
        this.m_renId = new EntityID();
        this.m_aikoReady = false;
        this.m_kenjiReady = false;
        this.m_renReady = false;
        this.m_aikoJamApplied = false;
        this.m_kenjiJamApplied = false;
        this.m_renJamApplied = false;
        this.m_pendingSmartJamBark = false;
        this.m_pendingJammerBoom = false;
        this.m_pendingSmartVictory = false;
        this.m_pendingGunsBlazing = false;
        this.m_pylonPos = this.GetPylonPos();
        this.m_jammerBombPos = this.GetJammerBombPos();
        this.m_rigPos = this.GetRigPos();
        this.m_combatStartedAt = 0.00;
        this.m_introWaitTicks = 0;
    }

    private final func AllPinPaths() -> array<String> {
        return [
            "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/mp_ep03_waterfront",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract/mp_ep03_rig"
        ];
    }

    public final func CleanupEntities() -> Void {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) {
            des.DeleteTagged(n"ChispaEp03Aiko");
            des.DeleteTagged(n"ChispaEp03Kenji");
            des.DeleteTagged(n"ChispaEp03Ren");
        }
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp03Pylon");
            ses.DespawnTagged(n"ChispaEp03JammerBomb");
            ses.DespawnTagged(n"ChispaEp03Rig");
            ses.DespawnTagged(n"ChispaEp03Sector");
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
            "quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms/desc_ep03_01",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/desc_ep03_02",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract/desc_ep03_03",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/04_ep03_talk/desc_ep03_04",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/desc_ep03_done"
        ];
        for dp in descPaths {
            jm.ChangeEntryState(dp, "gameJournalQuestDescription", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        let objPaths: array<String> = [
            "quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/04_ep03_talk"
        ];
        for op in objPaths {
            jm.ChangeEntryState(op, "gameJournalQuestObjective", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03", "gameJournalQuestPhase", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest", "gameJournalQuest", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        let smsPaths: array<String> = [
            "contacts/chispa_ai/conv_ep03/msg_ep03_hook",
            "contacts/chispa_ai/conv_ep03/msg_ep03_claws",
            "contacts/chispa_ai/conv_ep03/msg_ep03_quay",
            "contacts/chispa_ai/conv_ep03/msg_ep03_summary"
        ];
        for sp in smsPaths {
            jm.ChangeEntryState(sp, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/choices_ep03/reply_ep03_claws", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/choices_ep03/reply_ep03_quay", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/choices_ep03", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03", "gameJournalPhoneConversation", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep03", "gameJournalOnscreen", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        qs.SetFact(n"chispa_ep03_call_done", 0);
        qs.SetFact(n"chispa_ep03_sms_replied", 0);
        qs.SetFact(n"chispa_ep03_approach_played", 0);
        qs.SetFact(n"chispa_ep03_scanned", 0);
        qs.SetFact(n"chispa_ep03_smart_jammed", 0);
        qs.SetFact(n"chispa_ep03_jammer_down", 0);
        qs.SetFact(n"chispa_ep03_used_smart", 0);
        qs.SetFact(n"chispa_ep03_combat_started", 0);
        qs.SetFact(n"chispa_ep03_asked_nuke", 0);
        qs.SetFact(n"chispa_ep03_asked_unification", 0);
        qs.SetFact(n"chispa_ep03_asked_tygers", 0);
        qs.SetFact(n"chispa_ep03_done", 0);
        qs.SetFact(n"chispa_ep03_stage", 0);
    }

    // --- Holollamada e Hilo de SMS Inicial ---

    public final func GetCallSteps(stageTag: Int32, out completeAction: Int32) -> array<ref<ChispaSpeechStep>> {
        let steps: array<ref<ChispaSpeechStep>>;
        if !IsDefined(this.m_sys) || stageTag != 31 {
            return steps;
        }
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_call_01", n"phone", n"CHISPA", scnDialogLineType.Holocall, 18.43));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_v_call_01", n"player", n"V", scnDialogLineType.Regular, 6.68));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_call_02", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.86));
        completeAction = 401;
        return steps;
    }

    public final func OnCallRejected(stageTag: Int32) -> Void {
        if IsDefined(this.m_sys) && stageTag == 31 {
            GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance()).SetFact(n"chispa_ep03_call_done", 1);
            this.ActivateIntroSms();
        }
    }

    public final func OnPostSpeech(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if actionId == 401 {
            qs.SetFact(n"chispa_ep03_call_done", 1);
            this.m_sys.EndCustomCall(n"chispa_ai", this.m_sys.m_activeCallIsVideo);
            this.ActivateIntroSms();
            return;
        }
        if actionId == 409 || actionId == 410 || actionId == 411 || actionId == 412 {
            if qs.GetFact(n"chispa_ep03_stage") == 4 && !this.m_sys.IsUiBlockingWorldInput() {
                this.ShowDialogHub();
            }
            return;
        }
        if actionId == 420 {
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
        let qEntry: wref<JournalEntry> = jm.GetEntryByString("quests/side_quest/chispa_ep03_quest", "gameJournalQuest");
        if !IsDefined(qEntry) {
            return;
        }
        let qState: gameJournalEntryState = jm.GetEntryState(qEntry);
        if Equals(qState, gameJournalEntryState.Active) || Equals(qState, gameJournalEntryState.Succeeded) {
            return;
        }
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest", "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03", "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms/desc_ep03_01", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        if !IsDefined(jm.GetTrackedEntry()) {
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms");
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
        let msgEntry: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep03/msg_ep03_hook", "gameJournalPhoneMessage");
        if IsDefined(msgEntry) && Equals(jm.GetEntryState(msgEntry), gameJournalEntryState.Active) {
            return;
        }
        jm.ChangeEntryState("contacts/chispa_ai", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03", "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/msg_ep03_hook", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/choices_ep03", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/choices_ep03/reply_ep03_claws", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/choices_ep03/reply_ep03_quay", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    }

    public final func CheckSmsReply() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(jm) || qs.GetFact(n"chispa_ep03_stage") != 1 || qs.GetFact(n"chispa_ep03_sms_replied") > 0 {
            return;
        }
        let rClaws: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep03/choices_ep03/reply_ep03_claws", "gameJournalPhoneChoiceEntry");
        let rQuay: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep03/choices_ep03/reply_ep03_quay", "gameJournalPhoneChoiceEntry");

        let replyKind: Int32 = 0;
        if IsDefined(rClaws) && Equals(jm.GetEntryState(rClaws), gameJournalEntryState.Succeeded) {
            replyKind = 31;
        } else if IsDefined(rQuay) && Equals(jm.GetEntryState(rQuay), gameJournalEntryState.Succeeded) {
            replyKind = 32;
        }
        if replyKind == 0 {
            return;
        }

        qs.SetFact(n"chispa_ep03_sms_replied", replyKind);
        let cb: ref<ChispaSmsDelayCallback> = new ChispaSmsDelayCallback();
        cb.system = this.m_sys;
        cb.actionId = replyKind;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.90, false);
    }

    private final func GrantStarterSmartKit(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        if !IsDefined(ts) || !IsDefined(player) {
            return;
        }
        let granted: Bool = false;
        if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Chao_Default")) == 0 {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Chao_Default"), 1);
            granted = true;
        }
        if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.AdvancedSmartLinkCommon")) == 0 {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.AdvancedSmartLinkCommon"), 1);
        }
        let hasWipe: Bool = ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.MemoryWipeLvl2Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.MemoryWipeLvl3Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.MemoryWipeLvl4Program")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.MemoryWipeLvl4PlusPlusProgram")) > 0;
        if !hasWipe {
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.MemoryWipeLvl2Program"), 1);
            granted = true;
        }
        this.m_sys.EnsureSmartBridgeActive(player);
        if granted {
            this.m_sys.ShowRelicBanner(n"ch_banner_ep03_gear", "[CHISPA] ¡Pistola inteligente Chao y Puente Smart activos! Ruta trazada");
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
        if actionId == 31 {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/msg_ep03_claws", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        } else {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/msg_ep03_quay", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        }
        this.GrantStarterSmartKit(player);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        this.m_sys.ActivateObjectiveWithPin(
            32,
            "quests/side_quest/chispa_ep03_quest",
            "quests/side_quest/chispa_ep03_quest/phase_ep03",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/mp_ep03_waterfront",
            "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/desc_ep03_02",
            this.AllPinPaths(),
            true
        );
        qs.SetFact(n"chispa_ep03_stage", 2);
    }

    // --- Escena Táctica del Muelle Sur (Arasaka Waterfront / Garra de Tigre) ---

    private final func ApplyDermalSmartJammer(npc: ref<NPCPuppet>, targetProb: Float) -> Void {
        if !IsDefined(npc) || npc.IsDead() {
            return;
        }
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(this.m_sys.GetGameInstance());
        if !IsDefined(ss) {
            return;
        }
        let oid: StatsObjectID = Cast<StatsObjectID>(npc.GetEntityID());
        ss.RemoveAllModifiers(oid, gamedataStatType.SmartTargetingDisruptionProbability, true);
        let mod: ref<gameStatModifierData> = RPGManager.CreateStatModifier(gamedataStatType.SmartTargetingDisruptionProbability, gameStatModifierType.Additive, targetProb);
        ss.AddModifier(oid, mod);
    }

    private final func StripDermalSmartJammer(npc: ref<NPCPuppet>) -> Void {
        if !IsDefined(npc) {
            return;
        }
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(this.m_sys.GetGameInstance());
        if !IsDefined(ss) {
            return;
        }
        let oid: StatsObjectID = Cast<StatsObjectID>(npc.GetEntityID());
        ss.RemoveAllModifiers(oid, gamedataStatType.SmartTargetingDisruptionProbability, true);
        let suppress: ref<gameStatModifierData> = RPGManager.CreateStatModifier(gamedataStatType.SmartTargetingDisruptionProbability, gameStatModifierType.Additive, -1.50);
        ss.AddModifier(oid, suppress);
    }

    private final func EnsureSpawned(player: ref<PlayerPuppet>) -> Void {
        let pylonBase: Vector4 = this.GetPylonPos();
        let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), pylonBase);
        if distSq > 4225.00 {
            return;
        }

        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep03_stage");
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();

        if IsDefined(ses) && ses.IsReady() {
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_rigId) {
                ses.DespawnTagged(n"ChispaEp03Rig");
                let rBase: Vector4 = this.GetRigPos();
                let zR: Float = this.m_sys.FindGroundZ(rBase);
                this.m_rigPos = new Vector4(rBase.X, rBase.Y, zR, 1.00);
                this.m_rigId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep03_arasaka_rig.ent", n"", this.m_rigPos, 0.00, -165.00, n"ChispaEp03Rig");
            }
            if (stage == 2 || stage == 3) && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_sectorId) {
                ses.DespawnTagged(n"ChispaEp03Sector");
                let rBase: Vector4 = this.GetRigPos();
                let zR: Float = this.m_sys.FindGroundZ(rBase);
                this.m_rigPos = new Vector4(rBase.X, rBase.Y, zR, 1.00);
                this.m_sectorId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep03_sector_module.ent", n"", this.m_rigPos, 0.00, -165.00, n"ChispaEp03Sector");
            }
            if qs.GetFact(n"chispa_ep03_jammer_down") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_pylonId) {
                ses.DespawnTagged(n"ChispaEp03Pylon");
                let zP: Float = this.m_sys.FindGroundZ(pylonBase);
                this.m_pylonPos = new Vector4(pylonBase.X, pylonBase.Y, zP, 1.00);
                this.m_pylonId = this.m_sys.SpawnStaticPropEx(r"chispa_nc\\entities\\chispa_ep03_jammer_pylon.ent", n"", this.m_pylonPos, 0.00, 15.00, n"ChispaEp03Pylon");
            }
            if qs.GetFact(n"chispa_ep03_jammer_down") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_jammerBombId) {
                ses.DespawnTagged(n"ChispaEp03JammerBomb");
                this.m_bombConfigured = false;
                let jbBase: Vector4 = this.GetJammerBombPos();
                let zJb: Float = this.m_sys.FindGroundZ(jbBase);
                this.m_jammerBombPos = new Vector4(jbBase.X, jbBase.Y, zJb, 1.00);
                this.m_jammerBombId = this.m_sys.SpawnStaticPropEx(r"base\\gameplay\\devices\\explosives\\antenna_base_explosive_arasaka.ent", n"default", this.m_jammerBombPos, 0.00, -145.00, n"ChispaEp03JammerBomb");
            }
            if !this.m_bombConfigured && EntityID.IsDefined(this.m_jammerBombId) && ses.IsSpawned(this.m_jammerBombId) {
                let jbObj: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_jammerBombId) as ExplosiveDevice;
                if IsDefined(jbObj) && IsDefined(jbObj.GetDevicePS()) {
                    jbObj.GetDevicePS().ChispaConfigureExplosiveServer();
                    this.m_bombConfigured = true;
                }
            }
        }

        if stage == 2 {
            let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
            if IsDefined(des) && des.IsReady() {
                if !EntityID.IsDefined(this.m_aikoId) && !this.m_sys.IsDynamicEntityAliveOrSpawning(this.m_aikoId) {
                    des.DeleteTagged(n"ChispaEp03Aiko");
                    des.DeleteTagged(n"ChispaEp03Kenji");
                    des.DeleteTagged(n"ChispaEp03Ren");

                    let aXY: Vector4 = new Vector4(-2022.00, 1568.20, pylonBase.Z, 1.00);
                    let kXY: Vector4 = new Vector4(-2024.10, 1562.20, pylonBase.Z, 1.00);
                    let rXY: Vector4 = new Vector4(-2019.60, 1565.00, pylonBase.Z, 1.00);
                    let zA: Float = this.m_sys.FindGroundZ(aXY);
                    let zK: Float = this.m_sys.FindGroundZ(kXY);
                    let zR: Float = this.m_sys.FindGroundZ(rXY);

                    this.m_aikoReady = false;
                    this.m_kenjiReady = false;
                    this.m_renReady = false;
                    this.m_aikoJamApplied = false;
                    this.m_kenjiJamApplied = false;
                    this.m_renJamApplied = false;
                    this.m_aikoId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep03_Aiko", new Vector4(aXY.X, aXY.Y, zA, 1.00), -165.00, n"ChispaEp03Aiko");
                    this.m_kenjiId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep03_Kenji", new Vector4(kXY.X, kXY.Y, zK, 1.00), -170.00, n"ChispaEp03Kenji");
                    this.m_renId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep03_Ren", new Vector4(rXY.X, rXY.Y, zR, 1.00), -155.00, n"ChispaEp03Ren");
                }
                if !this.m_aikoReady && EntityID.IsDefined(this.m_aikoId) && des.IsSpawned(this.m_aikoId) {
                    let aNpc: ref<NPCPuppet> = des.GetEntity(this.m_aikoId) as NPCPuppet;
                    if IsDefined(aNpc) && ScriptedPuppet.IsActive(aNpc) {
                        this.m_aikoReady = true;
                        if !this.m_aikoJamApplied && qs.GetFact(n"chispa_ep03_jammer_down") == 0 {
                            this.ApplyDermalSmartJammer(aNpc, 0.85);
                            this.m_aikoJamApplied = true;
                        }
                    }
                }
                if !this.m_kenjiReady && EntityID.IsDefined(this.m_kenjiId) && des.IsSpawned(this.m_kenjiId) {
                    let kNpc: ref<NPCPuppet> = des.GetEntity(this.m_kenjiId) as NPCPuppet;
                    if IsDefined(kNpc) && ScriptedPuppet.IsActive(kNpc) {
                        this.m_kenjiReady = true;
                        if !this.m_kenjiJamApplied && qs.GetFact(n"chispa_ep03_jammer_down") == 0 {
                            this.ApplyDermalSmartJammer(kNpc, 0.80);
                            this.m_kenjiJamApplied = true;
                        }
                    }
                }
                if !this.m_renReady && EntityID.IsDefined(this.m_renId) && des.IsSpawned(this.m_renId) {
                    let rNpc: ref<NPCPuppet> = des.GetEntity(this.m_renId) as NPCPuppet;
                    if IsDefined(rNpc) && ScriptedPuppet.IsActive(rNpc) {
                        this.m_renReady = true;
                        if !this.m_renJamApplied && qs.GetFact(n"chispa_ep03_jammer_down") == 0 {
                            this.ApplyDermalSmartJammer(rNpc, 0.80);
                            this.m_renJamApplied = true;
                        }
                    }
                }
            }
        }
        this.m_spawned = true;
    }

    // --- Telemetría Smart-Jammer, Antena Explosiva IFF y Quickhacks ---

    public final func IsEp03JammerBomb(id: EntityID) -> Bool {
        return EntityID.IsDefined(id) && Equals(id, this.m_jammerBombId);
    }

    public final func IsEp03Npc(id: EntityID) -> Bool {
        return EntityID.IsDefined(id)
            && (Equals(id, this.m_aikoId)
                || Equals(id, this.m_kenjiId)
                || Equals(id, this.m_renId));
    }

    private final func IsEp03Target(id: EntityID) -> Bool {
        return this.IsEp03JammerBomb(id) || this.IsEp03Npc(id);
    }

    public final func OnTargetScanned(recID: TweakDBID) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep03_stage") != 2 {
            return;
        }
        if qs.GetFact(n"chispa_ep03_scanned") == 0 {
            qs.SetFact(n"chispa_ep03_scanned", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
        }
    }

    public final func OnSmartBulletJammed() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep03_stage") != 2 || !IsDefined(player) {
            return;
        }
        qs.SetFact(n"chispa_ep03_used_smart", 1);
        if qs.GetFact(n"chispa_ep03_smart_jammed") == 0 {
            qs.SetFact(n"chispa_ep03_smart_jammed", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
            if this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingSmartJamBark = true;
            } else {
                this.m_pendingSmartJamBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_smart_jam", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.73));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        this.OnTygerProvoked(player, true);
    }

    public final func OnQuickHackApplied(actionOwner: EntityID, actionClassName: CName, objectActionID: TweakDBID) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep03_stage") != 2 || !IsDefined(player) {
            return;
        }
        let nearWaterfront: Bool = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), this.GetPylonPos()) <= 5625.00;
        if !this.IsEp03Target(actionOwner) && !nearWaterfront {
            return;
        }
        qs.SetFact(n"chispa_ep03_used_smart", 1);
        if this.IsEp03Npc(actionOwner) {
            let isOpticWipe: Bool = Equals(objectActionID, t"QuickHack.BlindHack")
                || Equals(objectActionID, t"QuickHack.BlindLvl2Hack")
                || Equals(objectActionID, t"QuickHack.BlindLvl3Hack")
                || Equals(objectActionID, t"QuickHack.BlindLvl4Hack")
                || Equals(objectActionID, t"QuickHack.MemoryWipeLvl2Hack")
                || Equals(objectActionID, t"QuickHack.MemoryWipeLvl3Hack")
                || Equals(objectActionID, t"QuickHack.MemoryWipeLvl4Hack");
            if isOpticWipe {
                let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
                if IsDefined(des) {
                    let npc: ref<NPCPuppet> = des.GetEntity(actionOwner) as NPCPuppet;
                    if IsDefined(npc) {
                        this.StripDermalSmartJammer(npc);
                    }
                }
            }
            this.OnTygerProvoked(player, true);
        }
    }

    private final func ApplyJammerSurgeAndStripSquad(player: ref<PlayerPuppet>) -> Void {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);

        this.m_sys.PlaySfx(n"ch_sfx_capacitor_arc");
        if IsDefined(des) {
            let kenji: ref<NPCPuppet> = des.GetEntity(this.m_kenjiId) as NPCPuppet;
            if IsDefined(kenji) {
                this.StripDermalSmartJammer(kenji);
                if !kenji.IsDead() {
                    StatusEffectHelper.ApplyStatusEffect(kenji, t"BaseStatusEffect.Overload");
                    StatusEffectHelper.ApplyStatusEffect(kenji, t"BaseStatusEffect.Electrocuted");
                    if IsDefined(poolSys) {
                        poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(kenji.GetEntityID()), gamedataStatPoolType.Health, -100.0, player, true, true);
                    }
                    kenji.Kill(player);
                }
            }
            let aiko: ref<NPCPuppet> = des.GetEntity(this.m_aikoId) as NPCPuppet;
            if IsDefined(aiko) {
                this.StripDermalSmartJammer(aiko);
                if !aiko.IsDead() {
                    StatusEffectHelper.ApplyStatusEffect(aiko, t"BaseStatusEffect.Overload");
                    StatusEffectHelper.ApplyStatusEffect(aiko, t"BaseStatusEffect.Blind");
                    if IsDefined(poolSys) {
                        poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(aiko.GetEntityID()), gamedataStatPoolType.Health, -45.0, player, true, true);
                    }
                }
            }
            let ren: ref<NPCPuppet> = des.GetEntity(this.m_renId) as NPCPuppet;
            if IsDefined(ren) {
                this.StripDermalSmartJammer(ren);
                if !ren.IsDead() {
                    StatusEffectHelper.ApplyStatusEffect(ren, t"BaseStatusEffect.Overload");
                    StatusEffectHelper.ApplyStatusEffect(ren, t"BaseStatusEffect.Blind");
                    if IsDefined(poolSys) {
                        poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(ren.GetEntityID()), gamedataStatPoolType.Health, -55.0, player, true, true);
                    }
                }
            }
        }
        this.OnTygerProvoked(player, true);
    }

    public final func OnJammerBombDetonated() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if qs.GetFact(n"chispa_ep03_stage") != 2 || !IsDefined(player) || qs.GetFact(n"chispa_ep03_jammer_down") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep03_jammer_down", 1);
        qs.SetFact(n"chispa_ep03_used_smart", 1);
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp03Pylon");
        }
        this.m_pylonId = new EntityID();

        this.m_sys.ShowRelicBanner(n"ch_banner_ep03_jammer", "[CHISPA] ¡Inhibidor Garra de Tigre frito! Balas inteligentes al 100 %");
        this.ApplyJammerSurgeAndStripSquad(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingJammerBoom = true;
        } else {
            this.m_pendingJammerBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_jammer_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.43));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func TriggerJammerInversion() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep03_jammer_down") > 0 {
            return;
        }
        qs.SetFact(n"chispa_ep03_jammer_down", 1);
        qs.SetFact(n"chispa_ep03_used_smart", 1);

        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp03Pylon");
        }
        this.m_pylonId = new EntityID();

        if EntityID.IsDefined(this.m_jammerBombId) {
            let jbObj: ref<ExplosiveDevice> = GameInstance.FindEntityByID(game, this.m_jammerBombId) as ExplosiveDevice;
            if IsDefined(jbObj) && IsDefined(jbObj.GetDevicePS()) && !jbObj.GetDevicePS().IsExploded() {
                jbObj.QueueEvent(new ForceDetonate());
            }
        }
        this.m_sys.ShowRelicBanner(n"ch_banner_ep03_jammer", "[CHISPA] ¡Inhibidor Garra de Tigre frito! Balas inteligentes al 100 %");
        this.ApplyJammerSurgeAndStripSquad(player);
        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingJammerBoom = true;
        } else {
            this.m_pendingJammerBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_jammer_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.43));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    public final func OnTygerProvoked(player: ref<PlayerPuppet>, silent: Bool) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || qs.GetFact(n"chispa_ep03_stage") != 2 {
            return;
        }
        let alreadyCombat: Bool = qs.GetFact(n"chispa_ep03_combat_started") > 0;
        if !alreadyCombat {
            qs.SetFact(n"chispa_ep03_combat_started", 1);
            this.m_combatStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        }

        let aiko: ref<NPCPuppet> = des.GetEntity(this.m_aikoId) as NPCPuppet;
        let kenji: ref<NPCPuppet> = des.GetEntity(this.m_kenjiId) as NPCPuppet;
        let ren: ref<NPCPuppet> = des.GetEntity(this.m_renId) as NPCPuppet;
        if IsDefined(aiko) && !aiko.IsDead() {
            this.m_sys.MakeNpcHostile(aiko, player);
            if !silent && !alreadyCombat && !this.m_sys.m_isPlayingDialogueSequence {
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_aiko_bark", n"ChispaEp03Aiko", n"Aiko", scnDialogLineType.Regular, 6.74));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        if IsDefined(kenji) && !kenji.IsDead() {
            this.m_sys.MakeNpcHostile(kenji, player);
        }
        if IsDefined(ren) && !ren.IsDead() {
            this.m_sys.MakeNpcHostile(ren, player);
        }
    }

    private final func IsSquadDefeated() -> Bool {
        if !EntityID.IsDefined(this.m_aikoId) || !EntityID.IsDefined(this.m_kenjiId) || !EntityID.IsDefined(this.m_renId) {
            return false;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep03_jammer_down") == 0 && (!this.m_aikoReady || !this.m_kenjiReady || !this.m_renReady) {
            return false;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let anchor: Vector4 = this.GetRigPos();
        if !IsDefined(player) || this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), anchor) > 3600.00 {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        let elapsed: Float = this.m_combatStartedAt > 0.01 ? (now - this.m_combatStartedAt) : 0.00;
        let aikoDown: Bool = this.m_sys.IsNpcNeutralized(this.m_aikoId, anchor, elapsed, false);
        let kenjiDown: Bool = this.m_sys.IsNpcNeutralized(this.m_kenjiId, anchor, elapsed, aikoDown && elapsed >= 10.00 && !player.IsInCombat());
        let renDown: Bool = this.m_sys.IsNpcNeutralized(this.m_renId, anchor, elapsed, aikoDown && elapsed >= 10.00 && !player.IsInCombat());
        return aikoDown && kenjiDown && renDown;
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

        if kind == 40 {
            this.TriggerJammerInversion();
            return true;
        }

        if kind == 41 {
            this.m_pendingSmartJamBark = false;
            this.m_pendingJammerBoom = false;
            this.m_pendingSmartVictory = false;
            this.m_pendingGunsBlazing = false;

            let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
            if IsDefined(ses) {
                ses.DespawnTagged(n"ChispaEp03Sector");
            }
            this.m_sectorId = new EntityID();

            let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector03"), 1);
            ts.GiveMoney(player, 3400, n"money");
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.ContagionLvl2Program"), 1);
            this.m_sys.GiveItemDelayed(t"Items.Preset_Shingen_Chispa", 1, 1.15);
            this.m_sys.EnsureSmartBridgeActive(player);
            GameObject.PlaySoundEvent(player, n"ui_loot_cash");
            this.m_sys.PlaySfx(n"ch_sfx_dongle_sync");
            this.m_sys.ShowRelicBanner(n"ch_banner_ep03_claimed", "[CHISPA] Sector #03 conectado (+3.400 €$, Contagio y «Curva Ejecutiva»)");

            jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
            this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
            this.m_sys.ClearMappin();
            jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/04_ep03_talk/desc_ep03_04", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/04_ep03_talk", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_ep03_quest/phase_ep03/04_ep03_talk");
            qs.SetFact(n"chispa_ep03_stage", 4);

            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_sector_pickup", n"phone", n"CHISPA", scnDialogLineType.Holocall, 16.78));
            this.m_sys.StartSpeechSequence(steps, 409);
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

        if qs.GetFact(n"chispa_ep03_asked_nuke") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep03_nuke", "¿De verdad volaron la Torre Arasaka con una bomba nuclear en medio de Night City en 2023?"), false, false));
            ArrayPush(ids, 40);
        }
        if qs.GetFact(n"chispa_ep03_asked_unification") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep03_unification", "¿Cómo acabó Night City fuera del NUSA tras la Guerra de Unificación?"), false, false));
            ArrayPush(ids, 41);
        }
        if qs.GetFact(n"chispa_ep03_asked_tygers") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep03_tygers", "¿De dónde salieron los Garras de Tigre y por qué reciben cromo táctico de Arasaka?"), false, false));
            ArrayPush(ids, 42);
        }
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep03_accept", "Entendido, Chispa. Avísame cuando abran los puentes hacia Heywood para el Sector #04."), true, false));
        ArrayPush(ids, 43);

        this.m_sys.PushDialogHub(n"chispa_ep03", this.m_sys.GetLoc(n"ch_hub_ep03_talk_title", "C.H.I.S.P.A. // SECTOR #03 (Enlace Kiroshi)"), choices, ids);
    }

    public final func HandleDialogOption(optionId: Int32) -> Bool {
        if !IsDefined(this.m_sys) {
            return false;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        let steps: array<ref<ChispaSpeechStep>>;

        if optionId == 40 {
            qs.SetFact(n"chispa_ep03_asked_nuke", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_v_ask_nuke", n"player", n"V", scnDialogLineType.Regular, 5.66));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_ans_nuke", n"phone", n"CHISPA", scnDialogLineType.Holocall, 22.90));
            this.m_sys.StartSpeechSequence(steps, 410);
            return true;
        }
        if optionId == 41 {
            qs.SetFact(n"chispa_ep03_asked_unification", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_v_ask_unification", n"player", n"V", scnDialogLineType.Regular, 5.67));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_ans_unification", n"phone", n"CHISPA", scnDialogLineType.Holocall, 24.88));
            this.m_sys.StartSpeechSequence(steps, 411);
            return true;
        }
        if optionId == 42 {
            qs.SetFact(n"chispa_ep03_asked_tygers", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_v_ask_tygers", n"player", n"V", scnDialogLineType.Regular, 6.48));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_ans_tygers", n"phone", n"CHISPA", scnDialogLineType.Holocall, 25.85));
            this.m_sys.StartSpeechSequence(steps, 412);
            return true;
        }
        if optionId == 43 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_v_outro_accept", n"player", n"V", scnDialogLineType.Regular, 8.40));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_outro", n"phone", n"CHISPA", scnDialogLineType.Holocall, 17.66));
            this.m_sys.StartSpeechSequence(steps, 420);
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

        jm.ChangeEntryState("contacts/chispa_ai/conv_ep03/msg_ep03_summary", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep03", "gameJournalOnscreen", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/04_ep03_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/desc_ep03_done", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);

        this.m_sys.ShowRelicBanner(n"ch_banner_ep03_done", "[CHISPA] Episodio 3 completado — Campaña en Watson finalizada");
        qs.SetFact(n"chispa_ep03_done", 1);
        qs.SetFact(n"chispa_season_stage", 400);
        qs.SetFact(n"chispa_ep03_stage", 5);
    }

    public final func Tick(player: ref<PlayerPuppet>, phoneOpen: Bool, fullGameplay: Bool) -> Float {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep03_stage");

        if qs.GetFact(n"chispa_ep03_done") == 0 && stage == 0 {
            if !fullGameplay || this.m_sys.m_sessionReadyTicks < 6 {
                return 0.45;
            }
            if this.m_sys.m_isPlayingDialogueSequence || this.m_sys.IsExternalPhoneCallBusy() {
                this.m_introWaitTicks = 0;
                return 0.60;
            }
            this.m_introWaitTicks += 1;
            if this.m_introWaitTicks >= 5 {
                this.ActivateJournalQuest();
                this.ActivateIntroSms();
                this.m_sys.ShowRelicBanner(n"ch_banner_ep03_start", "[CHISPA] Eco corporativo en el muelle sur — Revisa tu holoteléfono");
                qs.SetFact(n"chispa_ep03_stage", 1);
                qs.SetFact(n"chispa_ep03_call_done", 0);
                if !this.m_sys.m_activeCallPendingPickup {
                    this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 31);
                }
            }
            return 0.60;
        }

        if stage == 1 {
            this.ActivateJournalQuest();
            this.CheckSmsReply();
            if qs.GetFact(n"chispa_ep03_call_done") == 0
                && !this.m_sys.m_activeCallPendingPickup
                && !this.m_sys.m_isPlayingDialogueSequence
                && this.m_sys.m_sessionReadyTicks >= 6
                && fullGameplay
                && !this.m_sys.IsExternalPhoneCallBusy() {
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 31);
            }
            return 0.25;
        }

        if stage == 2 {
            this.m_sys.HideDialogChoices();
            this.m_sys.SyncObjectivePinLoop(
                32,
                "quests/side_quest/chispa_ep03_quest",
                "quests/side_quest/chispa_ep03_quest/phase_ep03",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/mp_ep03_waterfront",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let pylonPos: Vector4 = this.m_spawned ? this.m_pylonPos : this.GetPylonPos();
            this.m_sys.UpdateFallbackMappin(
                32,
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear",
                new Vector4(pylonPos.X, pylonPos.Y, pylonPos.Z + 1.65, 1.00),
                n"ch_mappin_ep03_waterfront",
                "CHISPA Ep. 3: Muelle Sur de Arasaka"
            );

            let distPylonSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), pylonPos);
            if distPylonSq <= 900.00 && qs.GetFact(n"chispa_ep03_approach_played") == 0 && !this.m_sys.m_isPlayingDialogueSequence {
                qs.SetFact(n"chispa_ep03_approach_played", 1);
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_approach", n"phone", n"CHISPA", scnDialogLineType.Holocall, 19.51));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            if this.m_pendingSmartJamBark && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingSmartJamBark = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_smart_jam", n"phone", n"CHISPA", scnDialogLineType.Holocall, 15.73));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingJammerBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingJammerBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_jammer_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.43));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            let centerCombatPos: Vector4 = new Vector4(-2022.00, 1568.20, pylonPos.Z, 1.00);
            if this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), centerCombatPos) <= 56.25 && qs.GetFact(n"chispa_ep03_combat_started") == 0 {
                this.OnTygerProvoked(player, false);
            }

            let scannedFlag: Bool = qs.GetFact(n"chispa_ep03_scanned") > 0;
            let canReachPylon: Bool = qs.GetFact(n"chispa_ep03_jammer_down") == 0
                && ((scannedFlag && distPylonSq <= 324.00) || distPylonSq <= 64.00);
            if canReachPylon && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(40, n"ch_hub_ep03_pylon_title", "BALIZA INHIBIDORA IFF ARASAKA", n"ch_act_invert_pylon", "Invertir baliza IFF y sobrecargar condensador [Kiroshi]", false);
            } else {
                this.m_sys.HideWorldInteraction();
            }

            if EntityID.IsDefined(this.m_aikoId) && this.IsSquadDefeated() {
                this.m_sys.HideWorldInteraction();
                jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
                this.m_sys.ActivateObjectiveWithPin(
                    33,
                    "quests/side_quest/chispa_ep03_quest",
                    "quests/side_quest/chispa_ep03_quest/phase_ep03",
                    "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract",
                    "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract/mp_ep03_rig",
                    "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract/desc_ep03_03",
                    this.AllPinPaths(),
                    true
                );
                qs.SetFact(n"chispa_ep03_stage", 3);
                if qs.GetFact(n"chispa_ep03_used_smart") > 0 {
                    if this.m_sys.m_isPlayingDialogueSequence {
                        this.m_pendingSmartVictory = true;
                    } else {
                        this.m_pendingSmartVictory = false;
                        let steps: array<ref<ChispaSpeechStep>>;
                        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_smart_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.36));
                        this.m_sys.StartSpeechSequence(steps, 0);
                    }
                } else {
                    if this.m_sys.m_isPlayingDialogueSequence {
                        this.m_pendingGunsBlazing = true;
                    } else {
                        this.m_pendingGunsBlazing = false;
                        let steps: array<ref<ChispaSpeechStep>>;
                        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 13.43));
                        this.m_sys.StartSpeechSequence(steps, 0);
                    }
                }
            }
            return distPylonSq <= 400.00 ? 0.12 : 0.45;
        }

        if stage == 3 {
            this.m_sys.HideDialogChoices();
            if this.m_pendingJammerBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingJammerBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_jammer_boom", n"phone", n"CHISPA", scnDialogLineType.Holocall, 11.43));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingSmartVictory && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingSmartVictory = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_smart_victory", n"phone", n"CHISPA", scnDialogLineType.Holocall, 12.36));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingGunsBlazing && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingGunsBlazing = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep03_guns_blazing", n"phone", n"CHISPA", scnDialogLineType.Holocall, 13.43));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            this.m_sys.SyncObjectivePinLoop(
                33,
                "quests/side_quest/chispa_ep03_quest",
                "quests/side_quest/chispa_ep03_quest/phase_ep03",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract/mp_ep03_rig",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let rigPos: Vector4 = this.m_spawned ? this.m_rigPos : this.GetRigPos();
            this.m_sys.UpdateFallbackMappin(
                33,
                "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract",
                new Vector4(rigPos.X, rigPos.Y, rigPos.Z + 1.55, 1.00),
                n"ch_mappin_ep03_rig",
                "CHISPA Ep. 3: Alijo Corporativo"
            );
            let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), rigPos);
            if distSq <= 14.00 && !this.m_sys.IsSpeechBlockingWorldInteraction() && !this.m_sys.IsUiBlockingWorldInput() {
                this.m_sys.ShowWorldInteraction(41, n"ch_hub_ep03_rig_title", "CONTENEDOR NEGRO DE ARASAKA", n"ch_act_claim_sec03", "Extraer Sector de Memoria #03 [C.H.I.S.P.A.]", false, distSq <= 7.84);
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
        if qs.GetFact(n"chispa_ep03_stage") < 1 {
            qs.SetFact(n"chispa_ep03_stage", 1);
            this.ActivateJournalQuest();
        }
        qs.SetFact(n"chispa_ep03_call_done", 0);
        this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 31);
    }

    public final func TeleportToWaterfront() -> Void {
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
        if qs.GetFact(n"chispa_ep03_stage") < 2 {
            this.ActivateJournalQuest();
            this.ActivateIntroSms();
            this.GrantStarterSmartKit(player);
            jm.ChangeEntryState("quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            this.m_sys.ActivateObjectiveWithPin(
                32,
                "quests/side_quest/chispa_ep03_quest",
                "quests/side_quest/chispa_ep03_quest/phase_ep03",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/mp_ep03_waterfront",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/desc_ep03_02",
                this.AllPinPaths(),
                true
            );
            qs.SetFact(n"chispa_ep03_call_done", 1);
            qs.SetFact(n"chispa_ep03_sms_replied", 32);
            qs.SetFact(n"chispa_ep03_stage", 2);
        }
        this.m_sys.EnsureSmartBridgeActive(player);
        let dest: Vector4 = this.GetArrivalPos();
        let ang: EulerAngles;
        ang.Yaw = 5.00;
        GameInstance.GetTeleportationFacility(game).Teleport(player, dest, ang);
        this.EnsureSpawned(player);
    }
}
