// Protocolo CHISPA / SPARKY Protocol — Episodio 0: «No soy un clip de oficina»
module ChispaNC

public class ChispaEp00Handler {
    private let m_sys: wref<ChispaSystem>;
    private let m_spawned: Bool;
    private let m_consoleId: EntityID;
    private let m_dongleId: EntityID;
    private let m_capacitorId: EntityID;
    private let m_roccoId: EntityID;
    private let m_tinoId: EntityID;
    private let m_roccoReady: Bool;
    private let m_tinoReady: Bool;
    private let m_pendingTrapBoom: Bool;
    private let m_pendingGunsBlazingBark: Bool;
    private let m_consolePos: Vector4;
    private let m_capacitorPos: Vector4;
    private let m_combatStartedAt: Float;

    public final func Init(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
        this.ResetRuntimeFlags();
    }

    public final func GetConsolePos() -> Vector4 = new Vector4(-1338.69, 1264.53, 17.06, 1.00);
    public final func GetCapacitorPos() -> Vector4 = new Vector4(-1342.40, 1261.90, 17.06, 1.00);

    public final func ResetRuntimeFlags() -> Void {
        this.m_spawned = false;
        this.m_consoleId = new EntityID();
        this.m_dongleId = new EntityID();
        this.m_capacitorId = new EntityID();
        this.m_roccoId = new EntityID();
        this.m_tinoId = new EntityID();
        this.m_roccoReady = false;
        this.m_tinoReady = false;
        this.m_pendingTrapBoom = false;
        this.m_pendingGunsBlazingBark = false;
        this.m_consolePos = this.GetConsolePos();
        this.m_capacitorPos = this.GetCapacitorPos();
        this.m_combatStartedAt = 0.00;
    }

    private final func AllPinPaths() -> array<String> {
        return [
            "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/mp_ep00_alley",
            "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/mp_ep00_console"
        ];
    }

    public final func CleanupEntities() -> Void {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) {
            des.DeleteTagged(n"ChispaNPC");
            des.DeleteTagged(n"ChispaEp00Rocco");
            des.DeleteTagged(n"ChispaEp00Tino");
        }
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaProp");
            ses.DespawnTagged(n"ChispaEp00Console");
            ses.DespawnTagged(n"ChispaEp00Dongle");
            ses.DespawnTagged(n"ChispaEp00Capacitor");
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
            "quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms/desc_ep00_01",
            "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/desc_ep00_02",
            "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/desc_ep00_03",
            "quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa/desc_ep00_04",
            "quests/side_quest/chispa_nc_quest/phase_ep00/desc_ep00_done"
        ];
        for dp in descPaths {
            jm.ChangeEntryState(dp, "gameJournalQuestDescription", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        let objPaths: array<String> = [
            "quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms",
            "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley",
            "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa",
            "quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa"
        ];
        for op in objPaths {
            jm.ChangeEntryState(op, "gameJournalQuestObjective", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }

        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00", "gameJournalQuestPhase", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest", "gameJournalQuest", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        let smsPaths: array<String> = [
            "contacts/chispa_ai/conv_ep00/msg_ep00_hook",
            "contacts/chispa_ai/conv_ep00/msg_ep00_century",
            "contacts/chispa_ai/conv_ep00/msg_ep00_coords",
            "contacts/chispa_ai/conv_ep00/msg_ep00_summary"
        ];
        for sp in smsPaths {
            jm.ChangeEntryState(sp, "gameJournalPhoneMessage", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/choices_ep00/reply_century", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/choices_ep00/reply_coords", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/choices_ep00", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep00", "gameJournalOnscreen", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);

        qs.SetFact(n"chispa_ep00_call_done", 0);
        qs.SetFact(n"chispa_ep00_sms_replied", 0);
        qs.SetFact(n"chispa_ep00_approach_played", 0);
        qs.SetFact(n"chispa_ep00_scanned", 0);
        qs.SetFact(n"chispa_ep00_scan_react_played", 0);
        qs.SetFact(n"chispa_ep00_cap_blown", 0);
        qs.SetFact(n"chispa_ep00_used_trap", 0);
        qs.SetFact(n"chispa_ep00_combat_started", 0);
        qs.SetFact(n"chispa_ep00_asked_night", 0);
        qs.SetFact(n"chispa_ep00_asked_mega", 0);
        qs.SetFact(n"chispa_ep00_asked_deal", 0);
        qs.SetFact(n"chispa_ep00_done", 0);
        qs.SetFact(n"chispa_season_stage", 0);
        qs.SetFact(n"chispa_ep00_stage", 0);
        qs.SetFact(n"chispa_ep00_xp_sector", 0);
        qs.SetFact(n"chispa_ep00_xp_done", 0);
    }

    // --- Callbacks de Audio, Llamadas y SMS ---

    public final func GetCallSteps(stageTag: Int32, out completeAction: Int32) -> array<ref<ChispaSpeechStep>> {
        let steps: array<ref<ChispaSpeechStep>>;
        if !IsDefined(this.m_sys) || stageTag != 1 {
            return steps;
        }
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_call_01", n"phone", n"SPARKY", scnDialogLineType.Holocall, 11.52));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_v_call_01", n"player", n"V", scnDialogLineType.Regular, 7.68));
        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_call_02", n"phone", n"SPARKY", scnDialogLineType.Holocall, 10.88));
        completeAction = 101;
        return steps;
    }

    public final func OnCallRejected(stageTag: Int32) -> Void {
        if IsDefined(this.m_sys) && stageTag == 1 {
            GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance()).SetFact(n"chispa_ep00_call_done", 1);
            this.ActivateIntroSms();
        }
    }

    public final func OnPostSpeech(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if actionId == 101 {
            qs.SetFact(n"chispa_ep00_call_done", 1);
            this.m_sys.EndCustomCall(n"chispa_ai", this.m_sys.m_activeCallIsVideo);
            this.ActivateIntroSms();
            return;
        }
        if actionId == 109 || actionId == 110 || actionId == 111 || actionId == 112 {
            if qs.GetFact(n"chispa_ep00_stage") == 4 && !this.m_sys.IsUiBlockingWorldInput() {
                this.ShowDialogHub();
            }
            return;
        }
        if actionId == 120 {
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
        let qEntry: wref<JournalEntry> = jm.GetEntryByString("quests/side_quest/chispa_nc_quest", "gameJournalQuest");
        if !IsDefined(qEntry) {
            return;
        }
        let qState: gameJournalEntryState = jm.GetEntryState(qEntry);
        if Equals(qState, gameJournalEntryState.Active) || Equals(qState, gameJournalEntryState.Succeeded) {
            return;
        }
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest", "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00", "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms/desc_ep00_01", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        if !IsDefined(jm.GetTrackedEntry()) {
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms");
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
        let msgEntry: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep00/msg_ep00_hook", "gameJournalPhoneMessage");
        if IsDefined(msgEntry) && Equals(jm.GetEntryState(msgEntry), gameJournalEntryState.Active) {
            return;
        }
        jm.ChangeEntryState("contacts/chispa_ai", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00", "gameJournalPhoneConversation", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/msg_ep00_hook", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/choices_ep00", "gameJournalPhoneChoiceGroup", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/choices_ep00/reply_century", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/choices_ep00/reply_coords", "gameJournalPhoneChoiceEntry", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
    }

    public final func CheckSmsReply() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(jm) || qs.GetFact(n"chispa_ep00_stage") != 1 || qs.GetFact(n"chispa_ep00_sms_replied") > 0 {
            return;
        }
        let rCentury: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep00/choices_ep00/reply_century", "gameJournalPhoneChoiceEntry");
        let rCoords: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai/conv_ep00/choices_ep00/reply_coords", "gameJournalPhoneChoiceEntry");

        let replyKind: Int32 = 0;
        if IsDefined(rCentury) && Equals(jm.GetEntryState(rCentury), gameJournalEntryState.Succeeded) {
            replyKind = 1;
        } else if IsDefined(rCoords) && Equals(jm.GetEntryState(rCoords), gameJournalEntryState.Succeeded) {
            replyKind = 2;
        }
        if replyKind == 0 {
            return;
        }

        qs.SetFact(n"chispa_ep00_sms_replied", replyKind);
        let cb: ref<ChispaSmsDelayCallback> = new ChispaSmsDelayCallback();
        cb.system = this.m_sys;
        cb.actionId = replyKind;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, 0.90, false);
    }

    public final func OnDelayedSmsAction(actionId: Int32) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if actionId == 1 {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/msg_ep00_century", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        } else {
            jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/msg_ep00_coords", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        }
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        this.m_sys.ActivateObjectiveWithPin(
            2,
            "quests/side_quest/chispa_nc_quest",
            "quests/side_quest/chispa_nc_quest/phase_ep00",
            "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley",
            "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/mp_ep00_alley",
            "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/desc_ep00_02",
            this.AllPinPaths(),
            true
        );
        qs.SetFact(n"chispa_ep00_stage", 2);
    }

    // --- Escena Táctica del Solar Trasero H10 ---

    private final func EnsureSpawned(player: ref<PlayerPuppet>) -> Void {
        let basePos: Vector4 = this.GetConsolePos();
        let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), basePos);
        if distSq > 4225.00 {
            return;
        }

        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep00_stage");
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();

        if IsDefined(ses) && ses.IsReady() {
            if !this.m_sys.IsStaticPropAliveOrSpawning(this.m_consoleId) {
                ses.DespawnTagged(n"ChispaEp00Console");
                let zCon: Float = this.m_sys.FindGroundZ(basePos);
                this.m_consolePos = new Vector4(basePos.X, basePos.Y, zCon, 1.00);
                this.m_consoleId = this.m_sys.SpawnStaticProp(r"chispa_nc\\entities\\chispa_briefcase_rig.ent", this.m_consolePos, 35.00, n"ChispaEp00Console");
            }
            if (stage == 2 || stage == 3) && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_dongleId) {
                ses.DespawnTagged(n"ChispaEp00Dongle");
                let zCon: Float = this.m_sys.FindGroundZ(basePos);
                this.m_consolePos = new Vector4(basePos.X, basePos.Y, zCon, 1.00);
                this.m_dongleId = this.m_sys.SpawnStaticProp(r"chispa_nc\\entities\\chispa_dongle_shard.ent", this.m_consolePos, 35.00, n"ChispaEp00Dongle");
            }
            if qs.GetFact(n"chispa_ep00_cap_blown") == 0 && !this.m_sys.IsStaticPropAliveOrSpawning(this.m_capacitorId) {
                ses.DespawnTagged(n"ChispaEp00Capacitor");
                let capBase: Vector4 = this.GetCapacitorPos();
                let zCap: Float = this.m_sys.FindGroundZ(capBase);
                this.m_capacitorPos = new Vector4(capBase.X, capBase.Y, zCap, 1.00);
                this.m_capacitorId = this.m_sys.SpawnStaticProp(r"chispa_nc\\entities\\chispa_hazard_capacitor.ent", this.m_capacitorPos, 15.00, n"ChispaEp00Capacitor");
            }
        }

        if stage == 2 {
            let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
            if IsDefined(des) && des.IsReady() {
                if !EntityID.IsDefined(this.m_roccoId) && !this.m_sys.IsDynamicEntityAliveOrSpawning(this.m_roccoId) {
                    des.DeleteTagged(n"ChispaEp00Rocco");
                    des.DeleteTagged(n"ChispaEp00Tino");

                    let rXY: Vector4 = new Vector4(-1341.60, 1260.70, basePos.Z, 1.00);
                    let tXY: Vector4 = new Vector4(-1343.20, 1262.80, basePos.Z, 1.00);
                    let zR: Float = this.m_sys.FindGroundZ(rXY);
                    let zT: Float = this.m_sys.FindGroundZ(tXY);

                    this.m_roccoReady = false;
                    this.m_tinoReady = false;
                    this.m_roccoId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep00_Rocco", new Vector4(rXY.X, rXY.Y, zR, 1.00), 125.00, n"ChispaEp00Rocco");
                    this.m_tinoId = this.m_sys.SpawnDynamicNpc(t"Character.Chispa_Ep00_Tino", new Vector4(tXY.X, tXY.Y, zT, 1.00), 140.00, n"ChispaEp00Tino");
                }
                if !this.m_roccoReady && EntityID.IsDefined(this.m_roccoId) && des.IsSpawned(this.m_roccoId) {
                    let rNpc: ref<NPCPuppet> = des.GetEntity(this.m_roccoId) as NPCPuppet;
                    if IsDefined(rNpc) && ScriptedPuppet.IsActive(rNpc) {
                        this.m_roccoReady = true;
                    }
                }
                if !this.m_tinoReady && EntityID.IsDefined(this.m_tinoId) && des.IsSpawned(this.m_tinoId) {
                    let tNpc: ref<NPCPuppet> = des.GetEntity(this.m_tinoId) as NPCPuppet;
                    if IsDefined(tNpc) && ScriptedPuppet.IsActive(tNpc) {
                        this.m_tinoReady = true;
                    }
                }
            }
        }
        this.m_spawned = true;
    }

    public final func OnTargetScanned(recID: TweakDBID) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        if qs.GetFact(n"chispa_ep00_stage") != 2 {
            return;
        }
        if qs.GetFact(n"chispa_ep00_scanned") == 0 {
            qs.SetFact(n"chispa_ep00_scanned", 1);
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
        }
    }

    public final func OnThugsProvoked(player: ref<PlayerPuppet>) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || qs.GetFact(n"chispa_ep00_stage") != 2 {
            return;
        }
        let alreadyCombat: Bool = qs.GetFact(n"chispa_ep00_combat_started") > 0;
        if !alreadyCombat {
            qs.SetFact(n"chispa_ep00_combat_started", 1);
            this.m_combatStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        }
        let rocco: ref<NPCPuppet> = des.GetEntity(this.m_roccoId) as NPCPuppet;
        let tino: ref<NPCPuppet> = des.GetEntity(this.m_tinoId) as NPCPuppet;
        if IsDefined(rocco) && !rocco.IsDead() {
            this.m_sys.MakeNpcHostile(rocco, player);
            if !alreadyCombat && !this.m_sys.m_isPlayingDialogueSequence {
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_rocco_bark", n"ChispaEp00Rocco", n"Rocco", scnDialogLineType.Regular, 5.99));
                this.m_sys.StartSpeechSequence(steps, 0);
            }
        }
        if IsDefined(tino) && !tino.IsDead() {
            this.m_sys.MakeNpcHostile(tino, player);
        }
    }

    public final func TriggerCapacitorOverload() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep00_cap_blown") > 0 {
            return;
        }

        qs.SetFact(n"chispa_ep00_cap_blown", 1);
        qs.SetFact(n"chispa_ep00_used_trap", 1);
        qs.SetFact(n"chispa_ep00_combat_started", 1);
        this.m_combatStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));

        this.m_sys.PlaySfx(n"ch_sfx_capacitor_arc");
        this.m_sys.ShowRelicBanner(n"ch_banner_ep00_cap", "[SPARKY] Capacitor overloaded! Arc blast jolted the scav crew");

        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if IsDefined(ses) {
            ses.DespawnTagged(n"ChispaEp00Capacitor");
        }
        this.m_capacitorId = new EntityID();

        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);
        if IsDefined(des) {
            let tino: ref<NPCPuppet> = des.GetEntity(this.m_tinoId) as NPCPuppet;
            if IsDefined(tino) && !tino.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(tino, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(tino, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(tino.GetEntityID()), gamedataStatPoolType.Health, -100.0, player, true, true);
                }
                tino.Kill(player);
            }
            let rocco: ref<NPCPuppet> = des.GetEntity(this.m_roccoId) as NPCPuppet;
            if IsDefined(rocco) && !rocco.IsDead() {
                StatusEffectHelper.ApplyStatusEffect(rocco, t"BaseStatusEffect.Overload");
                StatusEffectHelper.ApplyStatusEffect(rocco, t"BaseStatusEffect.Electrocuted");
                if IsDefined(poolSys) {
                    poolSys.RequestChangingStatPoolValue(Cast<StatsObjectID>(rocco.GetEntityID()), gamedataStatPoolType.Health, -65.0, player, true, true);
                }
                this.m_sys.MakeNpcHostile(rocco, player);
            }
        }

        if this.m_sys.m_isPlayingDialogueSequence {
            this.m_pendingTrapBoom = true;
        } else {
            this.m_pendingTrapBoom = false;
            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_trap_boom", n"phone", n"SPARKY", scnDialogLineType.Holocall, 7.82));
            this.m_sys.StartSpeechSequence(steps, 0);
        }
    }

    private final func IsSquadDefeated() -> Bool {
        if !EntityID.IsDefined(this.m_roccoId) || !EntityID.IsDefined(this.m_tinoId) {
            return false;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if qs.GetFact(n"chispa_ep00_used_trap") == 0 && (!this.m_roccoReady || !this.m_tinoReady) {
            return false;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let anchor: Vector4 = this.GetConsolePos();
        if !IsDefined(player) || this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), anchor) > 3600.00 {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        let elapsed: Float = this.m_combatStartedAt > 0.01 ? (now - this.m_combatStartedAt) : 0.00;
        let roccoDown: Bool = this.m_sys.IsNpcNeutralized(this.m_roccoId, anchor, elapsed, false);
        let allowFar: Bool = roccoDown && elapsed >= 10.00 && !player.IsInCombat();
        return roccoDown && this.m_sys.IsNpcNeutralized(this.m_tinoId, anchor, elapsed, allowFar);
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

        if kind == 10 {
            this.TriggerCapacitorOverload();
            return true;
        }

        if kind == 11 {
            this.m_pendingTrapBoom = false;
            this.m_pendingGunsBlazingBark = false;
            let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
            if IsDefined(ses) {
                ses.DespawnTagged(n"ChispaEp00Dongle");
            }
            this.m_dongleId = new EntityID();

            let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
            ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle"), 1);
            ts.GiveMoney(player, 1500, n"money");
            this.m_sys.GiveItemDelayed(t"Items.Preset_Lexington_Chispa", 1, 1.15);
            GameObject.PlaySoundEvent(player, n"ui_loot_cash");
            this.m_sys.PlaySfx(n"ch_sfx_dongle_sync");
            this.m_sys.ShowRelicBanner(n"ch_banner_ep00_claimed", "[SPARKY] S.P.A.R.K.Y. linked (+1,500 E$ & Executive Courtesy)");

            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
            this.m_sys.DeactivateJournalPinList(this.AllPinPaths());
            this.m_sys.ClearMappin();
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa/desc_ep00_04", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa", "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);
            this.m_sys.TrackQuestObjective("quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa");
            qs.SetFact(n"chispa_ep00_stage", 4);
            this.m_sys.EnsureCoprocessorRamBridgeActive(player);
            this.m_sys.AwardMilestoneXP(n"chispa_ep00_xp_sector", 350, 400, gamedataProficiencyType.TechnicalAbilitySkill, 150);

            let steps: array<ref<ChispaSpeechStep>>;
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_dongle_pickup", n"phone", n"SPARKY", scnDialogLineType.Holocall, 10.52));
            this.m_sys.StartSpeechSequence(steps, 109);
            return true;
        }

        if kind == 12 {
            this.ShowDialogHub();
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

        if qs.GetFact(n"chispa_ep00_asked_night") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep00_night", "Looking around this alley... who the hell built Night City like this?"), false, false));
            ArrayPush(ids, 10);
        }
        if qs.GetFact(n"chispa_ep00_asked_mega") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep00_mega", "And these giant Megabuildings? Looks like a vertical prison."), false, false));
            ArrayPush(ids, 11);
        }
        if qs.GetFact(n"chispa_ep00_asked_deal") == 0 {
            ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep00_deal", "Okay, definitely not an office paperclip. What's the deal from here?"), false, false));
            ArrayPush(ids, 12);
        }
        ArrayPush(choices, this.m_sys.MakeDialogChoice(this.m_sys.GetLoc(n"ch_choice_ep00_accept", "Deal, SPARKY. Ping me once you lock onto your first sector in Kabuki."), true, false));
        ArrayPush(ids, 13);

        this.m_sys.PushDialogHub(n"chispa_ep00", this.m_sys.GetLoc(n"ch_hub_chispa_title", "S.P.A.R.K.Y. v0.98b (Kiroshi Link)"), choices, ids);
    }

    public final func HandleDialogOption(optionId: Int32) -> Bool {
        if !IsDefined(this.m_sys) {
            return false;
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.m_sys.GetGameInstance());
        let steps: array<ref<ChispaSpeechStep>>;

        if optionId == 10 {
            qs.SetFact(n"chispa_ep00_asked_night", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_v_ask_night", n"player", n"V", scnDialogLineType.Regular, 4.88));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_ans_night", n"phone", n"SPARKY", scnDialogLineType.Holocall, 15.08));
            this.m_sys.StartSpeechSequence(steps, 110);
            return true;
        }
        if optionId == 11 {
            qs.SetFact(n"chispa_ep00_asked_mega", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_v_ask_mega", n"player", n"V", scnDialogLineType.Regular, 7.12));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_ans_mega", n"phone", n"SPARKY", scnDialogLineType.Holocall, 15.70));
            this.m_sys.StartSpeechSequence(steps, 111);
            return true;
        }
        if optionId == 12 {
            qs.SetFact(n"chispa_ep00_asked_deal", 1);
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_v_ask_deal", n"player", n"V", scnDialogLineType.Regular, 5.84));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_ans_deal", n"phone", n"SPARKY", scnDialogLineType.Holocall, 13.35));
            this.m_sys.StartSpeechSequence(steps, 112);
            return true;
        }
        if optionId == 13 {
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_v_deal_accept", n"player", n"V", scnDialogLineType.Regular, 5.63));
            ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_outro", n"phone", n"SPARKY", scnDialogLineType.Holocall, 10.30));
            this.m_sys.StartSpeechSequence(steps, 120);
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

        jm.ChangeEntryState("contacts/chispa_ai/conv_ep00/msg_ep00_summary", "gameJournalPhoneMessage", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("onscreens/chispa_shards/chispa_shard_ep00", "gameJournalOnscreen", gameJournalEntryState.Active, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/desc_ep00_done", "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        jm.ChangeEntryState("quests/side_quest/chispa_nc_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);

        this.m_sys.ShowRelicBanner(n"ch_banner_ep00_done", "[SPARKY] Episode 0 complete — Wait for SPARKY's ping in Kabuki");
        qs.SetFact(n"chispa_ep00_done", 1);
        qs.SetFact(n"chispa_season_stage", 100);
        qs.SetFact(n"chispa_ep00_stage", 5);
        this.m_sys.AwardMilestoneXP(n"chispa_ep00_xp_done", 450, 450, gamedataProficiencyType.Level, 0);
    }

    public final func Tick(player: ref<PlayerPuppet>, phoneOpen: Bool, fullGameplay: Bool) -> Float {
        let game: GameInstance = this.m_sys.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let stage: Int32 = qs.GetFact(n"chispa_ep00_stage");

        if stage <= 0 {
            this.m_sys.HideDialogChoices();
            this.m_sys.HideWorldInteraction();
            this.m_sys.ClearMappin();
            if this.m_sys.m_sessionReadyTicks >= 6 && fullGameplay && this.m_sys.HasReachedNightCityAct1(player) && !this.m_sys.IsExternalPhoneCallBusy() {
                qs.SetFact(n"chispa_ep00_stage", 1);
                qs.SetFact(n"chispa_ep00_call_done", 0);
                this.ActivateJournalQuest();
                this.m_sys.ShowRelicBanner(n"ch_banner_ep00_start", "[SPARKY] Encrypted 2022 concierge signal locked — Check your holo");
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 1);
                return 0.45;
            }
            return 0.60;
        }

        if stage == 1 {
            this.ActivateJournalQuest();
            this.CheckSmsReply();
            if qs.GetFact(n"chispa_ep00_call_done") == 0
                && !this.m_sys.m_activeCallPendingPickup
                && !this.m_sys.m_isPlayingDialogueSequence
                && this.m_sys.m_sessionReadyTicks >= 6
                && fullGameplay
                && this.m_sys.HasReachedNightCityAct1(player)
                && !this.m_sys.IsExternalPhoneCallBusy() {
                this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 1);
            }
            return 0.25;
        }

        if stage == 2 {
            this.m_sys.HideDialogChoices();
            this.m_sys.SyncObjectivePinLoop(
                2,
                "quests/side_quest/chispa_nc_quest",
                "quests/side_quest/chispa_nc_quest/phase_ep00",
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley",
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/mp_ep00_alley",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let conPos: Vector4 = this.m_spawned ? this.m_consolePos : this.GetConsolePos();
            this.m_sys.UpdateFallbackMappin(
                2,
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley",
                new Vector4(conPos.X, conPos.Y, conPos.Z + 1.55, 1.00),
                n"ch_mappin_ep00_alley",
                "SPARKY Ep. 0: H10 Backlot"
            );

            let distConSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), conPos);
            if distConSq <= 1024.00 && qs.GetFact(n"chispa_ep00_approach_played") == 0 && !this.m_sys.m_isPlayingDialogueSequence {
                qs.SetFact(n"chispa_ep00_approach_played", 1);
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_alley_approach", n"phone", n"SPARKY", scnDialogLineType.Holocall, 9.16));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            if this.m_pendingTrapBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingTrapBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_trap_boom", n"phone", n"SPARKY", scnDialogLineType.Holocall, 7.82));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            if qs.GetFact(n"chispa_ep00_scanned") > 0
                && qs.GetFact(n"chispa_ep00_scan_react_played") == 0
                && !this.m_sys.m_isPlayingDialogueSequence {
                qs.SetFact(n"chispa_ep00_scan_react_played", 1);
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_scan_react", n"phone", n"SPARKY", scnDialogLineType.Holocall, 9.41));
                this.m_sys.StartSpeechSequence(steps, 0);
            }

            let capPos: Vector4 = this.m_spawned ? this.m_capacitorPos : this.GetCapacitorPos();
            let distCapSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), capPos);

            if distCapSq <= 56.25 && qs.GetFact(n"chispa_ep00_combat_started") == 0 {
                this.OnThugsProvoked(player);
            }

            let scannedFlag: Bool = qs.GetFact(n"chispa_ep00_scanned") > 0;
            let canReachCap: Bool = qs.GetFact(n"chispa_ep00_cap_blown") == 0
                && ((scannedFlag && distCapSq <= 256.00) || distCapSq <= 16.00);
            if canReachCap && !this.m_sys.IsSpeechBlockingWorldInteraction() && !phoneOpen {
                this.m_sys.ShowWorldInteraction(10, n"ch_hub_cap_title", "Industrial Capacitor Bank", n"ch_act_overload_cap", "Overload industrial capacitor [Kiroshi]", false);
            } else {
                this.m_sys.HideWorldInteraction();
            }

            if EntityID.IsDefined(this.m_roccoId) && this.IsSquadDefeated() {
                this.m_sys.HideWorldInteraction();
                jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.Notify);
                this.m_sys.ActivateObjectiveWithPin(
                    3,
                    "quests/side_quest/chispa_nc_quest",
                    "quests/side_quest/chispa_nc_quest/phase_ep00",
                    "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa",
                    "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/mp_ep00_console",
                    "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/desc_ep00_03",
                    this.AllPinPaths(),
                    true
                );
                qs.SetFact(n"chispa_ep00_stage", 3);
                if qs.GetFact(n"chispa_ep00_used_trap") == 0 {
                    if this.m_sys.m_isPlayingDialogueSequence {
                        this.m_pendingGunsBlazingBark = true;
                    } else {
                        this.m_pendingGunsBlazingBark = false;
                        let steps: array<ref<ChispaSpeechStep>>;
                        ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_guns_blazing", n"phone", n"SPARKY", scnDialogLineType.Holocall, 7.66));
                        this.m_sys.StartSpeechSequence(steps, 0);
                    }
                }
            }
            return distConSq <= 256.00 ? 0.12 : 0.45;
        }

        if stage == 3 {
            this.m_sys.HideDialogChoices();
            if this.m_pendingTrapBoom && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingTrapBoom = false;
                let steps: array<ref<ChispaSpeechStep>>;
                ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_trap_boom", n"phone", n"SPARKY", scnDialogLineType.Holocall, 7.82));
                this.m_sys.StartSpeechSequence(steps, 0);
            } else if this.m_pendingGunsBlazingBark && !this.m_sys.m_isPlayingDialogueSequence {
                this.m_pendingGunsBlazingBark = false;
                if qs.GetFact(n"chispa_ep00_used_trap") == 0 {
                    let steps: array<ref<ChispaSpeechStep>>;
                    ArrayPush(steps, this.m_sys.MakeSpeechStep(n"ch_ep00_guns_blazing", n"phone", n"SPARKY", scnDialogLineType.Holocall, 7.66));
                    this.m_sys.StartSpeechSequence(steps, 0);
                }
            }
            this.m_sys.SyncObjectivePinLoop(
                3,
                "quests/side_quest/chispa_nc_quest",
                "quests/side_quest/chispa_nc_quest/phase_ep00",
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa",
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/mp_ep00_console",
                this.AllPinPaths()
            );
            this.EnsureSpawned(player);
            let conPos: Vector4 = this.m_spawned ? this.m_consolePos : this.GetConsolePos();
            this.m_sys.UpdateFallbackMappin(
                3,
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa",
                new Vector4(conPos.X, conPos.Y, conPos.Z + 1.55, 1.00),
                n"ch_mappin_ep00_console",
                "SPARKY Ep. 0: Zetatech 2022 Terminal"
            );
            let distSq: Float = this.m_sys.ComputeDistanceSq(player.GetWorldPosition(), conPos);
            if distSq <= 14.00 && !this.m_sys.IsSpeechBlockingWorldInteraction() && !phoneOpen {
                this.m_sys.ShowWorldInteraction(11, n"ch_hub_console_title", "Zetatech 2022 Tactical Terminal", n"ch_act_claim_chispa", "Connect S.P.A.R.K.Y. v0.98b coprocessor", false, distSq <= 7.84);
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
        if qs.GetFact(n"chispa_ep00_stage") < 1 {
            qs.SetFact(n"chispa_ep00_stage", 1);
            this.ActivateJournalQuest();
        }
        this.m_sys.StartCustomCall(n"chispa_ai", this.m_sys.IsVideocallModeEnabled(), 1);
    }

    public final func TeleportToAlley() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let pos: Vector4 = new Vector4(-1331.50, 1269.50, 17.20, 1.00);
        let ang: EulerAngles;
        ang.Yaw = 135.00;
        GameInstance.GetTeleportationFacility(game).Teleport(player, pos, ang);
    }
}
