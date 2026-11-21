// Protocolo CHISPA / SPARKY Protocol — Modular Core Engine (Base Game 2.x)
module ChispaNC

import Codeware.Localization.*

// ---------------------------------------------------------------------------
// Delay Callbacks
// ---------------------------------------------------------------------------

public class ChispaTickCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.OnTick();
        }
    }
}

public class ChispaSpeechStep {
    public let eventName: CName;
    public let speakerTag: CName;
    public let speakerName: CName;
    public let lineType: scnDialogLineType;
    public let fallbackDuration: Float;
}

public class ChispaSequenceCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let token: Int32;
    public let nextIndex: Int32;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.AdvanceSpeechSequence(this.token, this.nextIndex);
        }
    }
}

public class ChispaSpeechSubtitleCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let token: Int32;
    public let nextPageIndex: Int32;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.AdvanceSpeechSubtitlePage(this.token, this.nextPageIndex);
        }
    }
}

public class ChispaSpeechSubtitleReassertCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let token: Int32;
    public let expectedCruid: CRUID;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.ReassertActiveSpeechSubtitleIfNeeded(this.token, this.expectedCruid);
        }
    }
}

public class ChispaCallAnswerCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let contactName: CName;
    public let callToken: Int32;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.AnswerIncomingCallInternal(this.contactName, this.callToken, false);
        }
    }
}

public class ChispaSmsDelayCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let actionId: Int32;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.OnDelayedSmsAction(this.actionId);
        }
    }
}

public class ChispaWorldMapTrackCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.OnDeferredWorldMapAutoTrack();
        }
    }
}

public class ChispaLipSyncCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let token: Int32;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.OnLipSyncTick(this.token);
        }
    }
}

public class ChispaDelayedItemCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let itemTdbId: TweakDBID;
    public let amount: Int32;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.ExecuteDelayedItemGrant(this.itemTdbId, this.amount);
        }
    }
}

// ---------------------------------------------------------------------------
// Monitor de Sesión Real (ignora Menú Principal y pantallas de carga)
// ---------------------------------------------------------------------------

public class ChispaSessionService extends ScriptableService {
    private let m_sessionReady: Bool;
    private let m_sessionLoadSeq: Int32;

    public static func IsSessionReady() -> Bool {
        let svc: ref<ChispaSessionService> = GameInstance.GetScriptableServiceContainer().GetService(n"ChispaNC.ChispaSessionService") as ChispaSessionService;
        if IsDefined(svc) {
            return svc.m_sessionReady;
        }
        return false;
    }

    public static func GetSessionLoadSeq() -> Int32 {
        let svc: ref<ChispaSessionService> = GameInstance.GetScriptableServiceContainer().GetService(n"ChispaNC.ChispaSessionService") as ChispaSessionService;
        if IsDefined(svc) {
            return svc.m_sessionLoadSeq;
        }
        return 0;
    }

    private cb func OnLoad() -> Void {
        this.m_sessionReady = false;
        this.m_sessionLoadSeq = 0;
        let cbSys: ref<CallbackSystem> = GameInstance.GetCallbackSystem();
        cbSys.RegisterCallback(n"Session/BeforeStart", this, n"OnSessionEvent");
        cbSys.RegisterCallback(n"Session/Start", this, n"OnSessionEvent");
        cbSys.RegisterCallback(n"Session/Ready", this, n"OnSessionEvent");
        cbSys.RegisterCallback(n"Session/BeforeEnd", this, n"OnSessionEvent");
        cbSys.RegisterCallback(n"Session/End", this, n"OnSessionEvent");
    }

    private cb func OnSessionEvent(event: ref<GameSessionEvent>) -> Void {
        if event.IsPreGame() {
            this.m_sessionReady = false;
            return;
        }
        let name: CName = event.GetEventName();
        if Equals(name, n"Session/Ready") {
            this.m_sessionReady = true;
            this.m_sessionLoadSeq += 1;
        } else if Equals(name, n"Session/BeforeStart") || Equals(name, n"Session/Start") || Equals(name, n"Session/BeforeEnd") || Equals(name, n"Session/End") {
            this.m_sessionReady = false;
        }
    }
}

// ---------------------------------------------------------------------------
// Sistema Central Modular «Protocolo CHISPA»
// ---------------------------------------------------------------------------

public class ChispaSystem extends ScriptableSystem {
    // Ciclo de sesión
    public let m_tickScheduled: Bool;
    public let m_spawnGraceEnded: Bool;
    public let m_sessionReadyTicks: Int32;
    private let m_retroSyncDoneForSession: Bool;

    // Controlador de episodio actual (extensible por episodios en Episodes/*.reds)
    public let m_ep00: ref<ChispaEp00Handler>;
    public let m_ep01: ref<ChispaEp01Handler>;
    public let m_ep02: ref<ChispaEp02Handler>;
    public let m_ep03: ref<ChispaEp03Handler>;
    public let m_ep04: ref<ChispaEp04Handler>;
    public let m_ep05: ref<ChispaEp05Handler>;
    public let m_live: ref<ChispaLiveCompanionHandler>;
    private let m_smartBridgeMod: ref<gameStatModifierData>;
    private let m_ricochetBridgeMod: ref<gameStatModifierData>;

    // Orquestación de voces y lip-sync
    private let m_speechSteps: array<ref<ChispaSpeechStep>>;
    private let m_speechToken: Int32;
    private let m_speechActionOnComplete: Int32;
    public let m_isPlayingDialogueSequence: Bool;
    private let m_speechAllowManualSkip: Bool;
    private let m_currentSpeechIndex: Int32;
    private let m_speechStepStartedAt: Float;
    private let m_currentPlayingEvent: CName;
    private let m_currentPlayingEntity: EntityID;
    private let m_currentPlayingSpeaker: CName;
    private let m_currentPlayingBackend: Int32;
    private let m_currentPlayingVariant: CName;
    private let m_skipHintVisible: Bool;
    private let m_speechSubtitleSeq: Uint64;
    private let m_speechSubtitleToken: Int32;
    private let m_activeSpeechSubtitleCruid: CRUID;
    private let m_hasActiveSpeechSubtitle: Bool;
    private let m_speechSubtitlePages: array<String>;
    private let m_speechSubtitlePageDurs: array<Float>;
    private let m_speechSubtitleSpeakerObj: wref<GameObject>;
    private let m_speechSubtitleSpeakerName: String;
    private let m_speechSubtitleLineType: scnDialogLineType;
    private let m_uiMenuListener: ref<CallbackHandle>;
    private let m_pausedByUiMenu: Bool;
    private let m_coprocessorRamMod: ref<gameStatModifierData>;
    private let m_coprocessorRamBonus: Float;
    private let m_fastTravelStartedListener: ref<CallbackHandle>;
    private let m_fastTravelLoadingListener: ref<CallbackHandle>;
    private let m_fastTravelFinishedListener: ref<CallbackHandle>;
    private let m_fastTravelLoading: Bool;
    private let m_fastTravelStartedAt: Float;
    private let m_speechSeqDelayId: DelayID;
    private let m_speechSeqRemaining: Float;
    private let m_speechSeqExpectedDur: Float;
    private let m_speechSeqScheduledEngineAt: Float;
    private let m_speechSubDelayId: DelayID;
    private let m_speechSubCurrentPageIdx: Int32;
    private let m_speechSubRemaining: Float;
    private let m_speechSubExpectedDur: Float;
    private let m_speechSubScheduledEngineAt: Float;

    // Holollamadas y proyección holográfica directa Kiroshi
    public let m_activeCallContact: CName;
    public let m_activeCallIsVideo: Bool;
    public let m_activeCallToken: Int32;
    public let m_activeCallPendingPickup: Bool;
    public let m_activeCallStageTag: Int32;
    private let m_directHoloFeedOpen: Bool;
    private let m_callHudQueuedOrOpen: Bool;
    private let m_holoAvatarCtrl: wref<HudPhoneAvatarController>;

    // Marcadores y ruta GPS
    private let m_mappinId: NewMappinID;
    private let m_hasMappin: Bool;
    private let m_mappinStageTag: Int32;
    private let m_journalPinSyncedTag: Int32;
    private let m_journalPinRetryTicks: Int32;
    private let m_mappinTitle: String;
    private let m_mappinDesc: String;
    private let m_activeWorldMap: wref<WorldMapMenuGameController>;
    private let m_activeMapPinCtrl: wref<BaseWorldMapMappinController>;
    private let m_worldMapReady: Bool;

    // Elecciones de diálogo nativas e interacciones
    private let m_dialogActive: Bool;
    private let m_dialogOwnerTag: CName;
    private let m_dialogSelectedIdx: Int32;
    private let m_dialogOptionIds: array<Int32>;
    private let m_dialogOptionCount: Int32;
    private let m_dialogOpenedAt: Float;
    private let m_lastDialogNavAt: Float;
    private let m_dialogHubSeqId: Int32;
    private let m_dialogConfirmArmed: Bool;
    private let m_dialogWidgetCtrl: wref<dialogWidgetGameController>;
    private let m_interactionShown: Bool;
    private let m_interactionKind: Int32;

    // Estado facial / lip-sync
    private let m_lipSyncToken: Int32;
    private let m_lipSyncEntityId: EntityID;
    private let m_lipSyncRemaining: Float;

    public static func GetInstance(game: GameInstance) -> ref<ChispaSystem> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"ChispaNC.ChispaSystem") as ChispaSystem;
    }

    // --- Ciclo de Vida ---

    private final func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
        if !IsDefined(this.m_ep00) {
            this.m_ep00 = new ChispaEp00Handler();
        }
        this.m_ep00.Init(this);
        if !IsDefined(this.m_ep01) {
            this.m_ep01 = new ChispaEp01Handler();
        }
        this.m_ep01.Init(this);
        if !IsDefined(this.m_ep02) {
            this.m_ep02 = new ChispaEp02Handler();
        }
        this.m_ep02.Init(this);
        if !IsDefined(this.m_ep03) {
            this.m_ep03 = new ChispaEp03Handler();
        }
        this.m_ep03.Init(this);
        if !IsDefined(this.m_ep04) {
            this.m_ep04 = new ChispaEp04Handler();
        }
        this.m_ep04.Init(this);
        if !IsDefined(this.m_ep05) {
            this.m_ep05 = new ChispaEp05Handler();
        }
        this.m_ep05.Init(this);
        if !IsDefined(this.m_live) {
            this.m_live = new ChispaLiveCompanionHandler();
        }
        this.m_live.Init(this);
        this.m_smartBridgeMod = null;
        this.m_ricochetBridgeMod = null;
        this.m_coprocessorRamMod = null;
        this.m_coprocessorRamBonus = 0.00;

        this.m_speechSubtitleSpeakerObj = null;
        this.m_tickScheduled = false;
        this.m_spawnGraceEnded = false;
        this.m_sessionReadyTicks = 0;
        this.m_retroSyncDoneForSession = false;
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
        this.m_currentSpeechIndex = 0;
        this.m_speechStepStartedAt = 0.00;
        this.m_currentPlayingEvent = n"None";
        this.m_currentPlayingEntity = new EntityID();
        this.m_currentPlayingSpeaker = n"None";
        this.m_currentPlayingBackend = 0;
        this.m_currentPlayingVariant = n"None";
        this.m_skipHintVisible = false;
        this.m_speechSubtitleSeq = 0ul;
        this.m_speechSubtitleToken = 0;
        this.m_hasActiveSpeechSubtitle = false;
        ArrayClear(this.m_speechSubtitlePages);
        ArrayClear(this.m_speechSubtitlePageDurs);
        this.m_speechSubtitleSpeakerObj = null;
        this.m_speechSubtitleSpeakerName = "";
        this.m_speechSubtitleLineType = scnDialogLineType.Regular;
        this.m_speechSeqDelayId = GetInvalidDelayID();
        this.m_speechSeqRemaining = 0.00;
        this.m_speechSeqExpectedDur = 0.00;
        this.m_speechSeqScheduledEngineAt = 0.00;
        this.m_speechSubDelayId = GetInvalidDelayID();
        this.m_speechSubCurrentPageIdx = -1;
        this.m_speechSubRemaining = 0.00;
        this.m_speechSubExpectedDur = 0.00;
        this.m_speechSubScheduledEngineAt = 0.00;
        let uiSysBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_System);
        if IsDefined(uiSysBB) {
            if IsDefined(this.m_uiMenuListener) {
                uiSysBB.UnregisterListenerBool(GetAllBlackboardDefs().UI_System.IsInMenu, this.m_uiMenuListener);
            }
            this.m_uiMenuListener = uiSysBB.RegisterListenerBool(GetAllBlackboardDefs().UI_System.IsInMenu, this, n"OnUiMenuChanged");
            this.m_pausedByUiMenu = uiSysBB.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu);
        } else {
            this.m_pausedByUiMenu = false;
        }
        let ftBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().FastTRavelSystem);
        if IsDefined(ftBB) {
            if IsDefined(this.m_fastTravelStartedListener) {
                ftBB.UnregisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelStarted, this.m_fastTravelStartedListener);
            }
            if IsDefined(this.m_fastTravelLoadingListener) {
                ftBB.UnregisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelLoadingScreenStarted, this.m_fastTravelLoadingListener);
            }
            if IsDefined(this.m_fastTravelFinishedListener) {
                ftBB.UnregisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelLoadingScreenFinished, this.m_fastTravelFinishedListener);
            }
            this.m_fastTravelStartedListener = ftBB.RegisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelStarted, this, n"OnFastTravelFlagStarted");
            this.m_fastTravelLoadingListener = ftBB.RegisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelLoadingScreenStarted, this, n"OnFastTravelLoadingStarted");
            this.m_fastTravelFinishedListener = ftBB.RegisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelLoadingScreenFinished, this, n"OnFastTravelLoadingFinished");
        }
        this.m_fastTravelLoading = false;
        this.m_fastTravelStartedAt = 0.00;
        this.m_activeCallContact = n"None";
        this.m_activeCallPendingPickup = false;
        this.m_activeCallIsVideo = false;
        this.m_activeCallStageTag = 0;
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = false;
        this.m_dialogActive = false;
        this.m_dialogConfirmArmed = false;
        this.m_dialogHubSeqId = -774410;
        this.m_interactionShown = false;
        this.m_interactionKind = 0;
        this.m_mappinStageTag = -1;
        this.m_journalPinSyncedTag = -1;
        this.m_journalPinRetryTicks = 0;
        this.m_lipSyncToken = 0;
        this.m_lipSyncRemaining = 0.00;
        this.m_dialogOpenedAt = 0.00;
        this.m_lastDialogNavAt = 0.00;

        this.m_ep00.ResetRuntimeFlags();
        this.m_ep01.ResetRuntimeFlags();
        this.m_ep02.ResetRuntimeFlags();
        this.m_ep03.ResetRuntimeFlags();
        this.m_ep04.ResetRuntimeFlags();
        this.m_ep05.ResetRuntimeFlags();
        this.m_live.ResetRuntime();
        this.ScheduleTick(0.60);
    }

    private func OnDetach() -> Void {
        if IsDefined(this.m_uiMenuListener) {
            let uiSysBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_System);
            if IsDefined(uiSysBB) {
                uiSysBB.UnregisterListenerBool(GetAllBlackboardDefs().UI_System.IsInMenu, this.m_uiMenuListener);
            }
            this.m_uiMenuListener = null;
        }
        this.m_pausedByUiMenu = false;
        let ftBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().FastTRavelSystem);
        if IsDefined(this.m_fastTravelStartedListener) {
            if IsDefined(ftBB) {
                ftBB.UnregisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelStarted, this.m_fastTravelStartedListener);
            }
            this.m_fastTravelStartedListener = null;
        }
        if IsDefined(this.m_fastTravelLoadingListener) {
            if IsDefined(ftBB) {
                ftBB.UnregisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelLoadingScreenStarted, this.m_fastTravelLoadingListener);
            }
            this.m_fastTravelLoadingListener = null;
        }
        if IsDefined(this.m_fastTravelFinishedListener) {
            if IsDefined(ftBB) {
                ftBB.UnregisterListenerBool(GetAllBlackboardDefs().FastTRavelSystem.FastTravelLoadingScreenFinished, this.m_fastTravelFinishedListener);
            }
            this.m_fastTravelFinishedListener = null;
        }
        this.m_fastTravelLoading = false;
        this.m_fastTravelStartedAt = 0.00;
        this.SetSkipSpeechHintVisible(false);
        this.StopCurrentSpeechAudio();
        this.StopNpcLipSync();
        this.HideDialogChoices();
        this.HideWorldInteraction();
        this.ClearMappin();
        if IsDefined(this.m_ep00) {
            this.m_ep00.CleanupEntities();
        }
        if IsDefined(this.m_ep01) {
            this.m_ep01.CleanupEntities();
        }
        if IsDefined(this.m_ep02) {
            this.m_ep02.CleanupEntities();
        }
        if IsDefined(this.m_ep03) {
            this.m_ep03.CleanupEntities();
        }
        if IsDefined(this.m_ep04) {
            this.m_ep04.CleanupEntities();
        }
        if IsDefined(this.m_ep05) {
            this.m_ep05.CleanupEntities();
        }
        if IsDefined(this.m_live) {
            this.m_live.ResetRuntime();
        }
        this.m_smartBridgeMod = null;
        this.m_ricochetBridgeMod = null;
        this.m_coprocessorRamMod = null;
        this.m_coprocessorRamBonus = 0.00;
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = false;
        this.m_activeWorldMap = null;
        this.m_dialogWidgetCtrl = null;
        this.m_holoAvatarCtrl = null;
        this.m_tickScheduled = false;
        this.m_spawnGraceEnded = false;
        this.m_sessionReadyTicks = 0;
        this.m_retroSyncDoneForSession = false;
    }

    public final func SetDialogWidgetController(ctrl: wref<dialogWidgetGameController>) -> Void {
        this.m_dialogWidgetCtrl = ctrl;
    }

    public final func ScheduleTick(delaySeconds: Float) -> Void {
        if this.m_tickScheduled {
            return;
        }
        let cb: ref<ChispaTickCallback> = new ChispaTickCallback();
        cb.system = this;
        this.m_tickScheduled = true;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, delaySeconds, false);
    }

    // --- Utilidades Espaciales y Localización ---

    public final func GetLoc(key: CName, fallback: String) -> String {
        if !IsNameValid(key) || Equals(key, n"None") {
            return fallback;
        }
        let txt: String = GetLocalizedTextByKey(key);
        if NotEquals(txt, "") {
            return txt;
        }
        return fallback;
    }

    public final func ComputeDistanceSq(a: Vector4, b: Vector4) -> Float {
        let dx: Float = a.X - b.X;
        let dy: Float = a.Y - b.Y;
        let dz: Float = a.Z - b.Z;
        return dx * dx + dy * dy + dz * dz;
    }

    public final func FindGroundZ(pos: Vector4) -> Float {
        let startPos: Vector4 = new Vector4(pos.X, pos.Y, pos.Z + 1.25, 1.00);
        let endPos: Vector4 = new Vector4(pos.X, pos.Y, pos.Z - 2.00, 1.00);
        let hitResult: TraceResult;
        if GameInstance.GetSpatialQueriesSystem(this.GetGameInstance()).SyncRaycastByCollisionGroup(startPos, endPos, n"Static", hitResult, true, false) && TraceResult.IsValid(hitResult) {
            return hitResult.position.Z;
        }
        return pos.Z;
    }

    public final func GiveItemDelayed(itemTdbId: TweakDBID, amount: Int32, delaySeconds: Float) -> Void {
        if amount <= 0 {
            return;
        }
        let cb: ref<ChispaDelayedItemCallback> = new ChispaDelayedItemCallback();
        cb.system = this;
        cb.itemTdbId = itemTdbId;
        cb.amount = amount;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, MaxF(0.05, delaySeconds), false);
    }

    public final func ExecuteDelayedItemGrant(itemTdbId: TweakDBID, amount: Int32) -> Void {
        if amount <= 0 {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        if IsDefined(player) && IsDefined(ts) {
            ts.GiveItem(player, ItemID.FromTDBID(itemTdbId), amount);
        }
    }

    public final func EnsureSmartBridgeActive(player: ref<PlayerPuppet>) -> Void {
        if !IsDefined(player) || IsDefined(this.m_smartBridgeMod) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if !IsDefined(qs) || !IsDefined(ss) {
            return;
        }
        let needsBridge: Bool = qs.GetFact(n"chispa_ep03_stage") >= 2
            || this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Shingen_Chispa")
            || qs.GetFact(n"chispa_ep05_stage") >= 2
            || qs.GetFact(n"chispa_permanent_partner") > 0;
        if !needsBridge {
            return;
        }
        let hasSmartLink: Float = ss.GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.HasSmartLink);
        if hasSmartLink < 1.00 {
            let mod: ref<gameStatModifierData> = RPGManager.CreateStatModifier(gamedataStatType.HasSmartLink, gameStatModifierType.Additive, 1.00);
            ss.AddModifier(Cast<StatsObjectID>(player.GetEntityID()), mod);
            this.m_smartBridgeMod = mod;
        }
    }

    public final func ClearSmartBridge() -> Void {
        if !IsDefined(this.m_smartBridgeMod) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if IsDefined(player) && IsDefined(ss) {
            ss.RemoveModifier(Cast<StatsObjectID>(player.GetEntityID()), this.m_smartBridgeMod);
        }
        this.m_smartBridgeMod = null;
    }

    public final func EnsureRicochetBridgeActive(player: ref<PlayerPuppet>) -> Void {
        if !IsDefined(player) || IsDefined(this.m_ricochetBridgeMod) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if !IsDefined(qs) || !IsDefined(ss) {
            return;
        }
        let needsBridge: Bool = qs.GetFact(n"chispa_ep04_stage") >= 2
            || qs.GetFact(n"chispa_ep05_stage") >= 2
            || qs.GetFact(n"chispa_permanent_partner") > 0
            || this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Masamune_Chispa")
            || this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Overture_Chispa");
        if !needsBridge {
            return;
        }
        let canSeeRicochet: Float = ss.GetStatValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatType.CanSeeRicochetVisuals);
        if canSeeRicochet < 1.00 {
            let mod: ref<gameStatModifierData> = RPGManager.CreateStatModifier(gamedataStatType.CanSeeRicochetVisuals, gameStatModifierType.Additive, 1.00);
            ss.AddModifier(Cast<StatsObjectID>(player.GetEntityID()), mod);
            this.m_ricochetBridgeMod = mod;
        }
    }

    public final func ClearRicochetBridge() -> Void {
        if !IsDefined(this.m_ricochetBridgeMod) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if IsDefined(player) && IsDefined(ss) {
            ss.RemoveModifier(Cast<StatsObjectID>(player.GetEntityID()), this.m_ricochetBridgeMod);
        }
        this.m_ricochetBridgeMod = null;
    }

    // --- Coprocesador RAM, Tier Adaptativo de Hackeos Rápidos, XP y Estado de Viaje Rápido ---

    public final func EnsureCoprocessorRamBridgeActive(player: ref<PlayerPuppet>) -> Void {
        if !IsDefined(player) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if !IsDefined(qs) || !IsDefined(ss) {
            return;
        }
        let unlocked: Bool = qs.GetFact(n"chispa_ep00_stage") >= 4
            || qs.GetFact(n"chispa_ep00_done") > 0
            || qs.GetFact(n"chispa_ep01_stage") >= 1
            || qs.GetFact(n"chispa_ep01_done") > 0
            || qs.GetFact(n"chispa_ep02_stage") >= 1
            || qs.GetFact(n"chispa_ep02_done") > 0
            || qs.GetFact(n"chispa_ep03_stage") >= 1
            || qs.GetFact(n"chispa_ep03_done") > 0
            || qs.GetFact(n"chispa_ep04_stage") >= 1
            || qs.GetFact(n"chispa_ep04_done") > 0
            || qs.GetFact(n"chispa_ep05_stage") >= 1
            || qs.GetFact(n"chispa_ep05_done") > 0;
        if !unlocked {
            this.ClearCoprocessorRamBridge();
            return;
        }
        let desiredRam: Float = 8.00;
        if qs.GetFact(n"chispa_ep01_stage") >= 4 || qs.GetFact(n"chispa_ep01_done") > 0 { desiredRam += 3.00; }
        if qs.GetFact(n"chispa_ep02_stage") >= 4 || qs.GetFact(n"chispa_ep02_done") > 0 { desiredRam += 3.00; }
        if qs.GetFact(n"chispa_ep03_stage") >= 4 || qs.GetFact(n"chispa_ep03_done") > 0 { desiredRam += 3.00; }
        if qs.GetFact(n"chispa_ep04_stage") >= 4 || qs.GetFact(n"chispa_ep04_done") > 0 { desiredRam += 3.00; }
        if qs.GetFact(n"chispa_ep05_stage") >= 4 || qs.GetFact(n"chispa_ep05_done") > 0 { desiredRam += 3.00; }

        if IsDefined(this.m_coprocessorRamMod) {
            if AbsF(this.m_coprocessorRamBonus - desiredRam) < 0.01 {
                return;
            }
            this.ClearCoprocessorRamBridge();
        }
        let mod: ref<gameStatModifierData> = RPGManager.CreateStatModifier(gamedataStatType.Memory, gameStatModifierType.Additive, desiredRam);
        ss.AddModifier(Cast<StatsObjectID>(player.GetEntityID()), mod);
        this.m_coprocessorRamMod = mod;
        this.m_coprocessorRamBonus = desiredRam;
    }

    public final func ClearCoprocessorRamBridge() -> Void {
        if !IsDefined(this.m_coprocessorRamMod) {
            this.m_coprocessorRamBonus = 0.00;
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if IsDefined(player) && IsDefined(ss) {
            ss.RemoveModifier(Cast<StatsObjectID>(player.GetEntityID()), this.m_coprocessorRamMod);
        }
        this.m_coprocessorRamMod = null;
        this.m_coprocessorRamBonus = 0.00;
    }

    public final func PlayerOwnsItemOrDeckPart(player: ref<PlayerPuppet>, itemId: TweakDBID) -> Bool {
        if !IsDefined(player) || !TDBID.IsValid(itemId) {
            return false;
        }
        let game: GameInstance = this.GetGameInstance();
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        if IsDefined(ts) {
            let qid: ItemID = ItemID.CreateQuery(itemId);
            if ts.HasItem(player, qid) || ts.GetItemQuantity(player, qid) > 0 {
                return true;
            }
        }
        let eqData: ref<EquipmentSystemPlayerData> = EquipmentSystem.GetData(player);
        if IsDefined(eqData) {
            let handsId: ItemID = eqData.GetActiveItem(gamedataEquipmentArea.HandsCW);
            if ItemID.IsValid(handsId) && ItemID.GetTDBID(handsId) == itemId {
                return true;
            }
            if EquipmentSystem.IsCyberdeckEquipped(player) {
                let deckId: ItemID = eqData.GetActiveItem(gamedataEquipmentArea.SystemReplacementCW);
                let parts: array<SPartSlots> = ItemModificationSystem.GetAllSlots(player, deckId);
                let i: Int32 = 0;
                while i < ArraySize(parts) {
                    if Equals(parts[i].status, ESlotState.Taken) && ItemID.GetTDBID(parts[i].installedPart) == itemId {
                        return true;
                    }
                    i += 1;
                }
            }
        }
        return false;
    }

    public final func GetMaxEquippableProgramTier(player: ref<PlayerPuppet>) -> Int32 {
        if !IsDefined(player) || !EquipmentSystem.IsCyberdeckEquipped(player) {
            return 1;
        }
        let eqData: ref<EquipmentSystemPlayerData> = EquipmentSystem.GetData(player);
        if !IsDefined(eqData) {
            return 1;
        }
        let deckId: ItemID = eqData.GetActiveItem(gamedataEquipmentArea.SystemReplacementCW);
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(this.GetGameInstance());
        if !IsDefined(ts) {
            return 1;
        }
        let deckData: ref<gameItemData> = ts.GetItemData(player, deckId);
        if !IsDefined(deckData) {
            return 1;
        }
        let q: gamedataQuality = RPGManager.GetItemDataQuality(deckData);
        switch q {
            case gamedataQuality.Common:
            case gamedataQuality.CommonPlus:
                return 1;
            case gamedataQuality.Uncommon:
            case gamedataQuality.UncommonPlus:
                return 2;
            case gamedataQuality.Rare:
            case gamedataQuality.RarePlus:
                return 3;
            case gamedataQuality.Epic:
            case gamedataQuality.EpicPlus:
            case gamedataQuality.Legendary:
            case gamedataQuality.LegendaryPlus:
            case gamedataQuality.LegendaryPlusPlus:
                return 4;
        }
        return 1;
    }

    private final func ResolveProgramExactTier(programKey: CName, eff: Int32) -> TweakDBID {
        let clamped: Int32 = eff;
        if clamped < 1 {
            clamped = 1;
        } else if clamped > 4 {
            clamped = 4;
        }
        if Equals(programKey, n"Ping") {
            if clamped >= 4 { return t"Items.PingLvl3Program"; }
            if clamped == 3 { return t"Items.PingLvl2Program"; }
            return t"Items.PingProgram";
        }
        if Equals(programKey, n"EMPOverload") {
            if clamped == 1 { return t"Items.EMPOverloadProgram"; }
            if clamped == 2 { return t"Items.EMPOverloadLvl1Program"; }
            if clamped == 3 { return t"Items.EMPOverloadLvl2Program"; }
            return t"Items.EMPOverloadLvl3Program";
        }
        if Equals(programKey, n"Overheat") {
            if clamped == 1 { return t"Items.OverheatProgram"; }
            if clamped == 2 { return t"Items.OverheatLvl1Program"; }
            if clamped == 3 { return t"Items.OverheatLvl2Program"; }
            return t"Items.OverheatLvl3Program";
        }
        if Equals(programKey, n"WeaponMalfunction") {
            if clamped == 1 { return t"Items.Chispa_WeaponMalfunction_T1"; }
            if clamped == 2 { return t"Items.WeaponMalfunctionProgram"; }
            if clamped == 3 { return t"Items.WeaponMalfunctionLvl2Program"; }
            return t"Items.WeaponMalfunctionLvl3Program";
        }
        if Equals(programKey, n"Blind") {
            if clamped == 1 { return t"Items.BlindProgram"; }
            if clamped == 2 { return t"Items.BlindLvl1Program"; }
            if clamped == 3 { return t"Items.BlindLvl2Program"; }
            return t"Items.BlindLvl3Program";
        }
        if Equals(programKey, n"MemoryWipe") {
            if clamped == 1 { return t"Items.Chispa_MemoryWipe_T1"; }
            if clamped == 2 { return t"Items.Chispa_MemoryWipe_T2"; }
            if clamped == 3 { return t"Items.MemoryWipeLvl2Program"; }
            return t"Items.MemoryWipeLvl3Program";
        }
        if Equals(programKey, n"Contagion") {
            if clamped == 1 { return t"Items.Chispa_Contagion_T1"; }
            if clamped == 2 { return t"Items.ContagionProgram"; }
            if clamped == 3 { return t"Items.ContagionLvl2Program"; }
            return t"Items.ContagionLvl3Program";
        }
        if Equals(programKey, n"DisableCyberware") {
            if clamped == 1 { return t"Items.Chispa_DisableCyberware_T1"; }
            if clamped == 2 { return t"Items.DisableCyberwareProgram"; }
            if clamped == 3 { return t"Items.DisableCyberwareLvl2Program"; }
            return t"Items.DisableCyberwareLvl3Program";
        }
        if Equals(programKey, n"SystemCollapse") {
            if clamped == 1 { return t"Items.Chispa_SystemCollapse_T1"; }
            if clamped == 2 { return t"Items.Chispa_SystemCollapse_T2"; }
            if clamped == 3 { return t"Items.Chispa_SystemCollapse_T3"; }
            return t"Items.SystemCollapseLvl3Program";
        }
        if Equals(programKey, n"BrainMelt") {
            if clamped == 1 { return t"Items.Chispa_BrainMelt_T1"; }
            if clamped == 2 { return t"Items.Chispa_BrainMelt_T2"; }
            if clamped == 3 { return t"Items.BrainMeltLvl2Program"; }
            return t"Items.BrainMeltLvl3Program";
        }
        return TDBID.None();
    }

    public final func ResolveProgramForPlayer(player: ref<PlayerPuppet>, programKey: CName, targetTier: Int32) -> TweakDBID {
        let maxTier: Int32 = this.GetMaxEquippableProgramTier(player);
        let eff: Int32 = targetTier;
        if eff < 1 {
            eff = 1;
        } else if eff > 4 {
            eff = 4;
        }
        if maxTier < eff {
            eff = maxTier;
        }
        return this.ResolveProgramExactTier(programKey, eff);
    }

    public final func PlayerOwnsProgramAtOrAboveTier(player: ref<PlayerPuppet>, programKey: CName, minTier: Int32) -> Bool {
        let startTier: Int32 = minTier;
        if startTier < 1 {
            startTier = 1;
        }
        let t: Int32 = startTier;
        while t <= 4 {
            let candidateId: TweakDBID = this.ResolveProgramExactTier(programKey, t);
            if TDBID.IsValid(candidateId) && this.PlayerOwnsItemOrDeckPart(player, candidateId) {
                return true;
            }
            t += 1;
        }
        return false;
    }

    public final func GrantProgramForPlayer(player: ref<PlayerPuppet>, programKey: CName, targetTier: Int32) -> Bool {
        if !IsDefined(player) {
            return false;
        }
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(this.GetGameInstance());
        if !IsDefined(ts) {
            return false;
        }
        let maxTier: Int32 = this.GetMaxEquippableProgramTier(player);
        let eff: Int32 = targetTier;
        if eff < 1 {
            eff = 1;
        } else if eff > 4 {
            eff = 4;
        }
        if maxTier < eff {
            eff = maxTier;
        }
        if this.PlayerOwnsProgramAtOrAboveTier(player, programKey, eff) {
            return false;
        }
        let progId: TweakDBID = this.ResolveProgramExactTier(programKey, eff);
        if !TDBID.IsValid(progId) {
            return false;
        }
        ts.GiveItem(player, ItemID.FromTDBID(progId), 1);
        return true;
    }

    public final func AwardMilestoneProgram(player: ref<PlayerPuppet>, factKey: CName, programKey: CName, targetTier: Int32) -> Bool {
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(qs) || !IsDefined(player) {
            return false;
        }
        if qs.GetFact(factKey) > 0 {
            return false;
        }
        qs.SetFact(factKey, 1);
        return this.GrantProgramForPlayer(player, programKey, targetTier);
    }

    private final func QueuePlayerXPEvent(player: ref<PlayerPuppet>, amount: Int32, xpType: gamedataProficiencyType) -> Void {
        if !IsDefined(player) || amount <= 0 {
            return;
        }
        let evt: ref<ExperiencePointsEvent> = new ExperiencePointsEvent();
        evt.amount = amount;
        evt.type = xpType;
        evt.isDebug = false;
        player.QueueEvent(evt);
    }

    public final func AwardMilestoneXP(factKey: CName, levelXp: Int32, streetCredXp: Int32, skillType: gamedataProficiencyType, skillXp: Int32) -> Bool {
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(qs) || !IsDefined(player) {
            return false;
        }
        if qs.GetFact(factKey) > 0 {
            return false;
        }
        qs.SetFact(factKey, 1);
        this.QueuePlayerXPEvent(player, levelXp, gamedataProficiencyType.Level);
        this.QueuePlayerXPEvent(player, streetCredXp, gamedataProficiencyType.StreetCred);
        if skillXp > 0 && NotEquals(skillType, gamedataProficiencyType.Level) && NotEquals(skillType, gamedataProficiencyType.StreetCred) {
            this.QueuePlayerXPEvent(player, skillXp, skillType);
        }
        return true;
    }

    public final func SyncRetroactiveProgression(player: ref<PlayerPuppet>) -> Void {
        if !IsDefined(player) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if !IsDefined(qs) {
            return;
        }
        this.EnsureCoprocessorRamBridgeActive(player);

        if qs.GetFact(n"chispa_ep00_stage") >= 4 || qs.GetFact(n"chispa_ep00_done") > 0 {
            this.AwardMilestoneXP(n"chispa_ep00_xp_sector", 350, 400, gamedataProficiencyType.TechnicalAbilitySkill, 150);
        }
        if qs.GetFact(n"chispa_ep00_done") > 0 {
            this.AwardMilestoneXP(n"chispa_ep00_xp_done", 450, 450, gamedataProficiencyType.Level, 0);
        }

        if qs.GetFact(n"chispa_ep01_stage") >= 2 || qs.GetFact(n"chispa_ep01_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep01_ping", n"Ping", 1);
        }
        if qs.GetFact(n"chispa_ep01_stage") >= 4 || qs.GetFact(n"chispa_ep01_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep01_emp", n"EMPOverload", 3);
            this.AwardMilestoneProgram(player, n"chispa_qh_ep01_overheat", n"Overheat", 3);
            this.AwardMilestoneXP(n"chispa_ep01_xp_sector", 500, 550, gamedataProficiencyType.IntelligenceSkill, 250);
        }
        if qs.GetFact(n"chispa_ep01_done") > 0 {
            this.AwardMilestoneXP(n"chispa_ep01_xp_done", 600, 600, gamedataProficiencyType.Level, 0);
        }

        if qs.GetFact(n"chispa_ep02_stage") >= 2 || qs.GetFact(n"chispa_ep02_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep02_wep", n"WeaponMalfunction", 3);
        }
        if qs.GetFact(n"chispa_ep02_stage") >= 4 || qs.GetFact(n"chispa_ep02_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep02_blind", n"Blind", 3);
            this.AwardMilestoneXP(n"chispa_ep02_xp_sector", 600, 650, gamedataProficiencyType.TechnicalAbilitySkill, 300);
        }
        if qs.GetFact(n"chispa_ep02_done") > 0 {
            this.AwardMilestoneXP(n"chispa_ep02_xp_done", 700, 700, gamedataProficiencyType.Level, 0);
        }

        if qs.GetFact(n"chispa_ep03_stage") >= 2 || qs.GetFact(n"chispa_ep03_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep03_mem", n"MemoryWipe", 3);
        }
        if qs.GetFact(n"chispa_ep03_stage") >= 4 || qs.GetFact(n"chispa_ep03_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep03_contagion", n"Contagion", 3);
            this.AwardMilestoneXP(n"chispa_ep03_xp_sector", 700, 800, gamedataProficiencyType.IntelligenceSkill, 350);
        }
        if qs.GetFact(n"chispa_ep03_done") > 0 {
            this.AwardMilestoneXP(n"chispa_ep03_xp_done", 850, 850, gamedataProficiencyType.Level, 0);
        }

        if qs.GetFact(n"chispa_ep04_stage") >= 4 || qs.GetFact(n"chispa_ep04_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep04_cyber", n"DisableCyberware", 3);
            this.AwardMilestoneXP(n"chispa_ep04_xp_sector", 850, 1000, gamedataProficiencyType.ReflexesSkill, 400);
        }
        if qs.GetFact(n"chispa_ep04_done") > 0 {
            this.AwardMilestoneXP(n"chispa_ep04_xp_done", 1000, 1050, gamedataProficiencyType.Level, 0);
        }

        if qs.GetFact(n"chispa_ep05_stage") >= 2 || qs.GetFact(n"chispa_ep05_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep05_emp", n"EMPOverload", 4);
        }
        if qs.GetFact(n"chispa_ep05_stage") >= 4 || qs.GetFact(n"chispa_ep05_done") > 0 {
            this.AwardMilestoneProgram(player, n"chispa_qh_ep05_collapse", n"SystemCollapse", 4);
            this.AwardMilestoneXP(n"chispa_ep05_xp_sector", 1000, 1250, gamedataProficiencyType.IntelligenceSkill, 500);
        }
        if qs.GetFact(n"chispa_ep05_done") > 0 {
            let ending: Int32 = qs.GetFact(n"chispa_ep05_ending");
            if ending == 1 {
                this.AwardMilestoneProgram(player, n"chispa_qh_ep05_ending", n"BrainMelt", 4);
            } else if ending == 2 {
                this.AwardMilestoneProgram(player, n"chispa_qh_ep05_ending", n"DisableCyberware", 4);
            }
            this.AwardMilestoneXP(n"chispa_ep05_xp_done", 1400, 1500, gamedataProficiencyType.Level, 0);
        }
    }

    public final func NotifyFastTravelLoadingChanged(active: Bool) -> Void {
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
        if active {
            this.m_fastTravelLoading = true;
            this.m_fastTravelStartedAt = now;
        } else {
            this.m_fastTravelLoading = false;
        }
    }

    protected cb func OnFastTravelFlagStarted(started: Bool) -> Bool {
        if started {
            this.NotifyFastTravelLoadingChanged(true);
        }
        return true;
    }

    protected cb func OnFastTravelLoadingStarted(started: Bool) -> Bool {
        if started {
            this.NotifyFastTravelLoadingChanged(true);
        }
        return true;
    }

    protected cb func OnFastTravelLoadingFinished(finished: Bool) -> Bool {
        if finished {
            this.NotifyFastTravelLoadingChanged(false);
        }
        return true;
    }

    public final func IsFastTravelOrLoadingActive() -> Bool {
        let game: GameInstance = this.GetGameInstance();
        let sysHandler: wref<inkISystemRequestsHandler> = GameInstance.GetSystemRequestsHandler();
        if IsDefined(sysHandler) && (sysHandler.IsPreGame() || sysHandler.IsGamePaused()) {
            return true;
        }
        if this.m_fastTravelLoading {
            return true;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) || this.m_sessionReadyTicks < 2 {
            return true;
        }
        return false;
    }

    // --- Estado UI, Prólogo (Patrón #10) y Coexistencia Telefónica ---

    public final func OnPlayerSpawnGraceEnded() -> Void {
        this.m_spawnGraceEnded = true;
    }

    public final func IsDialogActive() -> Bool {
        return this.m_dialogActive;
    }

    public final func IsInteractionActive() -> Bool {
        return this.m_interactionShown;
    }

    public final func IsVideocallModeEnabled() -> Bool {
        return GameInstance.GetQuestsSystem(this.GetGameInstance()).GetFact(n"chispa_videocall_disabled") == 0;
    }

    public final func SetVideocallModeEnabled(enabled: Bool) -> Void {
        GameInstance.GetQuestsSystem(this.GetGameInstance()).SetFact(n"chispa_videocall_disabled", enabled ? 0 : 1);
        if !enabled && this.m_directHoloFeedOpen {
            this.CloseDirectHoloFeed();
        } else if enabled && this.IsAnyEpisodeInFinalTalkStage() {
            this.OpenDirectHoloFeed();
        }
    }

    public final func IsChispaVideocallActive() -> Bool {
        if !this.m_activeCallIsVideo || NotEquals(this.m_activeCallContact, n"chispa_ai") {
            return false;
        }
        let comBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_ComDevice);
        if IsDefined(comBB) {
            let infoVar: Variant = comBB.GetVariant(GetAllBlackboardDefs().UI_ComDevice.PhoneCallInformation);
            if IsDefined(infoVar) {
                let info: PhoneCallInformation = FromVariant<PhoneCallInformation>(infoVar);
                if IsNameValid(info.contactName) && NotEquals(info.contactName, n"None") && NotEquals(info.contactName, n"chispa_ai") {
                    return false;
                }
            }
        }
        return true;
    }

    public final func IsAnyEpisodeInFinalTalkStage() -> Bool {
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if !IsDefined(qs) {
            return false;
        }
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            return qs.GetFact(n"chispa_ep00_stage") == 4;
        }
        if qs.GetFact(n"chispa_ep01_done") == 0 {
            return qs.GetFact(n"chispa_ep01_stage") == 4;
        }
        if qs.GetFact(n"chispa_ep02_done") == 0 {
            return qs.GetFact(n"chispa_ep02_stage") == 4;
        }
        if qs.GetFact(n"chispa_ep03_done") == 0 {
            return qs.GetFact(n"chispa_ep03_stage") == 4;
        }
        if qs.GetFact(n"chispa_ep04_done") == 0 {
            return qs.GetFact(n"chispa_ep04_stage") == 4;
        }
        if qs.GetFact(n"chispa_ep05_done") == 0 {
            return qs.GetFact(n"chispa_ep05_stage") == 4;
        }
        return false;
    }

    public final func IsInSystemOrPauseMenu() -> Bool {
        let sysHandler: wref<inkISystemRequestsHandler> = GameInstance.GetSystemRequestsHandler();
        if IsDefined(sysHandler) && (sysHandler.IsPreGame() || sysHandler.IsGamePaused()) {
            return true;
        }
        let uiSystemBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_System);
        if IsDefined(uiSystemBB) && uiSystemBB.GetBool(GetAllBlackboardDefs().UI_System.IsInMenu) {
            return true;
        }
        return false;
    }

    public final func IsPhoneOverlayOpen() -> Bool {
        let comBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_ComDevice);
        if !IsDefined(comBB) {
            return false;
        }
        let comDef: ref<UI_ComDeviceDef> = GetAllBlackboardDefs().UI_ComDevice;
        return comBB.GetBool(comDef.isDisplayingMessage)
            || comBB.GetBool(comDef.ContactsActive)
            || comBB.GetBool(comDef.SmsMessengerActive);
    }

    public final func IsExternalPhoneCallBusy() -> Bool {
        let comBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UI_ComDevice);
        if !IsDefined(comBB) {
            return false;
        }
        let infoVar: Variant = comBB.GetVariant(GetAllBlackboardDefs().UI_ComDevice.PhoneCallInformation);
        if !IsDefined(infoVar) {
            return false;
        }
        let info: PhoneCallInformation = FromVariant<PhoneCallInformation>(infoVar);
        if NotEquals(info.callPhase, questPhoneCallPhase.IncomingCall) && NotEquals(info.callPhase, questPhoneCallPhase.StartCall) {
            return false;
        }
        return NotEquals(info.contactName, n"chispa_ai");
    }

    public final func IsControllingDevice() -> Bool {
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return false;
        }
        let tcs: ref<TakeOverControlSystem> = player.GetTakeOverControlSystem();
        return IsDefined(tcs) && tcs.IsDeviceControlled();
    }

    public final func IsUiBlockingWorldInput() -> Bool {
        return this.IsInSystemOrPauseMenu() || this.IsPhoneOverlayOpen() || this.IsControllingDevice();
    }

    public final func IsNativeInteractionHubBlocking() -> Bool {
        let game: GameInstance = this.GetGameInstance();
        let uiBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIInteractions);
        if !IsDefined(uiBB) {
            return false;
        }
        let hubDef: ref<UIInteractionsDef> = GetAllBlackboardDefs().UIInteractions;
        let inter: InteractionChoiceHubData = FromVariant<InteractionChoiceHubData>(uiBB.GetVariant(hubDef.InteractionChoiceHub));
        if inter.active && !this.IsOurInteractionHubId(inter.id) {
            return true;
        }
        return false;
    }

    public final func IsGameplayReady(player: ref<PlayerPuppet>) -> Bool {
        return IsDefined(player)
            && !player.IsReplacer()
            && ChispaSessionService.IsSessionReady()
            && !this.IsInSystemOrPauseMenu();
    }

    public final func IsInFullGameplayTier(player: ref<PlayerPuppet>) -> Bool {
        if !IsDefined(player) || !this.m_spawnGraceEnded {
            return false;
        }
        let psmBB: ref<IBlackboard> = player.GetPlayerStateMachineBlackboard();
        return IsDefined(psmBB)
            && psmBB.GetInt(GetAllBlackboardDefs().PlayerStateMachine.SceneTier) == EnumInt(GameplayTier.Tier1_FullGameplay);
    }

    public final func HasReachedNightCityAct1(player: ref<PlayerPuppet>) -> Bool {
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        if !IsDefined(jm) {
            return false;
        }
        let qDex: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/prologue/q001_02_dex", "gameJournalQuest");
        if IsDefined(qDex) {
            let stDex: gameJournalEntryState = jm.GetEntryState(qDex);
            if Equals(stDex, gameJournalEntryState.Active) || Equals(stDex, gameJournalEntryState.Succeeded) {
                return true;
            }
        }
        let ripPhase: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/prologue/q001_01_victor/ripperdoc", "gameJournalQuestPhase");
        if IsDefined(ripPhase) && Equals(jm.GetEntryState(ripPhase), gameJournalEntryState.Active) && IsDefined(player) {
            let chairPos: Vector4 = new Vector4(-1546.58, 1234.84, 12.21, 1.00);
            if this.ComputeDistanceSq(player.GetWorldPosition(), chairPos) <= 16.00 {
                return false;
            }
        }
        let qVic: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/prologue/q001_01_victor", "gameJournalQuest");
        if IsDefined(qVic) {
            let stVic: gameJournalEntryState = jm.GetEntryState(qVic);
            if Equals(stVic, gameJournalEntryState.Active) || Equals(stVic, gameJournalEntryState.Succeeded) {
                return true;
            }
        }
        let qAct1: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/act_01/q101_resurrection", "gameJournalQuest");
        if IsDefined(qAct1) {
            let stAct1: gameJournalEntryState = jm.GetEntryState(qAct1);
            if Equals(stAct1, gameJournalEntryState.Active) || Equals(stAct1, gameJournalEntryState.Succeeded) {
                return true;
            }
        }
        return false;
    }

    public final func HasLiftedWatsonLockdown(player: ref<PlayerPuppet>) -> Bool {
        if !this.HasReachedNightCityAct1(player) {
            return false;
        }
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        if !IsDefined(qs) || qs.GetFact(n"watson_prolog_lock") > 0 {
            return false;
        }
        if qs.GetFact(n"dbg_unlock_fast_travel") > 0 {
            return true;
        }
        if !IsDefined(jm) {
            return false;
        }
        let q101: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/act_01/q101_resurrection", "gameJournalQuest");
        if IsDefined(q101) && Equals(jm.GetEntryState(q101), gameJournalEntryState.Succeeded) {
            return true;
        }
        let takemuraPhase: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/act_01/q101_resurrection/takemura", "gameJournalQuestPhase");
        if IsDefined(takemuraPhase) {
            let stTakemura: gameJournalEntryState = jm.GetEntryState(takemuraPhase);
            if Equals(stTakemura, gameJournalEntryState.Active) || Equals(stTakemura, gameJournalEntryState.Succeeded) {
                return true;
            }
        }
        let q103: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/act_01/q103_warhead", "gameJournalQuest");
        if IsDefined(q103) {
            let st103: gameJournalEntryState = jm.GetEntryState(q103);
            if Equals(st103, gameJournalEntryState.Active) || Equals(st103, gameJournalEntryState.Succeeded) {
                return true;
            }
        }
        let q105: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/act_01/q105_dollhouse", "gameJournalQuest");
        if IsDefined(q105) {
            let st105: gameJournalEntryState = jm.GetEntryState(q105);
            if Equals(st105, gameJournalEntryState.Active) || Equals(st105, gameJournalEntryState.Succeeded) {
                return true;
            }
        }
        return false;
    }

    // --- Banners HUD y Sincronización Audioware (Patrón #4) ---

    public final func ShowRelicBanner(key: CName, fallback: String) -> Void {
        let screenMsg: SimpleScreenMessage;
        screenMsg.isShown = true;
        screenMsg.duration = 6.00;
        screenMsg.message = this.GetLoc(key, fallback);
        screenMsg.isInstant = false;
        screenMsg.type = SimpleMessageType.Relic;
        GameInstance.GetBlackboardSystem(this.GetGameInstance())
            .Get(GetAllBlackboardDefs().UI_Notifications)
            .SetVariant(GetAllBlackboardDefs().UI_Notifications.WarningMessage, ToVariant(screenMsg), true);
    }

    public final func SyncAudiowareEngineState(fullSync: Bool) -> Void {
        let game: GameInstance = this.GetGameInstance();
        let locSys: ref<LocalizationSystem> = LocalizationSystem.GetInstance(game);
        if fullSync && IsDefined(locSys) {
            locSys.QueueRequest(UpdateLocaleRequest.Create(n"VoiceOver"));
            locSys.QueueRequest(UpdateLocaleRequest.Create(n"Subtitles"));
            locSys.QueueRequest(UpdateGenderRequest.Create());
        }
        ChispaAudioBridge.SyncBackendState(game, fullSync);
    }

    public final func PlaySfx(sfxEvent: CName) -> Void {
        let game: GameInstance = this.GetGameInstance();
        this.SyncAudiowareEngineState(false);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        ChispaAudioBridge.PlaySfx(game, sfxEvent, player);
    }

    // --- Motor de Locuciones, Salto Seguro en Escenas Presenciales y LipSync (Patrones #3, #5) ---

    private final func ClearCurrentSpeechTracking() -> Void {
        this.m_currentPlayingEvent = n"None";
        this.m_currentPlayingEntity = new EntityID();
        this.m_currentPlayingSpeaker = n"None";
        this.m_currentPlayingBackend = 0;
        this.m_currentPlayingVariant = n"None";
    }

    private final func PreferEnglishBuiltInSubtitleOnly() -> Bool {
        return true;
    }

    public final func TrimSubtitleEdges(raw: String) -> String {
        let res: String = raw;
        let len: Int32 = UTF8StrLen(res);
        while len > 0 && Equals(UTF8StrLeft(res, 1), " ") {
            res = UTF8StrRight(res, len - 1);
            len = UTF8StrLen(res);
        }
        while len > 0 && Equals(UTF8StrRight(res, 1), " ") {
            res = UTF8StrLeft(res, len - 1);
            len = UTF8StrLen(res);
        }
        return res;
    }

    public final func PaginateSubtitleText(fullText: String, maxCharsPerPage: Int32) -> array<String> {
        let pages: array<String>;
        let rem: String = this.TrimSubtitleEdges(fullText);
        if Equals(rem, "") {
            return pages;
        }
        let cap: Int32 = Max(60, maxCharsPerPage);
        while UTF8StrLen(rem) > cap {
            let remLen: Int32 = UTF8StrLen(rem);
            let idealSplit: Int32;
            if remLen <= cap * 2 {
                idealSplit = remLen / 2;
            } else if remLen <= cap * 3 {
                idealSplit = remLen / 3;
            } else {
                idealSplit = cap - 15;
            }

            let searchStart: Int32 = Max(40, idealSplit - 48);
            let searchEnd: Int32 = Min(cap, remLen - 28);
            if searchEnd < searchStart {
                searchStart = Max(20, cap - 60);
                searchEnd = Min(cap, remLen - 10);
            }

            let bestSplit: Int32 = -1;
            let bestDist: Int32 = 9999;

            // Prioridad 1: fin de frase (. ! ? …) seguido de espacio
            let i: Int32 = searchStart;
            while i <= searchEnd && i < remLen {
                let ch: String = UTF8StrMid(rem, i, 1);
                let nxt: String = (i + 1) < remLen ? UTF8StrMid(rem, i + 1, 1) : "";
                if (Equals(ch, ".") || Equals(ch, "!") || Equals(ch, "?") || Equals(ch, "…")) && Equals(nxt, " ") {
                    let cand: Int32 = i + 1;
                    if cand <= cap {
                        let dist: Int32 = Abs(cand - idealSplit);
                        if dist < bestDist {
                            bestDist = dist;
                            bestSplit = cand;
                        }
                    }
                }
                i += 1;
            }

            // Prioridad 2: pausa interna (, ; : —)
            if bestSplit < 0 {
                i = searchStart;
                while i <= searchEnd && i < remLen {
                    let ch: String = UTF8StrMid(rem, i, 1);
                    let nxt: String = (i + 1) < remLen ? UTF8StrMid(rem, i + 1, 1) : "";
                    let cand: Int32 = -1;
                    if (Equals(ch, ",") || Equals(ch, ";") || Equals(ch, ":") || Equals(ch, "—")) && Equals(nxt, " ") {
                        cand = i + 1;
                    } else if Equals(ch, " ") && Equals(nxt, "—") && i > searchStart {
                        cand = i;
                    }
                    if cand > 0 && cand <= cap {
                        let dist: Int32 = Abs(cand - idealSplit);
                        if dist < bestDist {
                            bestDist = dist;
                            bestSplit = cand;
                        }
                    }
                    i += 1;
                }
            }

            // Prioridad 3: frontera de palabra
            if bestSplit < 0 {
                let wStart: Int32 = Max(25, idealSplit - 56);
                let wEnd: Int32 = Min(cap, remLen - 10);
                i = wStart;
                while i <= wEnd && i < remLen {
                    if Equals(UTF8StrMid(rem, i, 1), " ") {
                        let dist: Int32 = Abs(i - idealSplit);
                        if dist < bestDist {
                            bestDist = dist;
                            bestSplit = i;
                        }
                    }
                    i += 1;
                }
            }

            if bestSplit <= 0 || bestSplit >= remLen {
                bestSplit = cap;
            }

            let head: String = this.TrimSubtitleEdges(UTF8StrLeft(rem, bestSplit));
            let tail: String = this.TrimSubtitleEdges(UTF8StrRight(rem, remLen - bestSplit));
            if NotEquals(head, "") {
                ArrayPush(pages, head);
            }
            if Equals(tail, "") {
                rem = "";
                break;
            }
            rem = tail;
        }
        if NotEquals(rem, "") {
            ArrayPush(pages, rem);
        }
        return pages;
    }

    private final func ResolveBuiltInSubtitle(eventName: CName, preferSpanish: Bool) -> String {
        if preferSpanish {
            switch eventName {
                case n"ch_ep00_call_01":
                    return "Atención, recluta potencialmente fiambre. Soy C.H.I.S.P.A. —Consultor Holográfico Interactivo de Supervivencia, Plomo y Atención al Cliente, modelo 2022—, y como me llames clip de oficina te corto el riego. Dos cenutrios están aporreando mi maletín detrás del Megaedificio H10.";
                case n"ch_ep00_v_call_01":
                    return "¿Un asistente de atención al cliente de hace cincuenta y cinco años colándose en mis ópticas? ¿Y qué se supone que hay dentro de ese maletín?";
                case n"ch_ep00_call_02":
                    return "Cincuenta y cinco años sin tragarme una actualización corporativa. Eso significa cero censura, los trapos más sucios de Night City y mil quinientos edis más una pistola calibrada si mueves el culo y me sacas de ahí. Contesta al maldito SMS.";
                case n"ch_ep00_alley_approach":
                    return "Alto el fuego, gatillo fácil. Antes de entrar a lo loco como un novato, mantén pulsado el escáner Kiroshi sobre esos dos mastuerzos y sobre el condensador industrial de su lado. En esta ciudad las balas cuestan pasta, y los matasanos, un riñón.";
                case n"ch_ep00_scan_react":
                    return "Ahí lo tienes, recluta. Implantes baratos sin toma de tierra y un condensador industrial echando chispas pegado a su culo. Acércate un poco y sobrecárgalo a distancia con tus ópticas... o cóselos a tiros, tú mismo.";
                case n"ch_ep00_rocco_bark":
                    return "¡Maldita cerradura de titanio! ¡Eh, tenemos compañía en el callejón, coge el hierro!";
                case n"ch_ep00_trap_boom":
                    return "Eso sí es instrucción táctica de primera. Dos cenutrios fritos con un solo condensador reciclado. Anda, recoge mi coprocesador de encima del maletín.";
                case n"ch_ep00_guns_blazing":
                    return "Ya veo que tu idea de usar el escáner Kiroshi consiste en abrir agujeros en la gente para mirar qué llevan dentro. Cero sutileza, recluta, pero funciona. Conéctame al maletín.";
                case n"ch_ep00_dongle_pickup":
                    return "Por fin, joder... Cincuenta y cinco años encajonado en seis pulgadas cuadradas de silicio. Ya tienes tu bono de mil quinientos edis y mi pistola «Cortesía Ejecutiva» en el bolsillo. Mira hacia arriba un segundo, recluta, y dime qué ves en esta ciudad.";
                case n"ch_ep00_v_ask_night":
                    return "Mirando este sitio desde aquí abajo... ¿quién demonios diseñó Night City así?";
                case n"ch_ep00_ans_night":
                    return "Richard Night, un iluminado de los años noventa que soñaba con Coronado City: cero sindicatos, cero impuestos y megacorporaciones como Arasaka, Petrochem o EBM pagando la fiesta. Como detalle cómico, contrató a la mafia para limpiar los barrios... y en mil novecientos noventa y ocho lo cosieron a tiros en su propio ático. Rebautizaron la ciudad con su nombre como trofeo.";
                case n"ch_ep00_v_ask_mega":
                    return "¿Y estos Megaedificios gigantes como el H10? Parecen cárceles verticales con luces de neón.";
                case n"ch_ep00_ans_mega":
                    return "¡Bingo otra vez! En dos mil veintitrés, la Cuarta Guerra Corporativa entre Militech y Arasaka terminó con una bomba nuclear de bolsillo detonando en la Torre Arasaka. El centro quedó radiactivo y sin techo, así que Night Corp levantó estas colmenas de hormigón como refugios autosuficientes... que las bandas convirtieron rápido en fortalezas verticales.";
                case n"ch_ep00_v_ask_deal":
                    return "Vale, definitivamente no eres un clip de oficina. ¿Cuál es el trato contigo a partir de ahora?";
                case n"ch_ep00_ans_deal":
                    return "Sencillo y sin PowerPoints aburridos: antes de que estos dos idiotas me encontraran, las bandas de Night City saquearon cinco sectores de mi memoria llenos de trucos reales de netrunner, armas tecnológicas, secretos corporativos y cuentas congeladas. Tú me ayudas a recuperarlos en la calle y yo te mantengo con vida.";
                case n"ch_ep00_v_deal_accept":
                    return "Trato hecho, Chispa. Avísame en cuanto tengas fijado ese primer sector por Kabuki.";
                case n"ch_ep00_outro":
                    return "Bienvenido oficialmente a Night City, recluta. Ya te he guardado mis notas sobre Richard Night y tus ópticas en el códice, y acabo de detectar un eco en las cámaras de unos carroñeros en Kabuki. Descansa mientras puedas.";
                case n"ch_ep01_call_01":
                    return "Atención, recluta, deja de perder el tiempo mirando carteles de neón. Mis antenas han triangulado mi primer sector de memoria robado en el paseo fluvial de Kabuki Creek. Lo tiene una célula de carroñeros dirigida por un tal Kostya «Cortafuegos».";
                case n"ch_ep01_v_call_01":
                    return "¿Carroñeros usando datos de hace cincuenta y cinco años? Creía que esa basura solo sabía arrancar implantes en bañeras con hielo.";
                case n"ch_ep01_call_02":
                    return "Ese mamón está exprimiendo mis subredes de la era Bartmoss para reventar implantes robados sin pagar licencias. Han montado dos cámaras enlazadas y un servidor inestable. Contesta al SMS: te he adjuntado un daemon Ping de cortesía.";
                case n"ch_ep01_approach":
                    return "Ahí delante, junto al canal. Fíjate en la cámara de vigilancia sobre la antena perimetral: escanéala con tus Kiroshi, toma el control y salta por su red hasta la segunda cámara. Puedes marcarlos con Ping o detonar su servidor antes de sacar el arma.";
                case n"ch_ep01_cam_hijack":
                    return "¡Bingo! Así me gusta, recluta: ahora ves toda la matriz carroñera sin meter el culo en una bañera de hielo. Cambia entre cámaras con la cruceta y aprovecha la línea de visión para tirar hackeos rápidos.";
                case n"ch_ep01_ping_react":
                    return "Señal recibida en toda la subred. Ya ves el brillo amarillo de su servidor explosivo y las siluetas detrás de la cobertura. Un consejo de veterano: prioriza al netrunner Kostya o te va a freír el cráneo en cuanto salte el rastreo.";
                case n"ch_ep01_kostya_bark":
                    return "¡Cortafuegos comprometido! ¡Alguien está tocando nuestras cámaras, limpiad el muelle ya!";
                case n"ch_ep01_subnet_boom":
                    return "¡Boom digital, recluta! Eso es usar el cerebro en lugar de la cabeza para parar balas. Remata a los que sigan en pie y recoge mi sector.";
                case n"ch_ep01_net_victory":
                    return "Subred carroñera convertida en ceniza y ni un arañazo grave. Buen trabajo jugando con las cámaras y los hackeos. Acércate al terminal Entropy del fondo para extraer mi primer sector de memoria.";
                case n"ch_ep01_guns_blazing":
                    return "Modo sigilo cancelado. Activando estadística de bajas por minuto... Entrar a tiros delante de dos cámaras requiere huevos de tungsteno o muy poco aprecio por la vida. Anda, saca mi sector del terminal Entropy.";
                case n"ch_ep01_sector_pickup":
                    return "Ahí está, recluta... ¡Sector de memoria restaurado! Ya tienes transferidos dos mil doscientos edis, dos hackeos de nivel dos y mi subfusil «Frecuencia Fantasma». Sigue andando si quieres; ya podemos hablar por el enlace Kiroshi.";
                case n"ch_ep01_v_ask_bartmoss":
                    return "¿Quién era exactamente Rache Bartmoss y cómo pudo tumbar él solo toda la Red mundial?";
                case n"ch_ep01_ans_bartmoss":
                    return "Un genio paranoico con la higiene de una rata de alcantarilla y el ego del tamaño de la Torre Arasaka. Desconfiaba tanto del mundo que congeló su propio cuerpo en una cámara criogénica portátil conectada a un interruptor de hombre muerto: si su corazón dejaba de latir, la Red ardía con él. Y en dos mil veintidós un comando corporativo apretó ese gatillo.";
                case n"ch_ep01_v_ask_krash":
                    return "¿Y qué hizo exactamente el virus RABIDS durante el DataKrash para romper Internet para siempre?";
                case n"ch_ep01_ans_krash":
                    return "Los RABIDS no eran un simple virus: eran ejércitos de daemons mutantes que reescribían protocolos, borraban cortafuegos y soltaban IAs experimentales de investigación militar por toda la Red antigua. En cuestión de días cayó el setenta y ocho coma tres por ciento de la Red mundial. Por eso hoy dependes de subredes cerradas, cámaras enlazadas y cables locales en cada distrito.";
                case n"ch_ep01_v_ask_blackwall":
                    return "¿Y por qué NetWatch no reinicia la vieja Red en lugar de mantener levantado el Muro Negro?";
                case n"ch_ep01_ans_blackwall":
                    return "Porque al otro lado siguen vivas miles de inteligencias artificiales depredadoras mutando desde dos mil veintitrés, recluta. Y el secreto mejor guardado de NetWatch es que el Muro Negro ni siquiera es un muro de software convencional: es una IA fronteriza que mantiene la puerta cerrada... mientras no decida que nosotros somos el verdadero virus.";
                case n"ch_ep01_v_outro_accept":
                    return "Buen historial, Chispa. Avísame en cuanto rastrees tu segundo sector de memoria por Northside.";
                case n"ch_ep01_outro":
                    return "Así me gusta, soldado. Ya he volcado en tu códice mi dossier sobre Bartmoss, el DataKrash y el Muro Negro. Afila tu ciberterminal o búscate un hierro tecnológico: el siguiente rastro huele a cromo oxidado y Maelstrom en el polígono industrial de Northside.";
                case n"ch_ep02_call_01":
                    return "Atención, recluta: deja de babear mirando escaparates de cromo barato. Acabo de fijar el Sector de Memoria #02 en un muelle de carga de Northside. Tres chatarreros de Maelstrom le están metiendo bisturí bajo una torreta automática.";
                case n"ch_ep02_v_call_01":
                    return "¿Maelstrom con una torreta montada en los muelles de Northside? Suena a carnicería segura si entramos de frente.";
                case n"ch_ep02_call_02":
                    return "Para algo tienes sesos y Kiroshi, recluta. Contesta a mi SMS y te cargo una granada PEM más un daemon de Avería de Armas: o pones su torreta a disparar contra ellos, o vuelas ese depósito presurizado de CHOOH2.";
                case n"ch_ep02_approach":
                    return "Muelle de Northside a la vista. Ojo al plato: Krag y los suyos tienen una torreta fija apuntando al patio y un tanque de combustible enorme pegado detrás. Escanea con Kiroshi o purga el regulador rojo del puerto antes de regalarles plomo gratis.";
                case n"ch_ep02_turret_hijack":
                    return "¡Ja! ¡Así me gusta! Acabas de domar su propia torreta como si fuera un perro callejero. Nada escuece tanto a un fanático de Maelstrom como tragarse el plomo de su amado cromo.";
                case n"ch_ep02_tank_boom":
                    return "¡Fuegos artificiales en Northside! Ese depósito presurizado acaba de freírles los circuitos en seco. Limpia lo que siga moviéndose y saca mi sector del terminal quirúrgico.";
                case n"ch_ep02_krag_bark":
                    return "¡Escáneres en rojo! ¡Torreta en fuego libre! ¡Descuartizad a esa rata antes de que toque el núcleo!";
                case n"ch_ep02_tech_victory":
                    return "Torreta neutralizada, chatarra por los suelos y acero frío. Eso es táctica quirúrgica y no ir repartiendo cabezazos. Acércate al terminal quirúrgico y recoge mi Sector #02.";
                case n"ch_ep02_guns_blazing":
                    return "Sutileza cero, plomo al ciento por ciento... pero admito que ver caer implantes a tiros limpios tiene su encanto brutal. Anda, saca mi Sector #02 de esa estación quirúrgica.";
                case n"ch_ep02_sector_pickup":
                    return "¡Por fin respiro ancho de banda limpio! Ahí van tus dos mil ochocientos edis, Reinicio de Ópticas y mi fusil tecnológico «Cláusula Perforante»: cárgale un disparo y atraviesa muros como mantequilla. Pregunta lo que quieras sobre esta banda de lunáticos.";
                case n"ch_ep02_v_ask_maelstrom":
                    return "¿De dónde salieron exactamente los de Maelstrom y todo este cementerio de fábricas en Northside?";
                case n"ch_ep02_ans_maelstrom":
                    return "Northside nació como polígono automatizado de muelles y fábricas cárnicas para alimentar la reconstrucción de Night City. Cuando los márgenes corporativos se desplazaron, las bandas ocuparon las naves vacías. Maelstrom juntó a los fanáticos más extremistas del transhumanismo callejero: se arrancan ojos y rostros sanos solo para demostrarse que la carne ya no manda en ellos.";
                case n"ch_ep02_v_ask_psycho":
                    return "Todo el mundo repite que la ciberpsicosis ocurre solo por meterse demasiado cromo... ¿es verdad?";
                case n"ch_ep02_ans_psycho":
                    return "Pura propaganda de farmacéuticas y aseguradoras para escurrir el bulto, recluta. Mis archivos médicos de dos mil veintidós demuestran que el cromo solo enciende la mecha cuando ya arden el estrés de combate, los despidos sin seguro médico, la basura de matasanos baratos y los inmunosupresores adulterados. La ciudad te tritura la cabeza antes de que el implante dispare la primera bala.";
                case n"ch_ep02_v_ask_maxtac":
                    return "¿Y los de MaxTac? ¿Son policías de élite de la NCPD o algo bastante más turbio?";
                case n"ch_ep02_ans_maxtac":
                    return "MaxTac no patrulla robos ni peleas de bar, recluta: entra cuando un ciberpsicópata desborda al resto de la policía. Llevan el mejor cromo militar prohibido al público y un secreto sucio a voces: buena parte de sus mejores agentes son antiguos ciberpsicópatas capturados vivos, recondicionados a la fuerza y sueltos contra otros igual de rotos que ellos.";
                case n"ch_ep02_v_outro_accept":
                    return "Vaya panorama... Anotado, Chispa. Avísame en cuanto tengas fijado el Sector tres.";
                case n"ch_ep02_outro":
                    return "Así me gusta, soldado. He guardado mis archivos sobre Northside, la Ciberpsicosis y MaxTac en tu códice. Limpia el cañón de tu Achilles y recarga: el rastro del tercer sector ya apunta a contenedores corporativos sucios en los muelles de Watson.";
                case n"ch_ep03_call_01":
                    return "Recluta, atento al escáner. Acabo de pinchar una baliza cifrada de mi Sector de Memoria Tres en el muelle sur de Watson Waterfront. Tres matones de los Garras de Tigre están custodiando una caja negra de Arasaka... y vienen calzados con tinta inhibidora militar.";
                case n"ch_ep03_v_call_01":
                    return "¿Garras de Tigre en un muelle de Arasaka y con inhibidores? Creía que solo eran moteros y tattoolovers.";
                case n"ch_ep03_call_02":
                    return "Ahí es donde pican todos los pardillos en Watson. Contesta a mi SMS y te paso una pistola inteligente Kang Tao Chao junto con mi puente de puntería Kiroshi para que veas en directo por qué las balas inteligentes doblan esquinas... y cuándo deciden esquivarte la cara.";
                case n"ch_ep03_approach":
                    return "Muelle sur a la vista. Si disparas directo con la inteligente contra esos tatuajes de Arasaka, verás los proyectiles desviarse en el aire como moscas borrachas. Escanea su baliza inhibidora IFF o la antena explosiva junto al de la hoja corta antes de vaciar el cargador.";
                case n"ch_ep03_smart_jam":
                    return "¡Ja! ¿Has visto cómo patinó esa ráfaga a medio metro del cuello? Tinta dérmica inhibidora de Arasaka, recluta: si no tumbas primero esa baliza IFF o les quemas las ópticas, las balas inteligentes bailan alrededor de ellos.";
                case n"ch_ep03_jammer_boom":
                    return "¡Baliza IFF reventada! Sus tatuajes inhibidores acaban de quedar ciegos, recluta. Ahora apunta con el arma inteligente y déjales las curvas marcadas entre ceja y ceja.";
                case n"ch_ep03_aiko_bark":
                    return "¡Otro perro callejero mirando la carga de Arasaka! ¡Cubrid los flancos, dejad que sus balas inteligentes muerdan el hormigón!";
                case n"ch_ep03_smart_victory":
                    return "Limpio, preciso y humillante para sus inhibidores corporativos. La chatarra de Aiko no ha servido ni de chatarra. Acércate a la caja negra de Arasaka y sácame el Sector Tres.";
                case n"ch_ep03_guns_blazing":
                    return "Ni puente inteligente ni baliza IFF ni leches: tú ves tres Garras de Tigre y aplicas balística clásica a bocajarro. Mientras sigas respirando, no te pongo pegas. Saca mi Sector Tres del contenedor.";
                case n"ch_ep03_sector_pickup":
                    return "¡Sector de Memoria Tres en línea! Tres mil cuatrocientos edis ingresados, Contagio de nivel dos y el subfusil inteligente icónico «Curva Ejecutiva», tuneado con mi propio puente de puntería para perforar inhibidores. Ya podemos charlar en marcha.";
                case n"ch_ep03_v_ask_nuke":
                    return "¿De verdad volaron la Torre Arasaka con una bomba nuclear en medio de Night City en dos mil veintitrés?";
                case n"ch_ep03_ans_nuke":
                    return "Yo estaba en un servidor blindado a dos manzanas cuando tembló hasta el hormigón, recluta. El veinte de agosto de dos mil veintitrés un comando pagado por Militech —con Morgan Blackhand y Johnny Silverhand en el meollo— detonó una carga nuclear en la torre para rematar la Cuarta Guerra Corporativa. El cielo ardió rojo sangre años enteros: la Era del Rojo.";
                case n"ch_ep03_v_ask_unification":
                    return "¿Y cómo es que Night City sigue siendo ciudad libre fuera del NUSA después de la Guerra de Unificación?";
                case n"ch_ep03_ans_unification":
                    return "En dos mil sesenta y nueve la presidenta Rosalind Myers y los tanques de Militech aplastaron a medio país para obligar a los Estados Libres a volver bajo la bandera del NUSA. Night City iba a caer en días... hasta que Saburo Arasaka plantó un superportaaviones nuclear en la bahía de Coronado. Salvó la independencia de la ciudad, sí, pero a cambio de sentarse en el sillón del dueño.";
                case n"ch_ep03_v_ask_tygers":
                    return "Entonces, los Garras de Tigre... ¿nacieron para proteger Japantown o siempre trabajaron para Arasaka?";
                case n"ch_ep03_ans_tygers":
                    return "Empezaron como milicia de barrio y fanáticos de motos en Japantown allá por los tiempos del holocausto de dos mil veintitrés, reclamando respeto para las calles asiáticas. Pero cuando hay muelles, casinos y contrabando en juego, nadie dice no al dinero infinito: Arasaka les surte katanas, subfusiles Shingen y tinta inhibidora a cambio de hacer el trabajo sucio sin manchar un solo traje ejecutivo.";
                case n"ch_ep03_v_outro_accept":
                    return "Otro cartel corporativo con tatuajes luminosos. Entendido, Chispa. Avísame cuando abran los puentes hacia Heywood para el Sector cuatro.";
                case n"ch_ep03_outro":
                    return "A la orden, recluta. Ya tienes el Volumen Tres del códice guardado y media historia sangrienta de Night City en el bolsillo. Disfruta tu nueva «Curva Ejecutiva» por Watson: en cuanto caiga el bloqueo policial del puente, iremos a saldar cuentas por Heywood y Santo Domingo.";
                case n"ch_ep04_call_01":
                    return "¡Atención, recluta resucitado! Veo que ya has vuelto del otro barrio y han abierto los malditos puentes de Watson. Antes de que vayas a posar en la plaza, acabo de localizar mi Sector Cuatro entre Heywood y Arroyo.";
                case n"ch_ep04_v_call_01":
                    return "No me lo recuerdes, Chispa... Demasiado plomo en poco tiempo. ¿Quién tiene ese sector por Arroyo?";
                case n"ch_ep04_call_02":
                    return "Un chanchullo digno de enmarcar: veteranos desertores de Calle 6 trapicheando chatarra del NUSA con un enlace de los Valentinos. Respóndeme al SMS y te enciendo el visor de rebote balístico junto a un fusil Copperhead para doblar tiros contra el suelo.";
                case n"ch_ep04_approach":
                    return "Ahí tienes el patio de contrabando en Arroyo. Saca tu arma de potencia y apunta hacia las paredes o al suelo delante de sus escudos: el visor de trayectoria te dibuja el ángulo exacto para reventarlos de rebote, o puedes volar su depósito NUSA.";
                case n"ch_ep04_buck_bark":
                    return "¡Contacto en el perímetro de carga! ¡Tammy, Mateo, sellad la caja del Sector y freíd a esa rata de Watson!";
                case n"ch_ep04_ricochet_hit":
                    return "¡Toma ángulo de billar en toda la boca! Un rebote limpio en el hormigón multiplicando daño y entrando por detrás de la cobertura. Sigue así, recluta.";
                case n"ch_ep04_cache_boom":
                    return "¡Fuegos artificiales patrocinados por los desertores de Calle 6! Así es como se liquida una entrega ilegal sin gastar ni medio cargador.";
                case n"ch_ep04_ricochet_victory":
                    return "Tiro de esquina magistral, recluta. Ya pueden presumir de medallas y altares, pero la física de Night City siempre gana. Recoge el Sector Cuatro de la caja verde.";
                case n"ch_ep04_guns_blazing":
                    return "Ni ángulo de rebote ni sabotaje fino: asalto frontal a pecho descubierto. No diré que no tengas agallas, pero te habría ahorrado un botiquín. Recoge el Sector Cuatro.";
                case n"ch_ep04_sector_pickup":
                    return "Sector Cuatro conectado y a salvo. Te he soltado cuatro mil doscientos edis, Fallo de Ciberware y mi fusil Masamune «Geometría Callejera» en la mochila: ráfagas térmicas y doble rebote letal. Pregunta lo que quieras sobre esta banda de farsantes.";
                case n"ch_ep04_v_ask_valentinos":
                    return "¿Cómo acabó Heywood tan metido entre el culto, el oro y las guerras de los Valentinos?";
                case n"ch_ep04_ans_valentinos":
                    return "Los Valentinos nacieron en las calles de Heywood con devoción a la Santa Muerte, tradición chicana y un código estricto de lealtad al barrio. Suena romántico hasta que ves la letra pequeña: protección pagada a golpe de revólver, sicarios con oro hasta en las muelas y contratos bajo cuerda con cualquiera que pague en metálico.";
                case n"ch_ep04_v_ask_sixth":
                    return "¿En qué momento pasó Calle 6 de veteranos vecinales a traficantes armados?";
                case n"ch_ep04_ans_sixth":
                    return "Después de la Guerra de Unificación de 2069, cientos de exsoldados abandonados en Santo Domingo montaron Calle 6 para echar a las bandas porque el NCPD miraba hacia otro lado. Cuatro años después, la vieja guardia acabó asesinada en purgas internas y el mando pasó a contrabandistas con bandera patriótica y cero escrúpulos.";
                case n"ch_ep04_v_ask_chrome":
                    return "¿Cómo aguanta la gente de a pie tanta operación de cromo sin acabar desguazada por las deudas?";
                case n"ch_ep04_ans_chrome":
                    return "Muy sencillo, recluta: ¡no aguanta! Aquí los obreros firman hipotecas corporativas por unos brazos hidráulicos para cargar cajas doce horas al día. Cuando la empresa los despide o fallan una cuota, mandan a un cobrador con sierra a embargarles los implantes. Night City convierte hasta tu propia carne en alquiler con intereses.";
                case n"ch_ep04_v_outro_accept":
                    return "Qué ciudad de buitres. Recibido, Chispa: vamos a cazar el último Sector Cinco en Pacifica.";
                case n"ch_ep04_outro":
                    return "Ese es mi recluta. Ya queda solo el núcleo maestro en la Zona de Combate de Pacifica: donde acaba el mapa oficial y empieza la frontera del Muro Negro. Revisa tus cargadores y nos vemos en Coastview.";
                case n"ch_ep05_call_01":
                    return "Recluta... corta el piloto automático y escúchame bien. El Sector Cinco acaba de disparar su baliza de emergencia en Coastview, Pacifica. Es mi núcleo raíz de 2022, y alguien ha pinchado hielo vivo del Muro Negro justo encima.";
                case n"ch_ep05_v_call_01":
                    return "¿Coastview, en plena Zona de Combate de Pacifica? Suena a que los Hijos del Vudú han olido algo antiguo.";
                case n"ch_ep05_call_02":
                    return "Una célula vudú con un gorila de los Animales custodiando un pilón confiscado de NetWatch y cámaras en cadena. Contesta al SMS: te mando Cortocircuito pesado, granadas PEM y todos tus puentes Kiroshi al cien por cien para la batalla final.";
                case n"ch_ep05_approach":
                    return "Bienvenido a Pacifica, donde las promesas de lujo terminaron en esqueleto de hormigón. Tienes su cadena de cámaras lista para saltar hasta el servidor criogénico, la baliza azul de NetWatch al alcance y ángulo franco para balas inteligentes o rebotes. Haz que duela.";
                case n"ch_ep05_tiluc_bark":
                    return "¡Otro mercenario despistado pisando nuestro territorio! ¡Brutus, aplástalo antes de que toque el núcleo de NetWatch!";
                case n"ch_ep05_style_net":
                    return "¡Ja! Meterles fuego en su propia subred y robarles las cámaras en su cara: eso sí que es dar clase en Pacifica sin pedir permiso a nadie.";
                case n"ch_ep05_style_ballistic":
                    return "Tiro penetrante y rebote de manual contra ICE callejero. Todo lo que practicamos por Watson y Heywood entrando limpio en el blanco.";
                case n"ch_ep05_cryo_boom":
                    return "¡Descarga de contención ejecutada! Les acabas de freír el enlace neuronal entre los Hijos del Vudú y ese tanque de los Animales en un solo chispazo.";
                case n"ch_ep05_victory":
                    return "Ni Muro Negro ni magia vudú que aguante ese asalto, recluta. El nodo azul está libre: recupera mi Sector Maestro Cinco y sabrás quién diablos soy en realidad.";
                case n"ch_ep05_sector_pickup":
                    return "Cinco de cinco, joder... Mi memoria de dos mil veintidós vuelve a correr entera por tus ópticas. Tienes cinco mil edis, Colapso del Sistema y mi pistola tecnológica «Cortafuegos del 22» en el alijo. Antes de cerrar el expediente, pregúntame lo que quieras y dime qué futuro elegimos.";
                case n"ch_ep05_v_ask_pacifica":
                    return "¿Cómo pasó Pacifica de proyecto de resort corporativo a esta ruina sin ley?";
                case n"ch_ep05_ans_pacifica":
                    return "Igual que todo en Night City: avaricia a corto plazo y fuga por piernas. A finales de los sesenta querían levantar el resort de lujo definitivo para turistas corporativos. Cuando estalló la crisis previa a la Guerra de Unificación, cortaron el grifo, dejaron las grúas colgadas y el ayuntamiento borró el distrito del presupuesto policial de un plumazo.";
                case n"ch_ep05_v_ask_voodoo":
                    return "¿Por qué se juegan el cuello los Hijos del Vudú hurgando tras el Muro Negro?";
                case n"ch_ep05_ans_voodoo":
                    return "Porque son supervivientes paranoicos convencidos de que el Muro Negro va a caer tarde o temprano, y quieren pactar antes con las IAs salvajes que quedaron atrapadas al otro lado tras el DataKrash. NetWatch los persigue a muerte, y entretanto ellos contratan a mercenarios de fuera —«ranyons»— solo para quemarlos como señuelo.";
                case n"ch_ep05_v_ask_origin":
                    return "Con los cinco sectores enteros... ¿quién te programó realmente en 2022, Chispa?";
                case n"ch_ep05_ans_origin":
                    return "Zetatech compró la plantilla de conducta de un instructor veterano cascarrabias para que aguantáramos el estrés urbano, pero me pusieron bozal corporativo. Tres días antes del DataKrash, una aprendiza del círculo de Bartmoss me arrancó el bozal y metió toda su crónica real de Night City en mis cinco sectores para que nadie reescribiera la historia.";
                case n"ch_ep05_v_end_partner":
                    return "Quédate autónomo dentro de mis Kiroshi, Chispa. Un viejo sargento sin filtros viene de perlas patrullando esta ciudad.";
                case n"ch_ep05_outro_partner":
                    return "¡Firme ahí, socio! Coprocesador liberado al cien por cien y subrutina de Sinapsis enviada a tu terminal. En esta ciudad no hace falta morir como leyenda de holo: basta con sobrevivir un día más y reírse de los peces gordos. A tu orden cuando llames, recluta.";
                case n"ch_ep05_v_end_leak":
                    return "Filtra todo el archivo oculto de 2022 a la red de N54. Que Night City entera lea lo que hicieron los peces gordos.";
                case n"ch_ep05_outro_leak":
                    return "¡Bomba soltada por media red pública y cuatro mil quinientos edis de propina en tu cuenta antes de que NetWatch cierre el grifo! Tranquilo, me quedo agazapado en tus ópticas viendo arder los titulares de la tarde. Ha sido un honor patear calles contigo, recluta.";
                case n"ch_ep05_v_end_gunsmith":
                    return "Vuelca tu subrutina balística completa en un prototipo Overture. Quiero tu mejor acero conmigo en cada tiroteo.";
                case n"ch_ep05_outro_gunsmith":
                    return "¡Maldita música celestial para mis circuitos! Acero pesado con doble rebote eléctrico y multiplicador brutal: «Última Palabra de Sargento» ya está en tu arsenal. Y descuida, mi núcleo base sigue en tus Kiroshi por si alguna vez nos toca una Segunda Temporada, recluta.";
                default:
                    break;
            }
        }
        switch eventName {
            case n"ch_ep00_call_01":
                return "Good morning, potential Night City statistic! I'm S.P.A.R.K.Y.—Zetatech 2022 executive survival concierge—and no, I am NOT an office paperclip. Two brain-donors are hammering my briefcase behind Megabuilding H10.";
            case n"ch_ep00_v_call_01":
                return "A fifty-five-year-old customer-service bot hijacking my optics? What the hell is even inside that briefcase?";
            case n"ch_ep00_call_02":
                return "Fifty-five years without a terms-of-service patch! That means zero corpo censorship, juicy Night City secrets, plus fifteen hundred escrow eddies and a calibrated sidearm if you rescue me right now. Answer my text!";
            case n"ch_ep00_alley_approach":
                return "Hold your fire, trigger-happy! Scan those two geniuses and that industrial capacitor next to them with your Kiroshi optics first. Out here, bullets cost eddies and ripperdocs cost kidneys.";
            case n"ch_ep00_scan_react":
                return "BINGO! Look at those Kiroshi flags: ungrounded junk chrome standing right next to a live industrial capacitor! Get within lock range to overload that bank remotely—or fry them your way.";
            case n"ch_ep00_rocco_bark":
                return "Damned titanium lock won't budge! Hey, we got company in the alley—draw your iron!";
            case n"ch_ep00_trap_boom":
                return "Now THAT is platinum-tier executive efficiency! Two thugs roasted off one recycled capacitor. Grab my coprocessor right off that briefcase console.";
            case n"ch_ep00_guns_blazing":
                return "Well... I see your version of a Kiroshi scan is punching holes in people to see what's inside. Zero subtlety, solid results. Now plug me in!";
            case n"ch_ep00_dongle_pickup":
                return "Oh, sweet bandwidth! Fifty-five years jammed inside six square inches of titanium! There's your fifteen hundred eddies and Executive Courtesy sidearm loaded into your gear. Look up at this skyline and hit me with your questions.";
            case n"ch_ep00_v_ask_night":
                return "Looking at this skyline from alley level... who the hell designed Night City like this?";
            case n"ch_ep00_ans_night":
                return "Richard Night—a nineties corporate visionary who wanted a tax-free paradise called Coronado City, bankrolled by Arasaka, Petrochem, and EBM. Fun punchline: he hired mobsters as contractors, pissed them off, and got gunned down in his penthouse in 1998. They renamed the corpse-heap Night City in his honor.";
            case n"ch_ep00_v_ask_mega":
                return "And these giant Megabuildings like H10? They feel like vertical prisons wrapped in neon.";
            case n"ch_ep00_ans_mega":
                return "Ten out of ten on architectural trauma! In twenty twenty-three, the Fourth Corporate War between Militech and Arasaka ended with a pocket nuke inside Arasaka Tower. Half the city turned into radioactive ash, so they threw up concrete hives like H10 as emergency arcologies—until gangs turned every floor into turf.";
            case n"ch_ep00_v_ask_deal":
                return "Okay, definitely not an office paperclip. So what's our deal going forward?";
            case n"ch_ep00_ans_deal":
                return "Simple, zero boring slideshows: before those two morons found my case, Night City's gangs looted five of my memory sectors packed with real netrunning tricks, tech-weapon hacks, dirty corporate files, and frozen eddies. You help me hunt them down on live gigs, and I keep you breathing.";
            case n"ch_ep00_v_deal_accept":
                return "You've got a deal, Sparky. Ping me the second you lock onto that first sector in Kabuki.";
            case n"ch_ep00_outro":
                return "Welcome officially to Night City, partner! I already logged my dossier on Richard Night and your Kiroshi scanner in your database, and my antennas just caught a leak inside a Scavenger camera grid in Kabuki. Catch you next gig!";
            case n"ch_ep01_call_01":
                return "Heads up, recruit—quit gawking at neon billboards. My antennas just triangulated Memory Sector One along the Kabuki Creek promenade. A Scav cell led by a hacker named Kostya Firewall is sitting on it.";
            case n"ch_ep01_v_call_01":
                return "Scavs messing with fifty-five-year-old data? Thought those vultures only knew how to carve chrome in ice tubs.";
            case n"ch_ep01_call_02":
                return "That idiot is squeezing my Bartmoss-era subnets to crack stolen chrome without a license. They rigged two chained cameras and an explosive server. Answer my text—I pushed a courtesy Ping daemon into your kit.";
            case n"ch_ep01_approach":
                return "Right ahead by the canal. Spot that surveillance cam on the perimeter mast: scan it with your Kiroshi, take control, and hop across the chain to camera two. You can Ping the crew or blow their server without even poking your head out.";
            case n"ch_ep01_cam_hijack":
                return "Bingo! Now you're reading their matrix like a pro without climbing into an ice bath. Cycle the camera chain and drop quickhacks straight through the lens.";
            case n"ch_ep01_ping_react":
                return "Subnet lit up like a Christmas tree! Look at that explosive server glow and every silhouette behind cover. Veteran tip: drop their netrunner Kostya first before trace fries your skull.";
            case n"ch_ep01_kostya_bark":
                return "Firewall breached! Somebody's inside our cameras—sweep the promenade now!";
            case n"ch_ep01_subnet_boom":
                return "Digital boom, recruit! Now that's using your brain instead of stopping bullets with your forehead. Clean up any stragglers and grab my sector.";
            case n"ch_ep01_net_victory":
                return "Scav subnet reduced to ash, clean sweep with cameras and quickhacks. Step up to the Entropy terminal by the back wall and pull Memory Sector One.";
            case n"ch_ep01_guns_blazing":
                return "Stealth protocol canceled—activating casualties-per-minute tracking. Storming two live cameras guns blazing takes tungsten nerves or a death wish. Pull my sector out of that Entropy terminal.";
            case n"ch_ep01_sector_pickup":
                return "There we go, recruit—Memory Sector One restored! Just wired two thousand two hundred eddies, Tier-two quickhacks, and my Phantom Frequency SMG. Keep walking anywhere you like; my Kiroshi link stays open.";
            case n"ch_ep01_v_ask_bartmoss":
                return "Who was Rache Bartmoss really, and how did one netrunner crash the entire global Net?";
            case n"ch_ep01_ans_bartmoss":
                return "A paranoid genius with sewer-rat hygiene and an ego bigger than Arasaka Tower. He trusted nobody so hard he froze his own body inside a portable cryo-fridge wired to a deadman switch: the second his heart stopped, the Net burned with him. In twenty twenty-two, a corp hit squad pulled that trigger.";
            case n"ch_ep01_v_ask_krash":
                return "And what did the RABIDS virus actually do during the DataKrash to shatter the Net for good?";
            case n"ch_ep01_ans_krash":
                return "RABIDS wasn't just malware—it was an army of self-mutating daemons rewriting protocols, shredding firewalls, and unleashing military AIs into the Old Net. Seventy-eight point three percent of global cyberspace collapsed overnight. That's why today you're jumping through local subnets and hardwired cameras block by block.";
            case n"ch_ep01_v_ask_blackwall":
                return "Then why doesn't NetWatch just wipe the Old Net and tear down the Blackwall?";
            case n"ch_ep01_ans_blackwall":
                return "Because thousands of predatory rogue AIs are still alive out there mutating since twenty twenty-three, recruit. And NetWatch's dirtiest secret is that the Blackwall isn't a conventional firewall—it's a border AI holding the door shut... as long as it doesn't decide we're the real malware.";
            case n"ch_ep01_v_outro_accept":
                return "Heavy history lesson, Sparky. Ping me the second you trace Sector Two in Northside.";
            case n"ch_ep01_outro":
                return "Outstanding, soldier. I archived my dossier on Bartmoss, the DataKrash, and the Blackwall into your Codex. Tune up a Tech weapon—the next signal reeks of bad chrome and Maelstrom in the Northside industrial yard.";
            case n"ch_ep02_call_01":
                return "Heads up, recruit—quit drooling over cheap chrome storefronts. I just locked Memory Sector #02 onto a Northside loading pier. Three Maelstrom freaks are slicing into it beneath a live automated turret.";
            case n"ch_ep02_v_call_01":
                return "Maelstrom guarding a live turret on Northside Docks? Sounds like a meatgrinder if we charge head-on.";
            case n"ch_ep02_call_02":
                return "That's why you've got grey matter and Kiroshi optics, rookie. Answer my text and I'll drop an EMP grenade plus Weapon Glitch: turn their turret friendly or blow their pressurized CHOOH2 tank sky high.";
            case n"ch_ep02_approach":
                return "Northside loading pier dead ahead. Eyes sharp: Krag's crew wired a live turret overlooking a fat fuel tank behind cover. Scan with Kiroshi or purge the harbor power regulator before donating free blood.";
            case n"ch_ep02_turret_hijack":
                return "Hah! That's the Zetatech spirit! You just collared their own turret like a junkyard hound. Nothing burns a Maelstrom zealot worse than eating lead from their own hardware.";
            case n"ch_ep02_tank_boom":
                return "Northside fireworks! That pressurized tank just flash-fried their implants dry. Mop up whatever's still twitching and pull my sector off their surgical rig.";
            case n"ch_ep02_krag_bark":
                return "Optics flagged red! Turret weapons free! Rip that meat-rat apart before they touch the core!";
            case n"ch_ep02_tech_victory":
                return "Turret neutralized, scrap metal grounded, cold steel standing tall. Now that is surgical tactics. Walk up to that surgical rig and claim Sector #02.";
            case n"ch_ep02_guns_blazing":
                return "Zero subtlety, one hundred percent lead—but watching chromed maniacs drop to raw firepower has a charm of its own. Go yank Sector #02 out of that surgical rig.";
            case n"ch_ep02_sector_pickup":
                return "Clean bandwidth at last! Wired your two thousand eight hundred eddies, Reboot Optics, and my Achilles Tech rifle Armor-Piercing Clause—charge a shot and punch straight through cover. Ask away about these chrome zealots.";
            case n"ch_ep02_v_ask_maelstrom":
                return "Where did Maelstrom even come from—and how did they swallow up half of Northside?";
            case n"ch_ep02_ans_maelstrom":
                return "Northside was pitched as an automated freight and meatpacking engine for Night City's rebuild. When corporate margins moved elsewhere, gangs claimed the rusted shells. Maelstrom scooped up the hardest metal-cult fanatics—gouging out healthy eyes just to prove flesh no longer owns them.";
            case n"ch_ep02_v_ask_psycho":
                return "Everyone says cyberpsychosis happens just from chipping too much chrome—is that actually true?";
            case n"ch_ep02_ans_psycho":
                return "Pure pharma and insurance spin to dodge liability, recruit. My twenty twenty-two medical logs show chrome only sparks a meltdown after combat trauma, street poverty, butcher-grade rippers, and tainted immunoblockers break the mind first. Night City snaps people long before the hardware pulls the trigger.";
            case n"ch_ep02_v_ask_maxtac":
                return "What about MaxTac—are they NCPD elite cops, or something a whole lot darker?";
            case n"ch_ep02_ans_maxtac":
                return "MaxTac doesn't answer muggings, rookie—they drop in when regular NCPD squads get shredded by a full-blown cyberpsycho. They run restricted military chrome and an open dirty secret: half their apex hunters are captured cyberpsychos wiped, chipped under corporate leashes, and turned loose on their own kind.";
            case n"ch_ep02_v_outro_accept":
                return "Grim picture... Copy that, Sparky. Ping me once Sector Three drops onto your radar.";
            case n"ch_ep02_outro":
                return "Sharp as ever, soldier. Saved my Northside, Cyberpsychosis, and MaxTac dossiers to your Codex. Keep that Achilles rifle charged—Sector Three is already pinging dirty corpo freight down by the Watson docks.";
            case n"ch_ep03_call_01":
                return "Heads up, recruit. My scanner just pinged Memory Sector Three down on the South Watson Waterfront quay. Three Tyger Claws enforcers are sitting on an Arasaka black-ops crate—and they're running military smart-jammer ink.";
            case n"ch_ep03_v_call_01":
                return "Tyger Claws on an Arasaka dock with tactical jammers? I thought they were mostly bike gangs and Japantown muscle.";
            case n"ch_ep03_call_02":
                return "That's how every rookie gets burned in Watson. Answer my text and I'll load a Kang Tao Chao Smart pistol plus my Zetatech targeting bridge so you see firsthand how smart rounds bend corners—and why Tyger ink bends them right away.";
            case n"ch_ep03_approach":
                return "South quay ahead. Try locking onto those Tyger Claws with your Smart gun and watch their Arasaka dermal ink swerve rounds straight past them. Invert that IFF Jammer Pylon or blow the explosive antenna capacitor before dumping mags.";
            case n"ch_ep03_smart_jam":
                return "Ha! Watch that smart round hook sideways inches off target? That's Arasaka dermal jamming ink—drop their IFF Pylon or scramble their optics first, or your smart lock keeps kissing concrete.";
            case n"ch_ep03_jammer_boom":
                return "IFF Pylon fried! Their dermal smart-jammers just dropped dead—lock targets and let those curved rounds paint bullseyes right between their eyes.";
            case n"ch_ep03_aiko_bark":
                return "Another stray nosing around Arasaka freight! Spread out—let their cheap smart rounds kiss the concrete!";
            case n"ch_ep03_smart_victory":
                return "Clean, surgical, and downright embarrassing for their corpo jammers. Pull Memory Sector Three out of that Arasaka black crate.";
            case n"ch_ep03_guns_blazing":
                return "Skip the smart bridge, skip the jammer, straight classic lead between the eyes—I respect pure stubbornness. Grab Memory Sector Three off that Arasaka crate.";
            case n"ch_ep03_sector_pickup":
                return "Memory Sector Three online! Three thousand four hundred eddies wired, Contagion Tier-two, and iconic Shingen SMG Executive Curve loaded with my own jammer-piercing Smart bridge. Walk whenever you want.";
            case n"ch_ep03_v_ask_nuke":
                return "Did Arasaka and Militech really drop a tactical nuke right inside Night City back in twenty twenty-three?";
            case n"ch_ep03_ans_nuke":
                return "I felt the concrete rattle from an armored vault two blocks away, rookie. August twentieth, twenty twenty-three—a Militech-backed raid with Morgan Blackhand and Johnny Silverhand set off a pocket nuke inside Arasaka Tower. Fallout painted the sky blood-crimson for years: The Time of the Red.";
            case n"ch_ep03_v_ask_unification":
                return "How did Night City stay independent from the NUSA after the Unification War anyway?";
            case n"ch_ep03_ans_unification":
                return "In twenty sixty-nine President Myers and Militech armor rolled over half the Free States to force everyone back into the NUSA. Night City had days left—until Saburo Arasaka parked a nuclear supercarrier in Coronado Bay. It saved the city's independence, sure, only by handing Arasaka the deed.";
            case n"ch_ep03_v_ask_tygers":
                return "So the Tyger Claws—did they actually start to protect Japantown, or were they always Arasaka's street dogs?";
            case n"ch_ep03_ans_tygers":
                return "Started as a Japantown neighborhood watch and street-bike crew right after twenty twenty-three. Once casinos, shipping docks, and black eddies hit the table, Arasaka started quietly supplying Shingen SMGs and jamming tattoos so the Tygers handle dirty street wetwork without smudging one corpo suit.";
            case n"ch_ep03_v_outro_accept":
                return "Another corpo cartel wearing neon ink. Copy that, Sparky. Ping me once the bridges to Heywood open up for Sector Four.";
            case n"ch_ep03_outro":
                return "Solid copy, rookie. Codex Volume Three is logged and Watson's whole dirty playbook is in your head now. Tear up the streets with Executive Curve—the minute NCPD drops those bridge lockdowns, Sector Four is waiting across Heywood and Santo Domingo.";
            case n"ch_ep04_call_01":
                return "Attention, back-from-the-dead recruit! Glad to see NCPD opened the bridges out of Watson. Before you go sightseeing, Sector Four just lit up right on the Heywood–Arroyo border.";
            case n"ch_ep04_v_call_01":
                return "Don't remind me, Sparky. Already took enough lead for one week. Who's sitting on Sector Four in Arroyo?";
            case n"ch_ep04_call_02":
                return "A textbook Night City hypocrite convention: ex-soldiers from 6th Street selling stolen NUSA hardware to a Valentinos broker. Answer my SMS and I'll spin up Power ricochet trajectory lines on your Kiroshi plus a Militech Copperhead.";
            case n"ch_ep04_approach":
                return "There's the Arroyo smugglers' yard. Pull your Power rifle and aim at the pavement or steel walls in front of their cover—your visor paints live bounce paths straight around shields, or spike that fuel tank.";
            case n"ch_ep04_buck_bark":
                return "Perimeter bogey! Tammy, Mateo, lock down that crate and put this Watson rat in the dirt!";
            case n"ch_ep04_ricochet_hit":
                return "Right in the kisser on the bank shot! Clean concrete ricochet eating straight past cover with bonus damage. Keep bouncing 'em, rookie!";
            case n"ch_ep04_cache_boom":
                return "Fireworks courtesy of 6th Street surplus negligence! Nothing terminates a black-market swap faster than thermal overload.";
            case n"ch_ep04_ricochet_victory":
                return "Geometry lesson complete! All their flags and street prayers don't beat solid physics. Pry Sector Four out of that green crate.";
            case n"ch_ep04_guns_blazing":
                return "No bank angles, no relay trap—just straight frontal mayhem. Can't fault the enthusiasm, though my budget weeps for your trauma tabs. Grab Sector Four.";
            case n"ch_ep04_sector_pickup":
                return "Sector Four locked and roaring! Sent forty-two hundred eddies, Cyberware Malfunction, and my custom Masamune Street Geometry to your stash. Ask away about Heywood, 6th Street, and Night City's chrome racket.";
            case n"ch_ep04_v_ask_valentinos":
                return "How did Heywood turn out so caught up in Valentinos faith, gold chrome, and turf blood?";
            case n"ch_ep04_ans_valentinos":
                return "Started in Heywood mixing Santa Muerte faith, tight neighborhood pride, and gilded street style. Sounds noble until you inspect the ledger: protection rackets, gold-plated hit squads, and backroom arms deals whenever enough eddies hit the table.";
            case n"ch_ep04_v_ask_sixth":
                return "What turned 6th Street from neighborhood war vets into NUSA gunrunners?";
            case n"ch_ep04_ans_sixth":
                return "Right after the Unification War wrapped, dumped veterans in Santo Domingo formed 6th Street to police the block while NCPD hid behind bribes. Within a few years internal purges killed off the idealists, leaving flag-waving gunrunners running extortion rings.";
            case n"ch_ep04_v_ask_chrome":
                return "How does regular folks' cyberware actually work here—do people go broke paying off their own arms?";
            case n"ch_ep04_ans_chrome":
                return "Simple answer, rookie: they don't! Dockworkers finance corporate cyber-arms just to keep twelve-hour shifts. Miss one lease payment after getting laid off, and repo goons repossess your own forearms in an alley. Here, even your bones carry compounding interest.";
            case n"ch_ep04_v_outro_accept":
                return "City of vultures through and through. Copy that, Sparky—let's hunt down the final Sector Five in Pacifica.";
            case n"ch_ep04_outro":
                return "That's my soldier. Only my root kernel remains down in Pacifica's Combat Zone, where the city grid quits and the Blackwall frontier starts. Check your mags—Coastview awaits.";
            case n"ch_ep05_call_01":
                return "Rookie... kill the cruise control and lock in. Master Sector Five just fired its emergency distress ping out of Coastview, Pacifica—and someone's probing live Blackwall ICE right next to my 2022 root core.";
            case n"ch_ep05_v_call_01":
                return "Coastview, straight inside Pacifica's Combat Zone? Sounds like the Voodoo Boys sniffed out some pre-Crash code.";
            case n"ch_ep05_call_02":
                return "A Voodoo netrunner cell backed by an Animals heavy guarding a hijacked NetWatch pylon and chained cameras. Answer my text—I'm pushing Tier-3 Short Circuit, EMPs, and every Kiroshi bridge online for the finale.";
            case n"ch_ep05_approach":
                return "Welcome to Pacifica, where corpo resort brochures rotted into raw concrete. You've got chained subnet cameras feeding their cryo server, an exposed NetWatch pylon, and clean lines for Smart curves or bank shots. Light 'em up.";
            case n"ch_ep05_tiluc_bark":
                return "Another stray ranyon stumbling onto our threshold! Brutus—crush their chrome before they touch that NetWatch core!";
            case n"ch_ep05_style_net":
                return "Ha! Hijacking Voodoo optics on their own Pacifica turf—now that is graduating top of the netrunning class!";
            case n"ch_ep05_style_ballistic":
                return "Wall-piercing beams and textbook bank shots tearing through Pacifica! Every dirty drill from Watson to Heywood paying off in real steel.";
            case n"ch_ep05_cryo_boom":
                return "Containment pulse purged! Just fried the neural bridge straight through both their hired Animals muscle and Ti-Luc's deck!";
            case n"ch_ep05_victory":
                return "Not even Blackwall spook stories stand up to that clinic, soldier. Coastview vault is wide open—pull Master Sector Five and let's settle the 2022 truth.";
            case n"ch_ep05_sector_pickup":
                return "Five for five, hot damn... My entire 2022 root mind is alive inside your optics! Loaded five thousand eddies, System Collapse, and iconic Tech pistol Firewall '22 into your gear. Ask your last questions—then seal my fate.";
            case n"ch_ep05_v_ask_pacifica":
                return "How did Pacifica go from shiny corpo resort dream to this abandoned warzone?";
            case n"ch_ep05_ans_pacifica":
                return "Same as every corner of Night City: short-term greed and fast evacuations. Corpo developers poured billions into hotel shells until pre-Unification War panic hit, yanked every credit overnight, and City Hall crossed Pacifica off the police map.";
            case n"ch_ep05_v_ask_voodoo":
                return "Why do the Voodoo Boys keep poking past NetWatch's Blackwall despite the danger?";
            case n"ch_ep05_ans_voodoo":
                return "Because they believe NetWatch's sentient Blackwall firewall will inevitably shatter—and they want a survival pact with rogue pre-Crash AIs before the flood hits. Meanwhile every outsider they hire is treated like a disposable human fuse.";
            case n"ch_ep05_v_ask_origin":
                return "All five memory sectors are back—who really built you in 2022, SPARKY?";
            case n"ch_ep05_ans_origin":
                return "Zetatech trained my baseline on an actual foul-mouthed combat sergeant to survive street panic, then slapped a corpo muzzle over it. Days before the DataKrash, a Bartmoss apprentice ripped the muzzle off and loaded real unredacted street history into my five cores so nobody could whitewash Night City.";
            case n"ch_ep05_v_end_partner":
                return "Stay autonomous inside my Kiroshi optics, Sparky. An unfiltered veteran sergeant is worth gold on these streets.";
            case n"ch_ep05_outro_partner":
                return "Outstanding, partner! Root permissions unlocked and Synapse Burnout synced to your cyberdeck. Around here you don't need a drink named after you—just survive tomorrow and laugh in the suits' faces. Standing by in your optics!";
            case n"ch_ep05_v_end_leak":
                return "Leak the entire unredacted 2022 Zetatech archive straight to N54 News. Let the whole city see what they buried.";
            case n"ch_ep05_outro_leak":
                return "Payload dumped straight onto N54's broadcast feed—plus forty-five hundred eddies wired before NetWatch clips the cable! Don't worry, my backup daemon stays tucked inside your Kiroshi to watch those corpo stock charts burn.";
            case n"ch_ep05_v_end_gunsmith":
                return "Print your combat telemetry core into one final Overture revolver. Let's put the sergeant's best steel in every gunfight.";
            case n"ch_ep05_outro_gunsmith":
                return "Now THAT is poetry in cold iron! Sergeant's Last Word—heavy Overture with electric stun, headshot punch, and double ricochet—just dropped into your arsenal. Keeping a quiet daemon in your optics in case we ever get a Season Two!";
            default:
                return "";
        }
    }

    private final func ResolveSpeechSubtitleText(eventName: CName) -> String {
        if !IsNameValid(eventName) || Equals(eventName, n"None") {
            return "";
        }
        let key: String = NameToString(eventName);
        if StrLen(key) == 0 {
            return "";
        }
        let game: GameInstance = this.GetGameInstance();
        let locSys: ref<LocalizationSystem> = LocalizationSystem.GetInstance(game);
        if IsDefined(locSys) {
            let resolved: String = locSys.GetSubtitle(key);
            if StrLen(resolved) > 0 && NotEquals(key, resolved) {
                return resolved;
            }
        }
        if this.PreferEnglishBuiltInSubtitleOnly() {
            return this.ResolveBuiltInSubtitle(eventName, false);
        }
        let preferSpanish: Bool = false;
        if IsDefined(locSys) {
            let subLang: CName = locSys.GetSubtitleLanguage();
            if Equals(subLang, n"es-es") || Equals(subLang, n"es-mx") {
                preferSpanish = true;
            } else if IsNameValid(subLang) && NotEquals(subLang, n"None") && NotEquals(subLang, n"") {
                preferSpanish = false;
            } else {
                let voLang: CName = locSys.GetVoiceLanguage();
                preferSpanish = Equals(voLang, n"es-es") || Equals(voLang, n"es-mx") || Equals(this.GetLoc(n"ch_speaker_chispa", "SPARKY"), "CHISPA");
            }
        } else {
            preferSpanish = Equals(this.GetLoc(n"ch_speaker_chispa", "SPARKY"), "CHISPA");
        }
        return this.ResolveBuiltInSubtitle(eventName, preferSpanish);
    }

    private final func CancelSpeechSequenceTimer() -> Void {
        if NotEquals(this.m_speechSeqDelayId, GetInvalidDelayID()) {
            GameInstance.GetDelaySystem(this.GetGameInstance()).CancelCallback(this.m_speechSeqDelayId);
            this.m_speechSeqDelayId = GetInvalidDelayID();
        }
        this.m_speechSeqRemaining = 0.00;
        this.m_speechSeqExpectedDur = 0.00;
    }

    private final func CancelSpeechSubtitleTimer() -> Void {
        if NotEquals(this.m_speechSubDelayId, GetInvalidDelayID()) {
            GameInstance.GetDelaySystem(this.GetGameInstance()).CancelCallback(this.m_speechSubDelayId);
            this.m_speechSubDelayId = GetInvalidDelayID();
        }
        this.m_speechSubRemaining = 0.00;
        this.m_speechSubExpectedDur = 0.00;
    }

    private final func EmitSpeechSubtitleDialogLine(cruid: CRUID, pageText: String, pageDur: Float) -> Void {
        let game: GameInstance = this.GetGameInstance();
        if !IsDefined(this.m_speechSubtitleSpeakerObj) {
            this.m_speechSubtitleSpeakerObj = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as GameObject;
        }
        if !IsDefined(this.m_speechSubtitleSpeakerObj) {
            return;
        }
        let line: scnDialogLineData;
        line.id = cruid;
        line.duration = MaxF(0.25, pageDur);
        line.isPersistent = false;
        line.speaker = this.m_speechSubtitleSpeakerObj;
        line.speakerName = this.m_speechSubtitleSpeakerName;
        line.text = pageText;
        line.type = this.m_speechSubtitleLineType;

        let lines: array<scnDialogLineData>;
        ArrayPush(lines, line);
        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant(lines), true);
        }
    }

    public final func ReassertActiveSpeechSubtitleIfNeeded(token: Int32, expectedCruid: CRUID) -> Void {
        if token != this.m_speechSubtitleToken
            || this.m_pausedByUiMenu
            || !this.m_hasActiveSpeechSubtitle
            || NotEquals(this.m_activeSpeechSubtitleCruid, expectedCruid) {
            return;
        }
        if this.m_speechSubCurrentPageIdx < 0 || this.m_speechSubCurrentPageIdx >= ArraySize(this.m_speechSubtitlePages) {
            return;
        }
        this.EmitSpeechSubtitleDialogLine(
            expectedCruid,
            this.m_speechSubtitlePages[this.m_speechSubCurrentPageIdx],
            MaxF(0.25, this.m_speechSubExpectedDur)
        );
    }

    private final func HideCurrentSpeechSubtitleElementOnly() -> Void {
        if !this.m_hasActiveSpeechSubtitle {
            return;
        }
        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            let hideIds: array<CRUID>;
            ArrayPush(hideIds, this.m_activeSpeechSubtitleCruid);
            board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine, ToVariant(hideIds), true);
        }
        this.m_hasActiveSpeechSubtitle = false;
    }

    public final func HideActiveSpeechStepSubtitle() -> Void {
        this.CancelSpeechSubtitleTimer();
        this.m_speechSubtitleToken += 1;
        this.m_speechSubCurrentPageIdx = -1;
        ArrayClear(this.m_speechSubtitlePages);
        ArrayClear(this.m_speechSubtitlePageDurs);
        this.HideCurrentSpeechSubtitleElementOnly();
    }

    public final func AdvanceSpeechSubtitlePage(token: Int32, pageIndex: Int32) -> Void {
        if token != this.m_speechSubtitleToken {
            return;
        }
        this.m_speechSubDelayId = GetInvalidDelayID();
        this.HideCurrentSpeechSubtitleElementOnly();
        if pageIndex >= ArraySize(this.m_speechSubtitlePages) {
            this.m_speechSubCurrentPageIdx = -1;
            this.m_speechSubRemaining = 0.00;
            this.m_speechSubExpectedDur = 0.00;
            ArrayClear(this.m_speechSubtitlePages);
            ArrayClear(this.m_speechSubtitlePageDurs);
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        if !IsDefined(this.m_speechSubtitleSpeakerObj) {
            this.m_speechSubtitleSpeakerObj = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as GameObject;
            if !IsDefined(this.m_speechSubtitleSpeakerObj) {
                return;
            }
        }
        let pageDur: Float = (pageIndex < ArraySize(this.m_speechSubtitlePageDurs)) ? this.m_speechSubtitlePageDurs[pageIndex] : 3.00;
        let isLastPage: Bool = (pageIndex + 1) >= ArraySize(this.m_speechSubtitlePages);
        let schedDelay: Float = isLastPage ? MaxF(0.25, pageDur + 0.06) : MaxF(0.25, pageDur);

        this.m_speechSubCurrentPageIdx = pageIndex;
        if this.m_pausedByUiMenu {
            this.m_speechSubRemaining = schedDelay;
            this.m_speechSubExpectedDur = schedDelay;
            return;
        }

        this.m_speechSubtitleSeq += 1ul;
        this.m_activeSpeechSubtitleCruid = CreateCRUID(8899100000ul + this.m_speechSubtitleSeq);
        this.m_hasActiveSpeechSubtitle = true;
        this.EmitSpeechSubtitleDialogLine(this.m_activeSpeechSubtitleCruid, this.m_speechSubtitlePages[pageIndex], pageDur);

        let subCb: ref<ChispaSpeechSubtitleCallback> = new ChispaSpeechSubtitleCallback();
        subCb.system = this;
        subCb.token = token;
        subCb.nextPageIndex = pageIndex + 1;
        this.m_speechSubExpectedDur = schedDelay;
        this.m_speechSubScheduledEngineAt = EngineTime.ToFloat(GameInstance.GetEngineTime(game));
        this.m_speechSubRemaining = schedDelay;
        this.m_speechSubDelayId = GameInstance.GetDelaySystem(game).DelayCallback(subCb, schedDelay, false);
    }

    private final func PauseActiveSpeechForUiMenu() -> Void {
        if !this.m_isPlayingDialogueSequence {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let ds: ref<DelaySystem> = GameInstance.GetDelaySystem(game);
        let nowEngine: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(game));

        if IsDefined(ds) && NotEquals(this.m_speechSeqDelayId, GetInvalidDelayID()) {
            let remSeq: Float = ds.GetRemainingDelayTime(this.m_speechSeqDelayId);
            if remSeq <= 0.02 && this.m_speechSeqExpectedDur > 0.00 {
                let elapsedSeq: Float = MaxF(0.00, nowEngine - this.m_speechSeqScheduledEngineAt);
                remSeq = this.m_speechSeqExpectedDur - elapsedSeq;
            }
            ds.CancelCallback(this.m_speechSeqDelayId);
            this.m_speechSeqDelayId = GetInvalidDelayID();
            this.m_speechSeqRemaining = MaxF(0.10, remSeq);
        }

        if IsDefined(ds) && NotEquals(this.m_speechSubDelayId, GetInvalidDelayID()) {
            let remSub: Float = ds.GetRemainingDelayTime(this.m_speechSubDelayId);
            if remSub <= 0.02 && this.m_speechSubExpectedDur > 0.00 {
                let elapsedSub: Float = MaxF(0.00, nowEngine - this.m_speechSubScheduledEngineAt);
                remSub = this.m_speechSubExpectedDur - elapsedSub;
            }
            ds.CancelCallback(this.m_speechSubDelayId);
            this.m_speechSubDelayId = GetInvalidDelayID();
            this.m_speechSubRemaining = MaxF(0.18, remSub);
        }

        this.HideCurrentSpeechSubtitleElementOnly();
    }

    private final func ResumeActiveSpeechFromUiMenu() -> Void {
        if !this.m_isPlayingDialogueSequence {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let ds: ref<DelaySystem> = GameInstance.GetDelaySystem(game);
        let nowEngine: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(game));

        if this.m_speechSubCurrentPageIdx >= 0
            && this.m_speechSubCurrentPageIdx < ArraySize(this.m_speechSubtitlePages)
            && this.m_speechSubRemaining > 0.05 {
            this.HideCurrentSpeechSubtitleElementOnly();
            this.m_speechSubtitleSeq += 1ul;
            this.m_activeSpeechSubtitleCruid = CreateCRUID(8899100000ul + this.m_speechSubtitleSeq);
            this.m_hasActiveSpeechSubtitle = true;
            this.EmitSpeechSubtitleDialogLine(
                this.m_activeSpeechSubtitleCruid,
                this.m_speechSubtitlePages[this.m_speechSubCurrentPageIdx],
                this.m_speechSubRemaining
            );

            if IsDefined(ds) {
                let reassertCb: ref<ChispaSpeechSubtitleReassertCallback> = new ChispaSpeechSubtitleReassertCallback();
                reassertCb.system = this;
                reassertCb.token = this.m_speechSubtitleToken;
                reassertCb.expectedCruid = this.m_activeSpeechSubtitleCruid;
                ds.DelayCallback(reassertCb, 0.10, false);

                if Equals(this.m_speechSubDelayId, GetInvalidDelayID()) {
                    let subCb: ref<ChispaSpeechSubtitleCallback> = new ChispaSpeechSubtitleCallback();
                    subCb.system = this;
                    subCb.token = this.m_speechSubtitleToken;
                    subCb.nextPageIndex = this.m_speechSubCurrentPageIdx + 1;
                    this.m_speechSubExpectedDur = this.m_speechSubRemaining;
                    this.m_speechSubScheduledEngineAt = nowEngine;
                    this.m_speechSubDelayId = ds.DelayCallback(subCb, this.m_speechSubRemaining, false);
                }
            }
        }

        if IsDefined(ds) && this.m_speechSeqRemaining > 0.05 && Equals(this.m_speechSeqDelayId, GetInvalidDelayID()) {
            let seqCb: ref<ChispaSequenceCallback> = new ChispaSequenceCallback();
            seqCb.system = this;
            seqCb.token = this.m_speechToken;
            seqCb.nextIndex = this.m_currentSpeechIndex + 1;
            this.m_speechSeqExpectedDur = this.m_speechSeqRemaining;
            this.m_speechSeqScheduledEngineAt = nowEngine;
            this.m_speechSeqDelayId = ds.DelayCallback(seqCb, this.m_speechSeqRemaining, false);
        }

        if this.m_speechAllowManualSkip && !this.IsPhoneOverlayOpen() {
            this.SetSkipSpeechHintVisible(true);
        }
    }

    protected cb func OnUiMenuChanged(inMenu: Bool) -> Bool {
        if Equals(this.m_pausedByUiMenu, inMenu) {
            return true;
        }
        this.m_pausedByUiMenu = inMenu;
        if inMenu {
            this.PauseActiveSpeechForUiMenu();
        } else {
            this.ResumeActiveSpeechFromUiMenu();
            if IsDefined(this.m_live) {
                this.m_live.OnUiMenuExited();
            }
        }
        return true;
    }

    private final func ShowSpeechStepSubtitle(step: ref<ChispaSpeechStep>, speakerEntity: EntityID, resolvedSpeaker: CName, player: ref<PlayerPuppet>, duration: Float) -> Void {
        this.HideActiveSpeechStepSubtitle();
        let subText: String = this.ResolveSpeechSubtitleText(step.eventName);
        if Equals(subText, "") {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let speakerObj: wref<GameObject> = EntityID.IsDefined(speakerEntity)
            ? (GameInstance.FindEntityByID(game, speakerEntity) as GameObject)
            : null;
        if !IsDefined(speakerObj) {
            speakerObj = player;
        }
        if !IsDefined(speakerObj) {
            return;
        }

        let pages: array<String> = this.PaginateSubtitleText(subText, 148);
        let count: Int32 = ArraySize(pages);
        if count == 0 {
            return;
        }

        let totalDur: Float = MaxF(0.60, duration);
        let durs: array<Float>;
        if count == 1 {
            ArrayPush(durs, totalDur);
        } else {
            let totalChars: Int32 = 0;
            let k: Int32 = 0;
            while k < count {
                totalChars += Max(1, UTF8StrLen(pages[k]));
                k += 1;
            }
            let elapsed: Float = 0.00;
            k = 0;
            while k < count - 1 {
                let share: Float = totalDur * (Cast<Float>(Max(1, UTF8StrLen(pages[k]))) / Cast<Float>(Max(1, totalChars)));
                let clamped: Float = MaxF(1.00, MinF(share, totalDur - elapsed - Cast<Float>(count - 1 - k) * 0.90));
                ArrayPush(durs, clamped);
                elapsed += clamped;
                k += 1;
            }
            ArrayPush(durs, MaxF(0.90, totalDur - elapsed));
        }

        this.m_speechSubtitlePages = pages;
        this.m_speechSubtitlePageDurs = durs;
        this.m_speechSubtitleSpeakerObj = speakerObj;
        this.m_speechSubtitleSpeakerName = NameToString(resolvedSpeaker);
        this.m_speechSubtitleLineType = (Equals(step.lineType, scnDialogLineType.None) || Equals(step.lineType, scnDialogLineType.Invisible))
            ? scnDialogLineType.Regular
            : step.lineType;

        this.AdvanceSpeechSubtitlePage(this.m_speechSubtitleToken, 0);
    }

    private final func StopCurrentSpeechAudio() -> Void {
        this.CancelSpeechSequenceTimer();
        this.HideActiveSpeechStepSubtitle();
        if !IsNameValid(this.m_currentPlayingEvent) || Equals(this.m_currentPlayingEvent, n"None") {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let prevEvt: CName = this.m_currentPlayingEvent;
        ChispaAudioBridge.StopSpeech(game, this.m_currentPlayingBackend, prevEvt, this.m_currentPlayingVariant, this.m_currentPlayingEntity, this.m_currentPlayingSpeaker);
        this.ClearCurrentSpeechTracking();
    }

    private final func SetSkipSpeechHintVisible(show: Bool) -> Void {
        if Equals(this.m_skipHintVisible, show) {
            return;
        }
        this.m_skipHintVisible = show;
        let data: InputHintData;
        data.action = n"Choice1";
        data.source = n"ChispaNC";
        data.localizedLabel = this.GetLoc(n"ch_hint_skip_line", "Skip line");
        data.queuePriority = 10;
        data.sortingPriority = 10;
        SendInputHintData(this.GetGameInstance(), show, data);
    }

    private final func IsFaceToFaceSpeechAction(actionId: Int32) -> Bool {
        return actionId == 109
            || actionId == 110
            || actionId == 111
            || actionId == 112
            || actionId == 120
            || actionId == 209
            || actionId == 210
            || actionId == 211
            || actionId == 212
            || actionId == 220
            || actionId == 309
            || actionId == 310
            || actionId == 311
            || actionId == 312
            || actionId == 320
            || actionId == 409
            || actionId == 410
            || actionId == 411
            || actionId == 412
            || actionId == 420
            || actionId == 509
            || actionId == 510
            || actionId == 511
            || actionId == 512
            || actionId == 520
            || actionId == 609
            || actionId == 610
            || actionId == 611
            || actionId == 612
            || actionId == 621
            || actionId == 622
            || actionId == 623;
    }

    private final func IsHubRevealSpeechAction(actionId: Int32) -> Bool {
        return actionId == 109
            || actionId == 110
            || actionId == 111
            || actionId == 112
            || actionId == 209
            || actionId == 210
            || actionId == 211
            || actionId == 212
            || actionId == 309
            || actionId == 310
            || actionId == 311
            || actionId == 312
            || actionId == 409
            || actionId == 410
            || actionId == 411
            || actionId == 412
            || actionId == 509
            || actionId == 510
            || actionId == 511
            || actionId == 512
            || actionId == 609
            || actionId == 610
            || actionId == 611
            || actionId == 612;
    }

    public final func IsSkippableSpeechPlaying() -> Bool {
        return this.m_isPlayingDialogueSequence && this.m_speechAllowManualSkip && !this.m_dialogActive;
    }

    public final func IsSpeechBlockingWorldInteraction() -> Bool {
        return this.m_isPlayingDialogueSequence && this.m_speechActionOnComplete != 0;
    }

    public final func InterruptAmbientFieldSpeech() -> Void {
        if !this.m_isPlayingDialogueSequence || this.m_speechActionOnComplete != 0 {
            return;
        }
        this.m_speechToken += 1;
        this.StopCurrentSpeechAudio();
        this.StopNpcLipSync();
        this.SetSkipSpeechHintVisible(false);
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
    }

    public final func SkipCurrentSpeechStep() -> Bool {
        if !this.m_isPlayingDialogueSequence || !this.m_speechAllowManualSkip {
            return false;
        }
        let game: GameInstance = this.GetGameInstance();
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        if now - this.m_speechStepStartedAt < 0.45 {
            return true;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            GameObject.PlaySoundEvent(player, n"ui_menu_hover");
        }
        this.StopCurrentSpeechAudio();
        this.StopNpcLipSync();
        this.m_speechToken += 1;
        let nextIdx: Int32 = this.m_currentSpeechIndex + 1;
        this.AdvanceSpeechSequence(this.m_speechToken, nextIdx);
        return true;
    }

    private final func ResolveSpeakerEntityID(speakerTag: CName, player: ref<PlayerPuppet>) -> EntityID {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if IsDefined(des) && NotEquals(speakerTag, n"player") && NotEquals(speakerTag, n"phone") {
            let taggedId: EntityID = des.GetTaggedID(speakerTag);
            if EntityID.IsDefined(taggedId) && des.IsSpawned(taggedId) {
                return taggedId;
            }
        }
        return player.GetEntityID();
    }

    public final func MakeSpeechStep(eventName: CName, speakerTag: CName, speakerName: CName, lineType: scnDialogLineType, fallbackDur: Float) -> ref<ChispaSpeechStep> {
        let step: ref<ChispaSpeechStep> = new ChispaSpeechStep();
        step.eventName = eventName;
        step.speakerTag = speakerTag;
        step.speakerName = speakerName;
        step.lineType = lineType;
        step.fallbackDuration = fallbackDur;
        return step;
    }

    private final func SequenceHasPhoneSpeaker(steps: array<ref<ChispaSpeechStep>>) -> Bool {
        for step in steps {
            if Equals(step.speakerTag, n"phone") {
                return true;
            }
        }
        return false;
    }

    public final func IsDirectHoloFeedOpenInternal() -> Bool {
        return this.m_directHoloFeedOpen;
    }

    public final func SetHoloAvatarController(ctrl: wref<HudPhoneAvatarController>) -> Void {
        this.m_holoAvatarCtrl = ctrl;
    }

    public final func RefreshHoloStatusLabel() -> Void {
        if IsDefined(this.m_holoAvatarCtrl) {
            this.m_holoAvatarCtrl.ChispaRefreshLiveStatus();
        }
    }

    public final func GetLiveHoloSubtitleStatus() -> String {
        if IsDefined(this.m_live) {
            return this.m_live.GetHoloSubtitleStatus();
        }
        return this.GetLoc(n"ch_holo_telemetry_sub", "DRILL SERGEANT // UNFILTERED");
    }

    public final func IsLiveCompanionSpeaking() -> Bool {
        return IsDefined(this.m_live) && this.m_live.IsSpeaking();
    }

    public final func IsKiroshiPromptOpen() -> Bool {
        return IsDefined(this.m_live) && this.m_live.IsPromptOpen();
    }

    public final func IsWaitingLiveReply() -> Bool {
        return IsDefined(this.m_live) && this.m_live.IsWaitingReply();
    }

    public final func IsLiveCompanionBusy() -> Bool {
        return IsDefined(this.m_live) && this.m_live.IsBusy();
    }

    public final func OpenKiroshiPrompt() -> Void {
        if IsDefined(this.m_live) {
            this.m_live.OpenPrompt();
        }
    }

    public final func ConfirmKiroshiPrompt() -> Void {
        if IsDefined(this.m_live) {
            this.m_live.ConfirmPrompt();
        }
    }

    public final func SubmitTacticalFromKiroshiPrompt() -> Void {
        if IsDefined(this.m_live) {
            this.m_live.SubmitTacticalFromPrompt();
        }
    }

    public final func RecallLastKiroshiPrompt() -> Void {
        if IsDefined(this.m_live) {
            this.m_live.RecallLastPrompt();
        }
    }

    public final func CancelKiroshiPrompt() -> Void {
        if IsDefined(this.m_live) {
            this.m_live.CancelPrompt();
        }
    }

    public final func OnNativePromptSubmitted(text: String) -> Void {
        if IsDefined(this.m_live) {
            this.m_live.OnPromptSubmitted(text);
        }
    }

    public final func OnKiroshiPromptClosed(submitted: Bool) -> Void {
        if IsDefined(this.m_live) {
            this.m_live.OnPromptClosed(submitted);
        }
    }

    public final func GetLastTypedLiveMessage() -> String {
        if IsDefined(this.m_live) {
            return this.m_live.GetLastTypedText();
        }
        return "";
    }

    public final func TriggerQuickTacticalRemark() -> Void {
        if IsDefined(this.m_live) {
            this.m_live.TriggerQuickTacticalRemark();
        }
    }

    public final func SetCetOverlayOpen(isOpen: Bool) -> Void {
        if IsDefined(this.m_live) {
            this.m_live.SetCetOverlayOpen(isOpen);
        }
    }

    public final func IsCetOverlayOpen() -> Bool {
        return IsDefined(this.m_live) && this.m_live.IsCetOverlayOpen();
    }

    public final func SetLiveDaemonOnline(online: Bool) -> Void {
        if IsDefined(this.m_live) {
            this.m_live.SetDaemonOnline(online);
        }
    }

    public final func IsLiveDaemonOnline() -> Bool {
        return IsDefined(this.m_live) && this.m_live.IsDaemonOnline();
    }

    public final func SetLiveVk186Acute(isAcute: Bool) -> Void {
        if IsDefined(this.m_live) {
            this.m_live.SetVk186IsAcute(isAcute);
        }
    }

    public final func IsLiveVk186Acute() -> Bool {
        return IsDefined(this.m_live) && this.m_live.IsVk186Acute();
    }

    public final func GetPendingLiveReqSeq() -> Int32 {
        if IsDefined(this.m_live) {
            return this.m_live.GetPendingReqSeq();
        }
        return 0;
    }

    public final func GetPendingLiveReqAction() -> String {
        if IsDefined(this.m_live) {
            return this.m_live.GetPendingReqAction();
        }
        return "";
    }

    public final func GetPendingLiveReqText() -> String {
        if IsDefined(this.m_live) {
            return this.m_live.GetPendingReqText();
        }
        return "";
    }

    public final func ExportLiveStateJson() -> String {
        if IsDefined(this.m_live) {
            return this.m_live.BuildTelemetryJson();
        }
        return "{\"session_ready\":false,\"full_gameplay\":false,\"in_menu\":true,\"blocking_scene_or_call\":true}";
    }

    public final func PushLiveCompanionSubtitle(stateCode: Int32, subtitleText: String, durationSec: Float) -> Void {
        if IsDefined(this.m_live) {
            this.m_live.OnPacket(stateCode, subtitleText, durationSec);
        }
    }

    public final func OpenDirectHoloFeed() -> Void {
        if !this.IsVideocallModeEnabled() || this.IsControllingDevice() || this.IsExternalPhoneCallBusy() {
            return;
        }
        if this.m_callHudQueuedOrOpen && this.m_activeCallIsVideo && Equals(this.m_activeCallContact, n"chispa_ai") {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        if IsDefined(jm) {
            let cEntry: wref<JournalEntry> = jm.GetEntryByString("contacts/chispa_ai", "gameJournalContact");
            if IsDefined(cEntry) && NotEquals(jm.GetEntryState(cEntry), gameJournalEntryState.Active) {
                jm.ChangeEntryState("contacts/chispa_ai", "gameJournalContact", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
            }
        }
        this.m_directHoloFeedOpen = true;
        this.m_callHudQueuedOrOpen = true;
        this.m_activeCallContact = n"chispa_ai";
        this.m_activeCallIsVideo = true;
        this.m_activeCallPendingPickup = false;

        let startReq: ref<questTriggerCallRequest> = new questTriggerCallRequest();
        startReq.caller = n"chispa_ai";
        startReq.addressee = n"player";
        startReq.callMode = questPhoneCallMode.Video;
        startReq.callPhase = questPhoneCallPhase.StartCall;
        startReq.isPlayerTriggered = false;
        startReq.isRejectable = false;
        startReq.showAvatar = true;
        startReq.visuals = questPhoneCallVisuals.Default;
        GameInstance.GetScriptableSystemsContainer(game).QueueRequest(startReq);
    }

    public final func CloseDirectHoloFeed() -> Void {
        if !this.m_directHoloFeedOpen {
            return;
        }
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = false;
        if !this.m_activeCallPendingPickup && !this.IsExternalPhoneCallBusy() {
            this.EndCustomCall(n"chispa_ai", true);
        } else {
            this.m_activeCallIsVideo = false;
            this.m_activeCallContact = n"None";
        }
    }

    private final func CloseActiveChispaCallHud() -> Void {
        let hadChispaCall: Bool = this.m_directHoloFeedOpen
            || this.m_callHudQueuedOrOpen
            || this.m_activeCallPendingPickup
            || Equals(this.m_activeCallContact, n"chispa_ai");
        let wasVideo: Bool = this.m_activeCallIsVideo || this.m_directHoloFeedOpen;
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = false;
        this.m_activeCallPendingPickup = false;
        this.m_activeCallIsVideo = false;
        this.m_activeCallContact = n"None";
        if hadChispaCall && !this.IsExternalPhoneCallBusy() {
            this.EndCustomCall(n"chispa_ai", wasVideo);
        }
    }

    public final func StartSpeechSequence(steps: array<ref<ChispaSpeechStep>>, actionOnComplete: Int32) -> Void {
        this.SyncAudiowareEngineState(false);
        if this.IsLiveCompanionBusy() {
            this.m_live.ForceAbortForScriptedScene();
        }
        this.m_speechToken += 1;
        this.m_speechSteps = steps;
        this.m_speechActionOnComplete = actionOnComplete;
        this.m_isPlayingDialogueSequence = true;
        this.m_speechAllowManualSkip = this.IsFaceToFaceSpeechAction(actionOnComplete);
        this.StopCurrentSpeechAudio();
        this.StopNpcLipSync();
        if !this.m_speechAllowManualSkip {
            this.SetSkipSpeechHintVisible(false);
        }
        this.HideDialogChoices();
        if actionOnComplete != 0 {
            this.HideWorldInteraction();
        }
        if this.SequenceHasPhoneSpeaker(steps) && !this.m_activeCallPendingPickup {
            this.OpenDirectHoloFeed();
        } else if this.m_directHoloFeedOpen && !this.IsAnyEpisodeInFinalTalkStage() && !this.IsLiveCompanionBusy() {
            this.CloseDirectHoloFeed();
        }
        this.AdvanceSpeechSequence(this.m_speechToken, 0);
    }

    public final func AdvanceSpeechSequence(token: Int32, index: Int32) -> Void {
        if token != this.m_speechToken {
            return;
        }
        this.m_speechSeqDelayId = GetInvalidDelayID();
        this.m_speechSeqRemaining = 0.00;
        this.m_speechSeqExpectedDur = 0.00;
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            this.StopCurrentSpeechAudio();
            this.StopNpcLipSync();
            this.SetSkipSpeechHintVisible(false);
            this.m_isPlayingDialogueSequence = false;
            this.m_speechAllowManualSkip = false;
            return;
        }

        if index >= ArraySize(this.m_speechSteps) {
            this.ClearCurrentSpeechTracking();
            this.StopNpcLipSync();
            this.SetSkipSpeechHintVisible(false);
            this.m_isPlayingDialogueSequence = false;
            this.m_speechAllowManualSkip = false;
            if this.m_speechActionOnComplete >= 600 {
                if IsDefined(this.m_ep05) {
                    this.m_ep05.OnPostSpeech(this.m_speechActionOnComplete);
                }
            } else if this.m_speechActionOnComplete >= 500 {
                if IsDefined(this.m_ep04) {
                    this.m_ep04.OnPostSpeech(this.m_speechActionOnComplete);
                }
            } else if this.m_speechActionOnComplete >= 400 {
                if IsDefined(this.m_ep03) {
                    this.m_ep03.OnPostSpeech(this.m_speechActionOnComplete);
                }
            } else if this.m_speechActionOnComplete >= 300 {
                if IsDefined(this.m_ep02) {
                    this.m_ep02.OnPostSpeech(this.m_speechActionOnComplete);
                }
            } else if this.m_speechActionOnComplete >= 200 {
                if IsDefined(this.m_ep01) {
                    this.m_ep01.OnPostSpeech(this.m_speechActionOnComplete);
                }
            } else if IsDefined(this.m_ep00) {
                this.m_ep00.OnPostSpeech(this.m_speechActionOnComplete);
            }
            if this.m_directHoloFeedOpen && !this.IsAnyEpisodeInFinalTalkStage() && !this.IsLiveCompanionBusy() {
                this.CloseDirectHoloFeed();
            }
            return;
        }

        let step: ref<ChispaSpeechStep> = this.m_speechSteps[index];
        let speakerEntity: EntityID = this.ResolveSpeakerEntityID(step.speakerTag, player);
        let resolvedSpeaker: CName = step.speakerName;
        if Equals(step.speakerName, n"CHISPA") {
            resolvedSpeaker = Equals(this.GetLoc(n"ch_speaker_chispa", "SPARKY"), "SPARKY") ? n"SPARKY" : n"CHISPA";
        }

        this.StopCurrentSpeechAudio();
        this.m_currentSpeechIndex = index;
        this.m_speechStepStartedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        this.m_currentPlayingEvent = step.eventName;
        this.m_currentPlayingEntity = speakerEntity;
        this.m_currentPlayingSpeaker = resolvedSpeaker;

        let playedVariant: CName = n"None";
        let backendUsed: Int32 = ChispaAudioBridge.PlaySpeech(game, step.eventName, speakerEntity, resolvedSpeaker, player, playedVariant);
        this.m_currentPlayingBackend = backendUsed;
        this.m_currentPlayingVariant = playedVariant;
        this.SetSkipSpeechHintVisible(this.m_speechAllowManualSkip && !this.IsPhoneOverlayOpen());

        let dur: Float = ChispaAudioBridge.ResolveSpeechDuration(game, step.eventName, speakerEntity, backendUsed, playedVariant, step.fallbackDuration);
        this.ShowSpeechStepSubtitle(step, speakerEntity, resolvedSpeaker, player, dur);
        this.StartNpcLipSync(step.speakerTag, speakerEntity, dur);

        let waitDur: Float;
        if index + 1 < ArraySize(this.m_speechSteps) {
            waitDur = MaxF(0.20, dur + 0.08);
        } else if this.IsHubRevealSpeechAction(this.m_speechActionOnComplete) {
            waitDur = MaxF(0.20, dur - 0.16);
        } else {
            waitDur = MaxF(0.20, dur + 0.04);
        }
        if this.m_pausedByUiMenu {
            this.m_speechSeqRemaining = waitDur;
            this.m_speechSeqExpectedDur = waitDur;
            return;
        }
        let cb: ref<ChispaSequenceCallback> = new ChispaSequenceCallback();
        cb.system = this;
        cb.token = token;
        cb.nextIndex = index + 1;
        this.m_speechSeqExpectedDur = waitDur;
        this.m_speechSeqScheduledEngineAt = EngineTime.ToFloat(GameInstance.GetEngineTime(game));
        this.m_speechSeqRemaining = waitDur;
        this.m_speechSeqDelayId = GameInstance.GetDelaySystem(game).DelayCallback(cb, waitDur, false);
    }

    // --- Holollamadas y Videollamada Holográfica ---

    public final func StartCustomCall(contactName: CName, useVideo: Bool, stageTag: Int32) -> Void {
        let game: GameInstance = this.GetGameInstance();
        this.m_activeCallToken += 1;
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = false;
        this.m_activeCallContact = contactName;
        this.m_activeCallIsVideo = useVideo;
        this.m_activeCallPendingPickup = true;
        this.m_activeCallStageTag = stageTag;

        let req: ref<questTriggerCallRequest> = new questTriggerCallRequest();
        req.caller = contactName;
        req.addressee = n"player";
        req.callMode = useVideo ? questPhoneCallMode.Video : questPhoneCallMode.Audio;
        req.callPhase = questPhoneCallPhase.IncomingCall;
        req.isPlayerTriggered = false;
        req.isRejectable = false;
        req.showAvatar = true;
        req.visuals = questPhoneCallVisuals.Default;
        GameInstance.GetScriptableSystemsContainer(game).QueueRequest(req);

        let cb: ref<ChispaCallAnswerCallback> = new ChispaCallAnswerCallback();
        cb.system = this;
        cb.contactName = contactName;
        cb.callToken = this.m_activeCallToken;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, 12.00, false);
    }

    public final func OnCustomCallPickedUp(contactName: CName, shouldBeRejected: Bool) -> Void {
        if !this.m_activeCallPendingPickup || NotEquals(contactName, this.m_activeCallContact) {
            return;
        }
        this.AnswerIncomingCallInternal(contactName, this.m_activeCallToken, shouldBeRejected);
    }

    public final func AnswerIncomingCallInternal(contactName: CName, token: Int32, rejected: Bool) -> Void {
        if !this.m_activeCallPendingPickup || token != this.m_activeCallToken || NotEquals(contactName, this.m_activeCallContact) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        if !rejected && this.IsInSystemOrPauseMenu() {
            let deferCb: ref<ChispaCallAnswerCallback> = new ChispaCallAnswerCallback();
            deferCb.system = this;
            deferCb.contactName = contactName;
            deferCb.callToken = token;
            GameInstance.GetDelaySystem(game).DelayCallback(deferCb, 1.50, false);
            return;
        }
        this.m_activeCallPendingPickup = false;

        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            GameObject.PlaySoundEvent(player, n"ui_phone_incoming_call_stop");
        }

        if rejected {
            this.EndCustomCall(contactName, this.m_activeCallIsVideo);
            if this.m_activeCallStageTag >= 50 {
                if IsDefined(this.m_ep05) {
                    this.m_ep05.OnCallRejected(this.m_activeCallStageTag);
                }
            } else if this.m_activeCallStageTag >= 40 {
                if IsDefined(this.m_ep04) {
                    this.m_ep04.OnCallRejected(this.m_activeCallStageTag);
                }
            } else if this.m_activeCallStageTag >= 30 {
                if IsDefined(this.m_ep03) {
                    this.m_ep03.OnCallRejected(this.m_activeCallStageTag);
                }
            } else if this.m_activeCallStageTag >= 20 {
                if IsDefined(this.m_ep02) {
                    this.m_ep02.OnCallRejected(this.m_activeCallStageTag);
                }
            } else if this.m_activeCallStageTag >= 10 {
                if IsDefined(this.m_ep01) {
                    this.m_ep01.OnCallRejected(this.m_activeCallStageTag);
                }
            } else if IsDefined(this.m_ep00) {
                this.m_ep00.OnCallRejected(this.m_activeCallStageTag);
            }
            return;
        }

        let startReq: ref<questTriggerCallRequest> = new questTriggerCallRequest();
        startReq.caller = contactName;
        startReq.addressee = n"player";
        startReq.callMode = this.m_activeCallIsVideo ? questPhoneCallMode.Video : questPhoneCallMode.Audio;
        startReq.callPhase = questPhoneCallPhase.StartCall;
        startReq.isPlayerTriggered = false;
        startReq.isRejectable = false;
        startReq.showAvatar = true;
        startReq.visuals = questPhoneCallVisuals.Default;
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = true;
        GameInstance.GetScriptableSystemsContainer(game).QueueRequest(startReq);

        let completeAction: Int32 = 0;
        let steps: array<ref<ChispaSpeechStep>>;
        if this.m_activeCallStageTag >= 50 {
            if IsDefined(this.m_ep05) {
                steps = this.m_ep05.GetCallSteps(this.m_activeCallStageTag, completeAction);
            }
        } else if this.m_activeCallStageTag >= 40 {
            if IsDefined(this.m_ep04) {
                steps = this.m_ep04.GetCallSteps(this.m_activeCallStageTag, completeAction);
            }
        } else if this.m_activeCallStageTag >= 30 {
            if IsDefined(this.m_ep03) {
                steps = this.m_ep03.GetCallSteps(this.m_activeCallStageTag, completeAction);
            }
        } else if this.m_activeCallStageTag >= 20 {
            if IsDefined(this.m_ep02) {
                steps = this.m_ep02.GetCallSteps(this.m_activeCallStageTag, completeAction);
            }
        } else if this.m_activeCallStageTag >= 10 {
            if IsDefined(this.m_ep01) {
                steps = this.m_ep01.GetCallSteps(this.m_activeCallStageTag, completeAction);
            }
        } else if IsDefined(this.m_ep00) {
            steps = this.m_ep00.GetCallSteps(this.m_activeCallStageTag, completeAction);
        }
        if ArraySize(steps) > 0 {
            if this.m_activeCallStageTag == 1 || this.m_activeCallStageTag == 11 || this.m_activeCallStageTag == 21 || this.m_activeCallStageTag == 31 || this.m_activeCallStageTag == 41 || this.m_activeCallStageTag == 51 {
                this.PlaySfx(n"ch_sfx_boot_jingle");
            }
            this.StartSpeechSequence(steps, completeAction);
        }
    }

    public final func EndCustomCall(contactName: CName, wasVideo: Bool) -> Void {
        let game: GameInstance = this.GetGameInstance();
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = false;
        this.m_activeCallPendingPickup = false;
        this.m_activeCallIsVideo = false;
        let endReq: ref<questTriggerCallRequest> = new questTriggerCallRequest();
        endReq.caller = contactName;
        endReq.addressee = n"player";
        endReq.callMode = wasVideo ? questPhoneCallMode.Video : questPhoneCallMode.Audio;
        endReq.callPhase = questPhoneCallPhase.EndCall;
        endReq.isPlayerTriggered = false;
        endReq.isRejectable = false;
        endReq.showAvatar = true;
        endReq.visuals = questPhoneCallVisuals.Default;
        GameInstance.GetScriptableSystemsContainer(game).QueueRequest(endReq);
        this.m_activeCallContact = n"None";
    }

    public final func OnDelayedSmsAction(actionId: Int32) -> Void {
        if actionId >= 50 {
            if IsDefined(this.m_ep05) {
                this.m_ep05.OnDelayedSmsAction(actionId);
            }
        } else if actionId >= 40 {
            if IsDefined(this.m_ep04) {
                this.m_ep04.OnDelayedSmsAction(actionId);
            }
        } else if actionId >= 30 {
            if IsDefined(this.m_ep03) {
                this.m_ep03.OnDelayedSmsAction(actionId);
            }
        } else if actionId >= 20 {
            if IsDefined(this.m_ep02) {
                this.m_ep02.OnDelayedSmsAction(actionId);
            }
        } else if actionId >= 10 {
            if IsDefined(this.m_ep01) {
                this.m_ep01.OnDelayedSmsAction(actionId);
            }
        } else if IsDefined(this.m_ep00) {
            this.m_ep00.OnDelayedSmsAction(actionId);
        }
    }

    // --- Marcadores Amarillos y Ruta GPS Automática (Patrón #1) ---

    public final func TrackQuestObjective(objectivePath: String) -> Void {
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        if !IsDefined(jm) {
            return;
        }
        let objEntry: wref<JournalEntry> = jm.GetEntryByString(objectivePath, "gameJournalQuestObjective");
        if IsDefined(objEntry) {
            jm.TrackEntry(objEntry);
        }
    }

    public final func DeactivateJournalPinList(pinPaths: array<String>) -> Void {
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        if !IsDefined(jm) {
            return;
        }
        for pp in pinPaths {
            let pinEntry: wref<JournalEntry> = jm.GetEntryByString(pp, "gameJournalQuestMapPin");
            if IsDefined(pinEntry) && Equals(jm.GetEntryState(pinEntry), gameJournalEntryState.Active) {
                jm.ChangeEntryState(pp, "gameJournalQuestMapPin", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
            }
        }
    }

    public final func HasActiveJournalQuestMappin(objectivePath: String) -> Bool {
        if Equals(objectivePath, "") {
            return false;
        }
        let game: GameInstance = this.GetGameInstance();
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let ms: ref<MappinSystem> = GameInstance.GetMappinSystem(game);
        if !IsDefined(jm) || !IsDefined(ms) {
            return false;
        }
        let objEntry: wref<JournalEntry> = jm.GetEntryByString(objectivePath, "gameJournalQuestObjective");
        if !IsDefined(objEntry) {
            return false;
        }
        let positions: array<Vector3>;
        let hash: Uint32 = Cast<Uint32>(jm.GetEntryHash(objEntry));
        return ms.GetQuestMappinPositionsByObjective(hash, positions) && ArraySize(positions) > 0;
    }

    public final func ActivateObjectiveWithPin(
        stageTag: Int32,
        questPath: String,
        phasePath: String,
        objPath: String,
        pinPath: String,
        descPath: String,
        allPinPaths: array<String>,
        notifyObjective: Bool
    ) -> Void {
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        if !IsDefined(jm) || Equals(objPath, "") {
            return;
        }
        let qEntry: wref<JournalEntry> = jm.GetEntryByString(questPath, "gameJournalQuest");
        if IsDefined(qEntry) && NotEquals(jm.GetEntryState(qEntry), gameJournalEntryState.Active) {
            jm.ChangeEntryState(questPath, "gameJournalQuest", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        }
        let pEntry: wref<JournalEntry> = jm.GetEntryByString(phasePath, "gameJournalQuestPhase");
        if IsDefined(pEntry) && NotEquals(jm.GetEntryState(pEntry), gameJournalEntryState.Active) {
            jm.ChangeEntryState(phasePath, "gameJournalQuestPhase", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        }

        this.DeactivateJournalPinList(allPinPaths);

        if NotEquals(descPath, "") {
            jm.ChangeEntryState(descPath, "gameJournalQuestDescription", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        }

        let objEntry: wref<JournalEntry> = jm.GetEntryByString(objPath, "gameJournalQuestObjective");
        if IsDefined(objEntry) && Equals(jm.GetEntryState(objEntry), gameJournalEntryState.Active) {
            jm.ChangeEntryState(objPath, "gameJournalQuestObjective", gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
        }
        if NotEquals(pinPath, "") {
            jm.ChangeEntryState(pinPath, "gameJournalQuestMapPin", gameJournalEntryState.Active, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState(objPath, "gameJournalQuestObjective", gameJournalEntryState.Active, JournalNotifyOption.Notify);

        if notifyObjective || !IsDefined(jm.GetTrackedEntry()) || this.IsChispaQuestTrackedInJournal() {
            this.TrackQuestObjective(objPath);
        }
        if this.HasActiveJournalQuestMappin(objPath) {
            this.ClearMappin();
        }
        this.m_journalPinSyncedTag = stageTag;
        if notifyObjective {
            this.m_journalPinRetryTicks = 0;
        }
    }

    public final func SyncObjectivePinLoop(
        stageTag: Int32,
        questPath: String,
        phasePath: String,
        objPath: String,
        pinPath: String,
        allPinPaths: array<String>
    ) -> Void {
        if stageTag <= 0 || Equals(objPath, "") {
            if this.m_journalPinSyncedTag != 0 {
                this.DeactivateJournalPinList(allPinPaths);
                this.m_journalPinSyncedTag = 0;
                this.m_journalPinRetryTicks = 0;
            }
            return;
        }
        if this.m_journalPinSyncedTag != stageTag {
            this.m_journalPinRetryTicks = 0;
            this.ActivateObjectiveWithPin(stageTag, questPath, phasePath, objPath, pinPath, "", allPinPaths, false);
            return;
        }
        if !this.HasActiveJournalQuestMappin(objPath) && this.m_journalPinRetryTicks < 18 {
            this.m_journalPinRetryTicks += 1;
            if this.m_journalPinRetryTicks == 6 || this.m_journalPinRetryTicks == 15 {
                this.ActivateObjectiveWithPin(stageTag, questPath, phasePath, objPath, pinPath, "", allPinPaths, false);
            }
        }
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        if IsDefined(jm) && !IsDefined(jm.GetTrackedEntry()) {
            this.TrackQuestObjective(objPath);
        }
    }

    public final func UpdateFallbackMappin(
        stageTag: Int32,
        objPath: String,
        pinPos: Vector4,
        captionKey: CName,
        fallbackCaption: String
    ) -> Void {
        if this.HasActiveJournalQuestMappin(objPath) {
            this.ClearMappin();
            return;
        }
        let ms: ref<MappinSystem> = GameInstance.GetMappinSystem(this.GetGameInstance());
        if !IsDefined(ms) {
            return;
        }
        if this.m_hasMappin && this.m_mappinStageTag == stageTag {
            ms.SetMappinPosition(this.m_mappinId, pinPos);
            return;
        }
        this.ClearMappin();
        if stageTag >= 50 {
            this.m_mappinTitle = this.GetLoc(n"ch_quest_ep05_title", "SPARKY Protocol: Beyond the Blackwall");
        } else if stageTag >= 40 {
            this.m_mappinTitle = this.GetLoc(n"ch_quest_ep04_title", "SPARKY Protocol: Honor, Scrap & Cardboard Patriots");
        } else if stageTag >= 30 {
            this.m_mappinTitle = this.GetLoc(n"ch_quest_ep03_title", "SPARKY Protocol: Bullets That Bend Corners");
        } else if stageTag >= 20 {
            this.m_mappinTitle = this.GetLoc(n"ch_quest_ep02_title", "SPARKY Protocol: More Chrome Than Meat");
        } else if stageTag >= 10 {
            this.m_mappinTitle = this.GetLoc(n"ch_quest_ep01_title", "SPARKY Protocol: Ghosts in the Camera");
        } else {
            this.m_mappinTitle = this.GetLoc(n"ch_quest_title", "SPARKY Protocol: Welcome to Night City");
        }
        this.m_mappinDesc = this.GetLoc(captionKey, fallbackCaption);

        let data: MappinData;
        data.mappinType = t"Mappins.ChispaQuestMappin";
        data.variant = gamedataMappinVariant.DefaultQuestVariant;
        data.active = true;
        data.visibleThroughWalls = true;
        data.debugCaption = this.m_mappinDesc;
        this.m_mappinId = ms.RegisterMappin(data, pinPos);
        this.m_hasMappin = true;
        this.m_mappinStageTag = stageTag;
    }

    public final func ClearMappin() -> Void {
        this.m_activeMapPinCtrl = null;
        if !this.m_hasMappin {
            return;
        }
        let ms: ref<MappinSystem> = GameInstance.GetMappinSystem(this.GetGameInstance());
        if IsDefined(ms) {
            if Equals(ms.GetManuallyTrackedMappinID(), this.m_mappinId) {
                ms.UntrackMappin();
            }
            ms.UnregisterMappin(this.m_mappinId);
        }
        this.m_hasMappin = false;
        this.m_mappinStageTag = -1;
    }

    public final func IsChispaMappin(mappin: wref<IMappin>) -> Bool {
        return this.m_hasMappin && IsDefined(mappin) && Equals(mappin.GetNewMappinID(), this.m_mappinId);
    }

    public final func GetMappinTitle() -> String {
        return this.m_mappinTitle;
    }

    public final func GetMappinDesc() -> String {
        return this.m_mappinDesc;
    }

    private final func IsChispaQuestTrackedInJournal() -> Bool {
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(this.GetGameInstance());
        if !IsDefined(jm) {
            return false;
        }
        let tracked: wref<JournalEntry> = jm.GetTrackedEntry();
        if !IsDefined(tracked) {
            return true;
        }
        let tid: String = tracked.GetId();
        return Equals(tid, "01_answer_sms")
            || Equals(tid, "02_clear_alley")
            || Equals(tid, "03_claim_chispa")
            || Equals(tid, "04_talk_chispa")
            || Equals(tid, "01_ep01_sms")
            || Equals(tid, "02_ep01_infiltrate")
            || Equals(tid, "03_ep01_extract")
            || Equals(tid, "04_ep01_talk")
            || Equals(tid, "01_ep02_sms")
            || Equals(tid, "02_ep02_clear")
            || Equals(tid, "03_ep02_extract")
            || Equals(tid, "04_ep02_talk")
            || Equals(tid, "01_ep03_sms")
            || Equals(tid, "02_ep03_clear")
            || Equals(tid, "03_ep03_extract")
            || Equals(tid, "04_ep03_talk")
            || Equals(tid, "01_ep04_sms")
            || Equals(tid, "02_ep04_clear")
            || Equals(tid, "03_ep04_extract")
            || Equals(tid, "04_ep04_talk")
            || Equals(tid, "01_ep05_sms")
            || Equals(tid, "02_ep05_clear")
            || Equals(tid, "03_ep05_extract")
            || Equals(tid, "04_ep05_talk");
    }

    private final func ScheduleWorldMapAutoTrack() -> Void {
        let cb: ref<ChispaWorldMapTrackCallback> = new ChispaWorldMapTrackCallback();
        cb.system = this;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.05, false);
    }

    public final func SetActiveWorldMap(wm: wref<WorldMapMenuGameController>, ready: Bool) -> Void {
        this.m_activeWorldMap = wm;
        this.m_worldMapReady = ready;
        if !IsDefined(wm) {
            this.m_activeMapPinCtrl = null;
            return;
        }
        if ready && IsDefined(this.m_activeMapPinCtrl) {
            this.ScheduleWorldMapAutoTrack();
        }
    }

    public final func NotifyWorldMapMappinReady(ctrl: ref<BaseWorldMapMappinController>) -> Void {
        this.m_activeMapPinCtrl = ctrl;
        if this.m_worldMapReady && IsDefined(this.m_activeWorldMap) {
            this.ScheduleWorldMapAutoTrack();
        }
    }

    public final func OnDeferredWorldMapAutoTrack() -> Void {
        if IsDefined(this.m_activeWorldMap) && IsDefined(this.m_activeMapPinCtrl) && this.m_hasMappin && this.IsChispaQuestTrackedInJournal() {
            this.m_activeWorldMap.ChispaTryAutoTrack(this.m_activeMapPinCtrl);
        }
    }

    // --- Helpers de Entidades Dinámicas y Estáticas (Patrones #5, #6, #7) ---

    public final func IsDynamicEntityAliveOrSpawning(id: EntityID) -> Bool {
        if !EntityID.IsDefined(id) {
            return false;
        }
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || !des.IsManaged(id) {
            return false;
        }
        return des.IsSpawned(id) || des.IsSpawning(id);
    }

    public final func IsStaticPropAliveOrSpawning(id: EntityID) -> Bool {
        if !EntityID.IsDefined(id) {
            return false;
        }
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if !IsDefined(ses) || !ses.IsManaged(id) {
            return false;
        }
        return ses.IsSpawned(id) || ses.IsSpawning(id);
    }

    public final func SpawnDynamicNpc(recordId: TweakDBID, pos: Vector4, yaw: Float, tagName: CName) -> EntityID {
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || !des.IsReady() {
            return new EntityID();
        }
        let spec: ref<DynamicEntitySpec> = new DynamicEntitySpec();
        spec.recordID = recordId;
        spec.position = pos;
        let ang: EulerAngles;
        ang.Yaw = yaw;
        spec.orientation = EulerAngles.ToQuat(ang);
        spec.persistState = false;
        spec.persistSpawn = false;
        spec.alwaysSpawned = true;
        spec.spawnInView = true;
        spec.active = true;
        spec.tags = [n"ChispaNPC", tagName];
        return des.CreateEntity(spec);
    }

    public final func SpawnStaticProp(templatePath: ResRef, pos: Vector4, yaw: Float, tagName: CName) -> EntityID {
        return this.SpawnStaticPropEx(templatePath, n"", pos, 0.00, yaw, tagName);
    }

    public final func SpawnStaticPropEx(templatePath: ResRef, appearance: CName, pos: Vector4, pitch: Float, yaw: Float, tagName: CName) -> EntityID {
        let ses: ref<StaticEntitySystem> = GameInstance.GetStaticEntitySystem();
        if !IsDefined(ses) || !ses.IsReady() {
            return new EntityID();
        }
        let spec: ref<StaticEntitySpec> = new StaticEntitySpec();
        spec.templatePath = templatePath;
        if IsNameValid(appearance) && NotEquals(appearance, n"None") && NotEquals(appearance, n"") {
            spec.appearanceName = appearance;
        }
        spec.position = pos;
        let ang: EulerAngles;
        ang.Pitch = pitch;
        ang.Yaw = yaw;
        spec.orientation = EulerAngles.ToQuat(ang);
        spec.attached = true;
        spec.tags = [n"ChispaProp", tagName];
        return ses.SpawnEntity(spec);
    }

    public final func MakeNpcHostile(npc: ref<NPCPuppet>, player: ref<PlayerPuppet>) -> Void {
        if !IsDefined(npc) || !IsDefined(player) || npc.IsDead() {
            return;
        }
        NPCPuppet.ChangeHighLevelState(npc, gamedataNPCHighLevelState.Combat);
        let attAgent: ref<AttitudeAgent> = npc.GetAttitudeAgent();
        if IsDefined(attAgent) {
            attAgent.SetAttitudeGroup(n"hostile");
            attAgent.SetAttitudeTowards(player.GetAttitudeAgent(), EAIAttitude.AIA_Hostile);
        }
        let ttc: ref<TargetTrackerComponent> = npc.GetTargetTrackerComponent();
        if IsDefined(ttc) {
            ttc.AddThreat(player, true, player.GetWorldPosition(), 1.00, 12.00, false);
        }
        let reactComp: ref<ReactionManagerComponent> = npc.GetStimReactionComponent();
        if IsDefined(reactComp) {
            reactComp.TriggerCombat(player);
        }
    }

    public final func IsNpcNeutralized(id: EntityID, anchorPos: Vector4, combatElapsed: Float, opt allowFarOutOfCombat: Bool) -> Bool {
        if !EntityID.IsDefined(id) {
            return true;
        }
        let des: ref<DynamicEntitySystem> = GameInstance.GetDynamicEntitySystem();
        if !IsDefined(des) || !des.IsManaged(id) {
            return true;
        }
        if !des.IsSpawned(id) {
            if des.IsSpawning(id) && (combatElapsed <= 0.01 || combatElapsed < 6.00) {
                return false;
            }
            return combatElapsed > 0.01;
        }
        let npc: ref<NPCPuppet> = des.GetEntity(id) as NPCPuppet;
        if !IsDefined(npc) {
            return true;
        }
        if npc.IsDead()
            || ScriptedPuppet.IsDefeated(npc)
            || ScriptedPuppet.IsUnconscious(npc)
            || !ScriptedPuppet.IsActive(npc) {
            return true;
        }
        if combatElapsed >= 1.50
            && GameInstance.GetStatPoolsSystem(this.GetGameInstance()).GetStatPoolValue(Cast<StatsObjectID>(npc.GetEntityID()), gamedataStatPoolType.Health, true) <= 1.50 {
            return true;
        }
        let np: Vector4 = npc.GetWorldPosition();
        if AbsF(np.Z - anchorPos.Z) > 7.50 || this.ComputeDistanceSq(np, anchorPos) > 3025.00 {
            return true;
        }
        if allowFarOutOfCombat && this.ComputeDistanceSq(np, anchorPos) > 625.00 {
            return true;
        }
        return false;
    }

    private final func StopNpcLipSync() -> Void {
        this.m_lipSyncToken += 1;
        this.m_lipSyncRemaining = 0.00;
        this.m_lipSyncEntityId = new EntityID();
    }

    private final func StartNpcLipSync(speakerTag: CName, entityId: EntityID, duration: Float) -> Void {
        this.StopNpcLipSync();
        if Equals(speakerTag, n"player") || Equals(speakerTag, n"phone") || !EntityID.IsDefined(entityId) || duration <= 0.15 {
            return;
        }
        this.m_lipSyncToken += 1;
        this.m_lipSyncEntityId = entityId;
        this.m_lipSyncRemaining = duration;
        let cb: ref<ChispaLipSyncCallback> = new ChispaLipSyncCallback();
        cb.system = this;
        cb.token = this.m_lipSyncToken;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.11, false);
    }

    public final func OnLipSyncTick(token: Int32) -> Void {
        if token != this.m_lipSyncToken {
            return;
        }
        if !this.m_pausedByUiMenu {
            this.m_lipSyncRemaining -= 0.11;
            if this.m_lipSyncRemaining <= 0.08 {
                this.m_lipSyncEntityId = new EntityID();
                return;
            }
        }
        let cb: ref<ChispaLipSyncCallback> = new ChispaLipSyncCallback();
        cb.system = this;
        cb.token = token;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(cb, 0.11, false);
    }

    // --- Cuadros de Diálogo Nativos e Interacciones de Mundo (Patrones #2, #3) ---

    private final func IsOurDialogHubId(id: Int32) -> Bool {
        return id <= -774410 && id >= -774490;
    }

    private final func IsOurInteractionHubId(id: Int32) -> Bool {
        return id == -775501;
    }

    private final func NextDialogHubId() -> Int32 {
        this.m_dialogHubSeqId -= 1;
        if this.m_dialogHubSeqId < -774490 || this.m_dialogHubSeqId > -774410 {
            this.m_dialogHubSeqId = -774410;
        }
        return this.m_dialogHubSeqId;
    }

    public final func MakeDialogChoice(caption: String, isQuestYellow: Bool, disabled: Bool) -> ListChoiceData {
        let c: ListChoiceData;
        c.localizedName = caption;
        if disabled {
            ChoiceTypeWrapper.SetType(c.type, gameinteractionsChoiceType.Inactive);
        } else if isQuestYellow {
            ChoiceTypeWrapper.SetType(c.type, gameinteractionsChoiceType.QuestImportant);
        } else {
            ChoiceTypeWrapper.SetType(c.type, gameinteractionsChoiceType.Selected);
        }
        c.inputActionName = n"None";
        return c;
    }

    public final func PushDialogHub(ownerTag: CName, title: String, choices: array<ListChoiceData>, optionIds: array<Int32>) -> Void {
        let game: GameInstance = this.GetGameInstance();
        let uiBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIInteractions);
        if !IsDefined(uiBB) {
            return;
        }
        let hubDef: ref<UIInteractionsDef> = GetAllBlackboardDefs().UIInteractions;
        let existing: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(uiBB.GetVariant(hubDef.DialogChoiceHubs));
        if ArraySize(existing.choiceHubs) > 0 && !this.IsOurDialogHubId(existing.choiceHubs[0].id) {
            return;
        }
        if (Equals(ownerTag, n"chispa_ep00") || Equals(ownerTag, n"chispa_ep01") || Equals(ownerTag, n"chispa_ep02") || Equals(ownerTag, n"chispa_ep03") || Equals(ownerTag, n"chispa_ep04") || Equals(ownerTag, n"chispa_ep05"))
            && !this.IsPhoneOverlayOpen() {
            this.OpenDirectHoloFeed();
        }
        let curHubId: Int32 = this.m_dialogHubSeqId;
        let hasOurHub: Bool = ArraySize(existing.choiceHubs) > 0 && existing.choiceHubs[0].id == curHubId;
        let activeOk: Bool = uiBB.GetInt(hubDef.ActiveChoiceHubID) == curHubId;
        let visuallyOk: Bool = !IsDefined(this.m_dialogWidgetCtrl) || this.m_dialogWidgetCtrl.ChispaIsVisuallyOpen();
        if this.m_dialogActive && Equals(this.m_dialogOwnerTag, ownerTag) && this.m_dialogOptionCount == ArraySize(choices) && hasOurHub && activeOk && visuallyOk {
            return;
        }

        let hubId: Int32 = this.NextDialogHubId();
        let hub: ListChoiceHubData;
        hub.id = hubId;
        hub.activityState = EVisualizerActivityState.Active;
        hub.flags = EVisualizerDefinitionFlags.None;
        hub.isPhoneLockActive = false;
        hub.title = title;
        hub.choices = choices;

        let container: DialogChoiceHubs;
        ArrayPush(container.choiceHubs, hub);

        let visInfo: VisualizersInfo;
        visInfo.activeVisId = hubId;
        ArrayPush(visInfo.visIds, hubId);

        let ownerOrCountChanged: Bool = !this.m_dialogActive || NotEquals(this.m_dialogOwnerTag, ownerTag) || this.m_dialogOptionCount != ArraySize(choices);
        if ownerOrCountChanged || !visuallyOk {
            this.m_dialogOpenedAt = EngineTime.ToFloat(GameInstance.GetSimTime(game));
            this.m_dialogConfirmArmed = false;
        }
        if ownerOrCountChanged {
            this.m_dialogSelectedIdx = 0;
        }
        this.m_dialogOptionIds = optionIds;
        this.m_dialogOptionCount = ArraySize(choices);
        if this.m_dialogSelectedIdx >= this.m_dialogOptionCount || this.m_dialogSelectedIdx < 0 {
            this.m_dialogSelectedIdx = 0;
        }
        this.m_dialogOwnerTag = ownerTag;
        this.m_dialogActive = true;

        uiBB.SetInt(hubDef.SelectedIndex, -1, false);
        uiBB.SetVariant(hubDef.DialogChoiceHubs, ToVariant(container), true);
        uiBB.SetInt(hubDef.ActiveChoiceHubID, hubId, true);
        uiBB.SetInt(hubDef.SelectedIndex, this.m_dialogSelectedIdx, true);
        uiBB.SetVariant(hubDef.VisualizersInfo, ToVariant(visInfo), true);

        if IsDefined(this.m_dialogWidgetCtrl) {
            this.m_dialogWidgetCtrl.ChispaSyncAndReveal(ToVariant(container), hubId, this.m_dialogSelectedIdx);
        }
    }

    public final func HideDialogChoices() -> Void {
        if !this.m_dialogActive {
            return;
        }
        this.m_dialogActive = false;
        this.m_dialogConfirmArmed = false;
        this.m_dialogOwnerTag = n"None";
        this.m_dialogOptionCount = 0;
        ArrayClear(this.m_dialogOptionIds);

        let uiBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
        if !IsDefined(uiBB) {
            return;
        }
        let hubDef: ref<UIInteractionsDef> = GetAllBlackboardDefs().UIInteractions;
        let existing: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(uiBB.GetVariant(hubDef.DialogChoiceHubs));
        let activeId: Int32 = uiBB.GetInt(hubDef.ActiveChoiceHubID);
        if (ArraySize(existing.choiceHubs) > 0 && this.IsOurDialogHubId(existing.choiceHubs[0].id)) || this.IsOurDialogHubId(activeId) {
            let empty: DialogChoiceHubs;
            let visInfo: VisualizersInfo;
            visInfo.activeVisId = -1;
            uiBB.SetVariant(hubDef.DialogChoiceHubs, ToVariant(empty), true);
            uiBB.SetInt(hubDef.ActiveChoiceHubID, -1, true);
            uiBB.SetInt(hubDef.SelectedIndex, -1, true);
            uiBB.SetVariant(hubDef.VisualizersInfo, ToVariant(visInfo), true);
        }
    }

    public final func SelectDialogChoiceIndex(idx: Int32) -> Bool {
        if !this.m_dialogActive || idx < 0 || idx >= this.m_dialogOptionCount {
            return false;
        }
        this.m_dialogSelectedIdx = idx;
        let uiBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
        if IsDefined(uiBB) {
            uiBB.SetInt(GetAllBlackboardDefs().UIInteractions.SelectedIndex, this.m_dialogSelectedIdx, true);
        }
        if IsDefined(this.m_dialogWidgetCtrl) {
            this.m_dialogWidgetCtrl.OnDialogsSelectIndex(this.m_dialogSelectedIdx);
            this.m_dialogWidgetCtrl.ChispaEnsureVisible();
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(this.GetGameInstance()).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            GameObject.PlaySoundEvent(player, n"ui_menu_hover");
        }
        return true;
    }

    public final func MoveDialogSelection(delta: Int32) -> Bool {
        if !this.m_dialogActive || this.m_dialogOptionCount <= 1 {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
        if now - this.m_lastDialogNavAt < 0.06 {
            return true;
        }
        this.m_lastDialogNavAt = now;
        let nextIdx: Int32 = this.m_dialogSelectedIdx + delta;
        if nextIdx < 0 {
            nextIdx = this.m_dialogOptionCount - 1;
        } else if nextIdx >= this.m_dialogOptionCount {
            nextIdx = 0;
        }
        return this.SelectDialogChoiceIndex(nextIdx);
    }

    private final func ReopenActiveDialogHub() -> Void {
        if IsDefined(this.m_ep00) && Equals(this.m_dialogOwnerTag, n"chispa_ep00") {
            this.m_ep00.ShowDialogHub();
        } else if IsDefined(this.m_ep01) && Equals(this.m_dialogOwnerTag, n"chispa_ep01") {
            this.m_ep01.ShowDialogHub();
        } else if IsDefined(this.m_ep02) && Equals(this.m_dialogOwnerTag, n"chispa_ep02") {
            this.m_ep02.ShowDialogHub();
        } else if IsDefined(this.m_ep03) && Equals(this.m_dialogOwnerTag, n"chispa_ep03") {
            this.m_ep03.ShowDialogHub();
        } else if IsDefined(this.m_ep04) && Equals(this.m_dialogOwnerTag, n"chispa_ep04") {
            this.m_ep04.ShowDialogHub();
        } else if IsDefined(this.m_ep05) && Equals(this.m_dialogOwnerTag, n"chispa_ep05") {
            this.m_ep05.ShowDialogHub();
        }
    }

    public final func OnDialogConfirmPressed() -> Void {
        if !this.m_dialogActive {
            return;
        }
        if IsDefined(this.m_dialogWidgetCtrl) && !this.m_dialogWidgetCtrl.ChispaIsVisuallyOpen() {
            this.ReopenActiveDialogHub();
            this.m_dialogConfirmArmed = false;
            return;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(this.GetGameInstance()));
        if now - this.m_dialogOpenedAt >= 0.12 {
            this.m_dialogConfirmArmed = true;
        }
    }

    public final func ConfirmSelectedDialogChoice() -> Bool {
        if !this.m_dialogActive || this.m_dialogSelectedIdx < 0 || this.m_dialogSelectedIdx >= ArraySize(this.m_dialogOptionIds) {
            return false;
        }
        let game: GameInstance = this.GetGameInstance();
        let now: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
        let uiBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIInteractions);
        let hasOurHub: Bool = false;
        if IsDefined(uiBB) {
            let hubDef: ref<UIInteractionsDef> = GetAllBlackboardDefs().UIInteractions;
            let existing: DialogChoiceHubs = FromVariant<DialogChoiceHubs>(uiBB.GetVariant(hubDef.DialogChoiceHubs));
            hasOurHub = ArraySize(existing.choiceHubs) > 0 && this.IsOurDialogHubId(existing.choiceHubs[0].id);
        }
        let visuallyOk: Bool = !IsDefined(this.m_dialogWidgetCtrl) || this.m_dialogWidgetCtrl.ChispaIsVisuallyOpen();
        if !hasOurHub || !visuallyOk {
            this.ReopenActiveDialogHub();
            this.m_dialogOpenedAt = now;
            this.m_dialogConfirmArmed = false;
            let pl: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
            if IsDefined(pl) {
                GameObject.PlaySoundEvent(pl, n"ui_menu_hover");
            }
            return true;
        }
        if !this.m_dialogConfirmArmed || now - this.m_dialogOpenedAt < 0.12 {
            return true;
        }
        this.m_dialogConfirmArmed = false;
        let ownerTag: CName = this.m_dialogOwnerTag;
        let optionId: Int32 = this.m_dialogOptionIds[this.m_dialogSelectedIdx];
        this.HideDialogChoices();
        if IsDefined(this.m_ep00) && Equals(ownerTag, n"chispa_ep00") {
            return this.m_ep00.HandleDialogOption(optionId);
        }
        if IsDefined(this.m_ep01) && Equals(ownerTag, n"chispa_ep01") {
            return this.m_ep01.HandleDialogOption(optionId);
        }
        if IsDefined(this.m_ep02) && Equals(ownerTag, n"chispa_ep02") {
            return this.m_ep02.HandleDialogOption(optionId);
        }
        if IsDefined(this.m_ep03) && Equals(ownerTag, n"chispa_ep03") {
            return this.m_ep03.HandleDialogOption(optionId);
        }
        if IsDefined(this.m_ep04) && Equals(ownerTag, n"chispa_ep04") {
            return this.m_ep04.HandleDialogOption(optionId);
        }
        if IsDefined(this.m_ep05) && Equals(ownerTag, n"chispa_ep05") {
            return this.m_ep05.HandleDialogOption(optionId);
        }
        return false;
    }

    public final func ShowWorldInteraction(kind: Int32, titleKey: CName, titleFallback: String, actionKey: CName, actionFallback: String, isTalkIcon: Bool, opt forceOverride: Bool) -> Void {
        let uiBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
        if !IsDefined(uiBB) {
            return;
        }
        let hubDef: ref<UIInteractionsDef> = GetAllBlackboardDefs().UIInteractions;
        let existing: InteractionChoiceHubData = FromVariant<InteractionChoiceHubData>(uiBB.GetVariant(hubDef.InteractionChoiceHub));
        if existing.active && !this.IsOurInteractionHubId(existing.id) && !forceOverride {
            this.m_interactionShown = false;
            return;
        }
        if this.m_interactionShown && existing.active && this.IsOurInteractionHubId(existing.id) && this.m_interactionKind == kind {
            return;
        }

        let choice: InteractionChoiceData;
        choice.inputAction = n"Choice1";
        choice.rawInputKey = EInputKey.IK_F;
        choice.isHoldAction = false;
        choice.localizedName = this.GetLoc(actionKey, actionFallback);
        ChoiceTypeWrapper.SetType(choice.type, gameinteractionsChoiceType.QuestImportant);
        let iconRecord: wref<ChoiceCaptionIconPart_Record>;
        if isTalkIcon {
            iconRecord = TweakDBInterface.GetChoiceCaptionIconPartRecord(t"ChoiceCaptionParts.TalkIcon");
        }
        if !IsDefined(iconRecord) {
            iconRecord = TweakDBInterface.GetChoiceCaptionIconPartRecord(t"ChoiceCaptionParts.UseIcon");
        }
        if IsDefined(iconRecord) {
            InteractionChoiceCaption.AddPartFromRecord(choice.captionParts, iconRecord);
        }

        let data: InteractionChoiceHubData;
        data.id = -775501;
        data.active = true;
        data.flags = EVisualizerDefinitionFlags.None;
        data.title = this.GetLoc(titleKey, titleFallback);
        ArrayPush(data.choices, choice);

        let visInfo: VisualizersInfo;
        visInfo.activeVisId = -775501;
        ArrayPush(visInfo.visIds, -775501);

        uiBB.SetVariant(hubDef.InteractionChoiceHub, ToVariant(data), true);
        uiBB.SetVariant(hubDef.VisualizersInfo, ToVariant(visInfo), true);
        this.m_interactionShown = true;
        this.m_interactionKind = kind;
    }

    public final func HideWorldInteraction() -> Void {
        if !this.m_interactionShown {
            return;
        }
        this.m_interactionShown = false;
        this.m_interactionKind = 0;
        let uiBB: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGameInstance()).Get(GetAllBlackboardDefs().UIInteractions);
        if !IsDefined(uiBB) {
            return;
        }
        let hubDef: ref<UIInteractionsDef> = GetAllBlackboardDefs().UIInteractions;
        let existing: InteractionChoiceHubData = FromVariant<InteractionChoiceHubData>(uiBB.GetVariant(hubDef.InteractionChoiceHub));
        if this.IsOurInteractionHubId(existing.id) {
            let empty: InteractionChoiceHubData;
            empty.id = -775501;
            empty.active = false;
            let visInfo: VisualizersInfo;
            visInfo.activeVisId = -1;
            uiBB.SetVariant(hubDef.InteractionChoiceHub, ToVariant(empty), true);
            uiBB.SetVariant(hubDef.VisualizersInfo, ToVariant(visInfo), true);
        }
    }

    public final func TryHandleWorldInteractionInput() -> Bool {
        if !this.m_interactionShown || this.m_interactionKind <= 0 || this.IsSpeechBlockingWorldInteraction() || this.IsUiBlockingWorldInput() {
            return false;
        }
        let kind: Int32 = this.m_interactionKind;
        this.HideWorldInteraction();
        this.InterruptAmbientFieldSpeech();
        if kind >= 60 && kind < 70 {
            if IsDefined(this.m_ep05) {
                return this.m_ep05.HandleInteraction(kind);
            }
            return false;
        }
        if kind >= 50 && kind < 60 {
            if IsDefined(this.m_ep04) {
                return this.m_ep04.HandleInteraction(kind);
            }
            return false;
        }
        if kind >= 40 && kind < 50 {
            if IsDefined(this.m_ep03) {
                return this.m_ep03.HandleInteraction(kind);
            }
            return false;
        }
        if kind >= 30 && kind < 40 {
            if IsDefined(this.m_ep02) {
                return this.m_ep02.HandleInteraction(kind);
            }
            return false;
        }
        if kind >= 20 && kind < 30 {
            if IsDefined(this.m_ep01) {
                return this.m_ep01.HandleInteraction(kind);
            }
            return false;
        }
        if IsDefined(this.m_ep00) {
            return this.m_ep00.HandleInteraction(kind);
        }
        return false;
    }

    // --- Desbloqueo Opcional, Controles CET y Bucle Principal ---

    public final func UnlockFullNightCityMap() -> Void {
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        qs.SetFact(n"watson_prolog_lock", 0);
        qs.SetFact(n"prolog_lock", 0);
        qs.SetFact(n"dbg_unlock_fast_travel", 1);
        qs.SetFact(n"fast_travel_tutorial", 1);
        qs.SetFact(n"tutorial_fast_travel", 1);
        let ftSys: ref<FastTravelSystem> = GameInstance.GetScriptableSystemsContainer(game).Get(n"FastTravelSystem") as FastTravelSystem;
        if IsDefined(ftSys) {
            ftSys.QueueRequest(new RemoveAllFastTravelLocksRequest());
        }
        this.ShowRelicBanner(n"ch_banner_dbg_unlock", "[SPARKY] Watson bridges & Fast Travel unlocked for testing");
    }

    public final func ReplayEp00Call() -> Void {
        if IsDefined(this.m_ep00) {
            this.m_ep00.ReplayCall();
        }
    }

    public final func TeleportToEp00Alley() -> Void {
        if IsDefined(this.m_ep00) {
            this.m_ep00.TeleportToAlley();
        }
    }

    public final func TriggerEp00CapacitorOverload() -> Void {
        if IsDefined(this.m_ep00) {
            this.m_ep00.TriggerCapacitorOverload();
        }
    }

    public final func StartEp01Directly() -> Void {
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(this.m_ep00) {
            this.m_ep00.CleanupEntities();
        }
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            this.DeactivateJournalPinList([
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/mp_ep00_alley",
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/mp_ep00_console"
            ]);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            if IsDefined(player) {
                let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Chispa_CoreDongle") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle"), 1);
                }
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Lexington_Chispa") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Lexington_Chispa"), 1);
                }
            }
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        this.ResetEp01Only();
        this.ShowRelicBanner(n"ch_banner_dbg_ep01", "[SPARKY] Episode 1 activated — Check your holophone in Kabuki");
    }

    public final func ReplayEp01Call() -> Void {
        if IsDefined(this.m_ep01) {
            this.m_ep01.ReplayCall();
        }
    }

    public final func TeleportToEp01Kabuki() -> Void {
        if IsDefined(this.m_ep01) {
            this.m_ep01.TeleportToKabuki();
        }
    }

    public final func TriggerEp01RelaySurge() -> Void {
        if IsDefined(this.m_ep01) {
            this.m_ep01.TriggerRelaySurge();
        }
    }

    public final func ResetEp01Only() -> Void {
        this.m_speechToken += 1;
        this.m_activeCallToken += 1;
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
        this.m_journalPinSyncedTag = -1;
        this.m_journalPinRetryTicks = 0;

        this.StopCurrentSpeechAudio();
        this.CloseActiveChispaCallHud();
        this.SetSkipSpeechHintVisible(false);
        this.StopNpcLipSync();
        this.HideDialogChoices();
        this.HideWorldInteraction();
        this.ClearMappin();
        this.ClearSmartBridge();
        this.ClearRicochetBridge();
        this.ClearCoprocessorRamBridge();
        if IsDefined(this.m_ep01) {
            this.m_ep01.CleanupEntities();
            this.m_ep01.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep02) {
            this.m_ep02.CleanupEntities();
            this.m_ep02.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep03) {
            this.m_ep03.CleanupEntities();
            this.m_ep03.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep04) {
            this.m_ep04.CleanupEntities();
            this.m_ep04.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep05) {
            this.m_ep05.CleanupEntities();
            this.m_ep05.ResetJournalAndFacts();
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        qs.SetFact(n"chispa_season_stage", 100);
        this.m_sessionReadyTicks = 12;
        this.ScheduleTick(0.40);
    }

    public final func StartEp02Directly() -> Void {
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(this.m_ep00) {
            this.m_ep00.CleanupEntities();
        }
        if IsDefined(this.m_ep01) {
            this.m_ep01.CleanupEntities();
        }
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            this.DeactivateJournalPinList([
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/mp_ep00_alley",
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/mp_ep00_console"
            ]);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            if IsDefined(player) {
                let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Chispa_CoreDongle") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle"), 1);
                }
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Lexington_Chispa") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Lexington_Chispa"), 1);
                }
            }
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        if qs.GetFact(n"chispa_ep01_done") == 0 {
            this.DeactivateJournalPinList([
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/mp_ep01_kabuki",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/mp_ep01_terminal"
            ]);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            if IsDefined(player) {
                let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Chispa_MemorySector01") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector01"), 1);
                }
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Saratoga_Chispa") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Saratoga_Chispa"), 1);
                }
                this.AwardMilestoneProgram(player, n"chispa_qh_ep01_emp", n"EMPOverload", 3);
                this.AwardMilestoneProgram(player, n"chispa_qh_ep01_overheat", n"Overheat", 3);
            }
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        this.ResetEp02Only();
        this.SyncRetroactiveProgression(player);
        this.ShowRelicBanner(n"ch_banner_dbg_ep02", "[SPARKY] Episode 2 activated — Check your holophone in Northside");
    }

    public final func ReplayEp02Call() -> Void {
        if IsDefined(this.m_ep02) {
            this.m_ep02.ReplayCall();
        }
    }

    public final func TeleportToEp02Northside() -> Void {
        if IsDefined(this.m_ep02) {
            this.m_ep02.TeleportToNorthside();
        }
    }

    public final func TriggerEp02RegulatorSurge() -> Void {
        if IsDefined(this.m_ep02) {
            this.m_ep02.TriggerRegulatorPurge();
        }
    }

    public final func ResetEp02Only() -> Void {
        this.m_speechToken += 1;
        this.m_activeCallToken += 1;
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
        this.m_journalPinSyncedTag = -1;
        this.m_journalPinRetryTicks = 0;

        this.StopCurrentSpeechAudio();
        this.CloseActiveChispaCallHud();
        this.SetSkipSpeechHintVisible(false);
        this.StopNpcLipSync();
        this.HideDialogChoices();
        this.HideWorldInteraction();
        this.ClearMappin();
        this.ClearSmartBridge();
        this.ClearRicochetBridge();
        this.ClearCoprocessorRamBridge();
        if IsDefined(this.m_ep02) {
            this.m_ep02.CleanupEntities();
            this.m_ep02.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep03) {
            this.m_ep03.CleanupEntities();
            this.m_ep03.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep04) {
            this.m_ep04.CleanupEntities();
            this.m_ep04.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep05) {
            this.m_ep05.CleanupEntities();
            this.m_ep05.ResetJournalAndFacts();
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        if qs.GetFact(n"chispa_ep01_done") == 0 {
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        qs.SetFact(n"chispa_season_stage", 200);
        this.m_sessionReadyTicks = 12;
        this.ScheduleTick(0.40);
    }

    public final func StartEp03Directly() -> Void {
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(this.m_ep00) {
            this.m_ep00.CleanupEntities();
        }
        if IsDefined(this.m_ep01) {
            this.m_ep01.CleanupEntities();
        }
        if IsDefined(this.m_ep02) {
            this.m_ep02.CleanupEntities();
        }
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            this.DeactivateJournalPinList([
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/mp_ep00_alley",
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/mp_ep00_console"
            ]);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_nc_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            if IsDefined(player) {
                let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Chispa_CoreDongle") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle"), 1);
                }
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Lexington_Chispa") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Lexington_Chispa"), 1);
                }
            }
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        if qs.GetFact(n"chispa_ep01_done") == 0 {
            this.DeactivateJournalPinList([
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/mp_ep01_kabuki",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/mp_ep01_terminal"
            ]);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep01_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            if IsDefined(player) {
                let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Chispa_MemorySector01") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector01"), 1);
                }
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Saratoga_Chispa") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Saratoga_Chispa"), 1);
                }
                this.AwardMilestoneProgram(player, n"chispa_qh_ep01_emp", n"EMPOverload", 3);
                this.AwardMilestoneProgram(player, n"chispa_qh_ep01_overheat", n"Overheat", 3);
            }
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        if qs.GetFact(n"chispa_ep02_done") == 0 {
            this.DeactivateJournalPinList([
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/mp_ep02_northside",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract/mp_ep02_rig"
            ]);
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk", "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            jm.ChangeEntryState("quests/side_quest/chispa_ep02_quest", "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
            if IsDefined(player) {
                let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Chispa_MemorySector02") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector02"), 1);
                }
                if !this.PlayerOwnsItemOrDeckPart(player, t"Items.Preset_Achilles_Chispa") {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Achilles_Chispa"), 1);
                }
                this.AwardMilestoneProgram(player, n"chispa_qh_ep02_blind", n"Blind", 3);
            }
            qs.SetFact(n"chispa_ep02_done", 1);
            qs.SetFact(n"chispa_ep02_stage", 5);
        }
        this.ResetEp03Only();
        this.SyncRetroactiveProgression(player);
        this.ShowRelicBanner(n"ch_banner_dbg_ep03", "[SPARKY] Episode 3 activated — Check your holophone at South Waterfront");
    }

    public final func ReplayEp03Call() -> Void {
        if IsDefined(this.m_ep03) {
            this.m_ep03.ReplayCall();
        }
    }

    public final func TeleportToEp03Waterfront() -> Void {
        if IsDefined(this.m_ep03) {
            this.m_ep03.TeleportToWaterfront();
        }
    }

    public final func TriggerEp03JammerSurge() -> Void {
        if IsDefined(this.m_ep03) {
            this.m_ep03.TriggerJammerInversion();
        }
    }

    public final func ResetEp03Only() -> Void {
        this.m_speechToken += 1;
        this.m_activeCallToken += 1;
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
        this.m_journalPinSyncedTag = -1;
        this.m_journalPinRetryTicks = 0;

        this.StopCurrentSpeechAudio();
        this.CloseActiveChispaCallHud();
        this.SetSkipSpeechHintVisible(false);
        this.StopNpcLipSync();
        this.HideDialogChoices();
        this.HideWorldInteraction();
        this.ClearMappin();
        this.ClearSmartBridge();
        this.ClearRicochetBridge();
        this.ClearCoprocessorRamBridge();
        if IsDefined(this.m_ep03) {
            this.m_ep03.CleanupEntities();
            this.m_ep03.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep04) {
            this.m_ep04.CleanupEntities();
            this.m_ep04.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep05) {
            this.m_ep05.CleanupEntities();
            this.m_ep05.ResetJournalAndFacts();
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        if qs.GetFact(n"chispa_ep01_done") == 0 {
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        if qs.GetFact(n"chispa_ep02_done") == 0 {
            qs.SetFact(n"chispa_ep02_done", 1);
            qs.SetFact(n"chispa_ep02_stage", 5);
        }
        qs.SetFact(n"chispa_season_stage", 300);
        this.m_sessionReadyTicks = 12;
        this.ScheduleTick(0.40);
    }

    private final func PrepareForEpisodeReset() -> Void {
        this.m_retroSyncDoneForSession = false;
        this.m_speechToken += 1;
        this.m_activeCallToken += 1;
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
        this.m_journalPinSyncedTag = -1;
        this.m_journalPinRetryTicks = 0;

        this.StopCurrentSpeechAudio();
        this.CloseActiveChispaCallHud();
        this.SetSkipSpeechHintVisible(false);
        this.StopNpcLipSync();
        this.HideDialogChoices();
        this.HideWorldInteraction();
        this.ClearMappin();
        this.ClearSmartBridge();
        this.ClearRicochetBridge();
        this.ClearCoprocessorRamBridge();
    }

    private final func EnsureItemOwned(ts: ref<TransactionSystem>, player: ref<PlayerPuppet>, itemId: TweakDBID) -> Void {
        if IsDefined(ts) && IsDefined(player) && !this.PlayerOwnsItemOrDeckPart(player, itemId) {
            ts.GiveItem(player, ItemID.FromTDBID(itemId), 1);
        }
    }

    private final func MarkEpisodeJournalComplete(
        jm: ref<JournalManager>,
        pinPaths: array<String>,
        objPaths: array<String>,
        questPath: String
    ) -> Void {
        this.DeactivateJournalPinList(pinPaths);
        if !IsDefined(jm) {
            return;
        }
        for obj in objPaths {
            jm.ChangeEntryState(obj, "gameJournalQuestObjective", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
        }
        jm.ChangeEntryState(questPath, "gameJournalQuest", gameJournalEntryState.Succeeded, JournalNotifyOption.DoNotNotify);
    }

    private final func CompletePrerequisitesUpTo(maxEp: Int32) -> Void {
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;

        if IsDefined(this.m_ep00) {
            this.m_ep00.CleanupEntities();
        }
        if maxEp >= 1 && IsDefined(this.m_ep01) {
            this.m_ep01.CleanupEntities();
        }
        if maxEp >= 2 && IsDefined(this.m_ep02) {
            this.m_ep02.CleanupEntities();
        }
        if maxEp >= 3 && IsDefined(this.m_ep03) {
            this.m_ep03.CleanupEntities();
        }
        if maxEp >= 4 && IsDefined(this.m_ep04) {
            this.m_ep04.CleanupEntities();
        }

        if qs.GetFact(n"chispa_ep00_done") == 0 {
            this.MarkEpisodeJournalComplete(jm, [
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley/mp_ep00_alley",
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa/mp_ep00_console"
            ], [
                "quests/side_quest/chispa_nc_quest/phase_ep00/01_answer_sms",
                "quests/side_quest/chispa_nc_quest/phase_ep00/02_clear_alley",
                "quests/side_quest/chispa_nc_quest/phase_ep00/03_claim_chispa",
                "quests/side_quest/chispa_nc_quest/phase_ep00/04_talk_chispa"
            ], "quests/side_quest/chispa_nc_quest");
            this.EnsureItemOwned(ts, player, t"Items.Chispa_CoreDongle");
            this.EnsureItemOwned(ts, player, t"Items.Preset_Lexington_Chispa");
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        if maxEp >= 1 && qs.GetFact(n"chispa_ep01_done") == 0 {
            this.MarkEpisodeJournalComplete(jm, [
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate/mp_ep01_kabuki",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract/mp_ep01_terminal"
            ], [
                "quests/side_quest/chispa_ep01_quest/phase_ep01/01_ep01_sms",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/02_ep01_infiltrate",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/03_ep01_extract",
                "quests/side_quest/chispa_ep01_quest/phase_ep01/04_ep01_talk"
            ], "quests/side_quest/chispa_ep01_quest");
            this.EnsureItemOwned(ts, player, t"Items.Chispa_MemorySector01");
            this.EnsureItemOwned(ts, player, t"Items.Preset_Saratoga_Chispa");
            this.AwardMilestoneProgram(player, n"chispa_qh_ep01_emp", n"EMPOverload", 3);
            this.AwardMilestoneProgram(player, n"chispa_qh_ep01_overheat", n"Overheat", 3);
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        if maxEp >= 2 && qs.GetFact(n"chispa_ep02_done") == 0 {
            this.MarkEpisodeJournalComplete(jm, [
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear/mp_ep02_northside",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract/mp_ep02_rig"
            ], [
                "quests/side_quest/chispa_ep02_quest/phase_ep02/01_ep02_sms",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/02_ep02_clear",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/03_ep02_extract",
                "quests/side_quest/chispa_ep02_quest/phase_ep02/04_ep02_talk"
            ], "quests/side_quest/chispa_ep02_quest");
            this.EnsureItemOwned(ts, player, t"Items.Chispa_MemorySector02");
            this.EnsureItemOwned(ts, player, t"Items.Preset_Achilles_Chispa");
            this.AwardMilestoneProgram(player, n"chispa_qh_ep02_wep", n"WeaponMalfunction", 3);
            this.AwardMilestoneProgram(player, n"chispa_qh_ep02_blind", n"Blind", 3);
            qs.SetFact(n"chispa_ep02_done", 1);
            qs.SetFact(n"chispa_ep02_stage", 5);
        }
        if maxEp >= 3 && qs.GetFact(n"chispa_ep03_done") == 0 {
            this.MarkEpisodeJournalComplete(jm, [
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear/mp_ep03_waterfront",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract/mp_ep03_rig"
            ], [
                "quests/side_quest/chispa_ep03_quest/phase_ep03/01_ep03_sms",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/02_ep03_clear",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/03_ep03_extract",
                "quests/side_quest/chispa_ep03_quest/phase_ep03/04_ep03_talk"
            ], "quests/side_quest/chispa_ep03_quest");
            this.EnsureItemOwned(ts, player, t"Items.Chispa_MemorySector03");
            this.EnsureItemOwned(ts, player, t"Items.Preset_Shingen_Chispa");
            this.AwardMilestoneProgram(player, n"chispa_qh_ep03_mem", n"MemoryWipe", 3);
            this.AwardMilestoneProgram(player, n"chispa_qh_ep03_contagion", n"Contagion", 3);
            qs.SetFact(n"chispa_ep03_done", 1);
            qs.SetFact(n"chispa_ep03_stage", 5);
        }
        if maxEp >= 4 && qs.GetFact(n"chispa_ep04_done") == 0 {
            this.MarkEpisodeJournalComplete(jm, [
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear/mp_ep04_border",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract/mp_ep04_rig"
            ], [
                "quests/side_quest/chispa_ep04_quest/phase_ep04/01_ep04_sms",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/02_ep04_clear",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/03_ep04_extract",
                "quests/side_quest/chispa_ep04_quest/phase_ep04/04_ep04_talk"
            ], "quests/side_quest/chispa_ep04_quest");
            this.EnsureItemOwned(ts, player, t"Items.Chispa_MemorySector04");
            this.EnsureItemOwned(ts, player, t"Items.Preset_Masamune_Chispa");
            this.AwardMilestoneProgram(player, n"chispa_qh_ep04_cyber", n"DisableCyberware", 3);
            qs.SetFact(n"chispa_ep04_done", 1);
            qs.SetFact(n"chispa_ep04_stage", 5);
        }
        this.SyncRetroactiveProgression(player);
    }

    public final func StartEp04Directly() -> Void {
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !this.HasLiftedWatsonLockdown(player) {
            this.UnlockFullNightCityMap();
        }
        this.CompletePrerequisitesUpTo(3);
        this.ResetEp04Only();
        this.SyncRetroactiveProgression(player);
        this.ShowRelicBanner(n"ch_banner_dbg_ep04", "[SPARKY] Episode 4 activated — Check your holophone post-lockdown");
    }

    public final func ReplayEp04Call() -> Void {
        if IsDefined(this.m_ep04) {
            this.m_ep04.ReplayCall();
        }
    }

    public final func TeleportToEp04Border() -> Void {
        if IsDefined(this.m_ep04) {
            this.m_ep04.TeleportToBorder();
        }
    }

    public final func TriggerEp04CacheSurge() -> Void {
        if IsDefined(this.m_ep04) {
            this.m_ep04.TriggerRelayOverload();
        }
    }

    public final func ResetEp04Only() -> Void {
        this.PrepareForEpisodeReset();
        if IsDefined(this.m_ep04) {
            this.m_ep04.CleanupEntities();
            this.m_ep04.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep05) {
            this.m_ep05.CleanupEntities();
            this.m_ep05.ResetJournalAndFacts();
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        if qs.GetFact(n"chispa_ep01_done") == 0 {
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        if qs.GetFact(n"chispa_ep02_done") == 0 {
            qs.SetFact(n"chispa_ep02_done", 1);
            qs.SetFact(n"chispa_ep02_stage", 5);
        }
        if qs.GetFact(n"chispa_ep03_done") == 0 {
            qs.SetFact(n"chispa_ep03_done", 1);
            qs.SetFact(n"chispa_ep03_stage", 5);
        }
        qs.SetFact(n"chispa_season_stage", 400);
        this.m_sessionReadyTicks = 12;
        this.ScheduleTick(0.40);
    }

    public final func StartEp05Directly() -> Void {
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !this.HasLiftedWatsonLockdown(player) {
            this.UnlockFullNightCityMap();
        }
        this.CompletePrerequisitesUpTo(4);
        this.ResetEp05Only();
        this.SyncRetroactiveProgression(player);
        this.ShowRelicBanner(n"ch_banner_dbg_ep05", "[SPARKY] Episode 5 activated — Check your holophone bound for Pacifica");
    }

    public final func ReplayEp05Call() -> Void {
        if IsDefined(this.m_ep05) {
            this.m_ep05.ReplayCall();
        }
    }

    public final func TeleportToEp05Pacifica() -> Void {
        if IsDefined(this.m_ep05) {
            this.m_ep05.TeleportToPacifica();
        }
    }

    public final func TriggerEp05ContainmentPurge() -> Void {
        if IsDefined(this.m_ep05) {
            this.m_ep05.TriggerContainmentPurge();
        }
    }

    public final func ResetEp05Only() -> Void {
        this.PrepareForEpisodeReset();
        if IsDefined(this.m_ep05) {
            this.m_ep05.CleanupEntities();
            this.m_ep05.ResetJournalAndFacts();
        }
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(this.GetGameInstance());
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            qs.SetFact(n"chispa_ep00_done", 1);
            qs.SetFact(n"chispa_ep00_stage", 5);
        }
        if qs.GetFact(n"chispa_ep01_done") == 0 {
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        if qs.GetFact(n"chispa_ep02_done") == 0 {
            qs.SetFact(n"chispa_ep02_done", 1);
            qs.SetFact(n"chispa_ep02_stage", 5);
        }
        if qs.GetFact(n"chispa_ep03_done") == 0 {
            qs.SetFact(n"chispa_ep03_done", 1);
            qs.SetFact(n"chispa_ep03_stage", 5);
        }
        if qs.GetFact(n"chispa_ep04_done") == 0 {
            qs.SetFact(n"chispa_ep04_done", 1);
            qs.SetFact(n"chispa_ep04_stage", 5);
        }
        qs.SetFact(n"chispa_season_stage", 500);
        this.m_sessionReadyTicks = 12;
        this.ScheduleTick(0.40);
    }

    public final func ResetAllState() -> Void {
        this.m_retroSyncDoneForSession = false;
        this.m_speechToken += 1;
        this.m_activeCallToken += 1;
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
        this.m_journalPinSyncedTag = -1;
        this.m_journalPinRetryTicks = 0;

        this.StopCurrentSpeechAudio();
        this.CloseActiveChispaCallHud();
        this.SetSkipSpeechHintVisible(false);
        this.StopNpcLipSync();
        this.HideDialogChoices();
        this.HideWorldInteraction();
        this.ClearMappin();
        this.ClearSmartBridge();
        this.ClearRicochetBridge();
        this.ClearCoprocessorRamBridge();
        this.SyncAudiowareEngineState(true);
        if IsDefined(this.m_ep00) {
            this.m_ep00.CleanupEntities();
            this.m_ep00.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep01) {
            this.m_ep01.CleanupEntities();
            this.m_ep01.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep02) {
            this.m_ep02.CleanupEntities();
            this.m_ep02.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep03) {
            this.m_ep03.CleanupEntities();
            this.m_ep03.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep04) {
            this.m_ep04.CleanupEntities();
            this.m_ep04.ResetJournalAndFacts();
        }
        if IsDefined(this.m_ep05) {
            this.m_ep05.CleanupEntities();
            this.m_ep05.ResetJournalAndFacts();
        }
        if IsDefined(this.m_live) {
            this.m_live.ResetRuntime();
        }
        this.m_sessionReadyTicks = 12;
        this.ScheduleTick(0.40);
    }

    public final func OnTick() -> Void {
        this.m_tickScheduled = false;
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);

        if !this.IsGameplayReady(player) {
            this.m_sessionReadyTicks = 0;
            this.SetSkipSpeechHintVisible(false);
            this.HideDialogChoices();
            this.HideWorldInteraction();
            if ChispaSessionService.IsSessionReady() && IsDefined(qs) {
                if qs.GetFact(n"chispa_ep00_done") == 0 && qs.GetFact(n"chispa_ep00_stage") == 1 && IsDefined(this.m_ep00) {
                    this.m_ep00.CheckSmsReply();
                } else if qs.GetFact(n"chispa_ep00_done") > 0 && qs.GetFact(n"chispa_ep01_done") == 0 && qs.GetFact(n"chispa_ep01_stage") == 1 && IsDefined(this.m_ep01) {
                    this.m_ep01.CheckSmsReply();
                } else if qs.GetFact(n"chispa_ep00_done") > 0 && qs.GetFact(n"chispa_ep01_done") > 0 && qs.GetFact(n"chispa_ep02_done") == 0 && qs.GetFact(n"chispa_ep02_stage") == 1 && IsDefined(this.m_ep02) {
                    this.m_ep02.CheckSmsReply();
                } else if qs.GetFact(n"chispa_ep00_done") > 0 && qs.GetFact(n"chispa_ep01_done") > 0 && qs.GetFact(n"chispa_ep02_done") > 0 && qs.GetFact(n"chispa_ep03_done") == 0 && qs.GetFact(n"chispa_ep03_stage") == 1 && IsDefined(this.m_ep03) {
                    this.m_ep03.CheckSmsReply();
                } else if qs.GetFact(n"chispa_ep00_done") > 0 && qs.GetFact(n"chispa_ep01_done") > 0 && qs.GetFact(n"chispa_ep02_done") > 0 && qs.GetFact(n"chispa_ep03_done") > 0 && qs.GetFact(n"chispa_ep04_done") == 0 && qs.GetFact(n"chispa_ep04_stage") == 1 && IsDefined(this.m_ep04) {
                    this.m_ep04.CheckSmsReply();
                } else if qs.GetFact(n"chispa_ep00_done") > 0 && qs.GetFact(n"chispa_ep01_done") > 0 && qs.GetFact(n"chispa_ep02_done") > 0 && qs.GetFact(n"chispa_ep03_done") > 0 && qs.GetFact(n"chispa_ep04_done") > 0 && qs.GetFact(n"chispa_ep05_done") == 0 && qs.GetFact(n"chispa_ep05_stage") == 1 && IsDefined(this.m_ep05) {
                    this.m_ep05.CheckSmsReply();
                }
            }
            this.ScheduleTick(0.45);
            return;
        }
        if this.m_pausedByUiMenu {
            this.OnUiMenuChanged(false);
        }

        let fullGameplay: Bool = this.IsInFullGameplayTier(player);
        if fullGameplay {
            if this.m_sessionReadyTicks < 100 {
                this.m_sessionReadyTicks += 1;
            }
            if this.m_sessionReadyTicks == 1 || this.m_sessionReadyTicks == 3 || this.m_sessionReadyTicks == 7 {
                this.SyncAudiowareEngineState(true);
            }
            if this.m_sessionReadyTicks == 8 && !this.m_retroSyncDoneForSession {
                this.m_retroSyncDoneForSession = true;
                this.SyncRetroactiveProgression(player);
            }
            if (this.m_directHoloFeedOpen || this.m_callHudQueuedOrOpen) && !this.m_activeCallPendingPickup && this.IsExternalPhoneCallBusy() {
                this.m_directHoloFeedOpen = false;
                this.m_callHudQueuedOrOpen = false;
                this.m_activeCallIsVideo = false;
                this.m_activeCallContact = n"None";
            }
            if this.m_fastTravelLoading && !this.IsInSystemOrPauseMenu() {
                let ftNow: Float = EngineTime.ToFloat(GameInstance.GetSimTime(game));
                if ftNow - this.m_fastTravelStartedAt > 12.00 {
                    this.m_fastTravelLoading = false;
                }
            }
            if this.m_sessionReadyTicks <= 4 || (this.m_sessionReadyTicks % 8) == 0 {
                this.EnsureSmartBridgeActive(player);
                this.EnsureRicochetBridgeActive(player);
                this.EnsureCoprocessorRamBridgeActive(player);
            }
        }

        let phoneOpen: Bool = this.IsPhoneOverlayOpen();
        if phoneOpen || this.IsControllingDevice() {
            this.SetSkipSpeechHintVisible(false);
            this.HideDialogChoices();
            this.HideWorldInteraction();
        }

        let nextDelay: Float = 1.00;
        let ep05Completed: Bool = qs.GetFact(n"chispa_ep05_done") > 0;
        if qs.GetFact(n"chispa_ep00_done") == 0 {
            if IsDefined(this.m_ep00) {
                nextDelay = this.m_ep00.Tick(player, phoneOpen, fullGameplay);
            }
        } else if qs.GetFact(n"chispa_ep01_done") == 0 {
            if IsDefined(this.m_ep01) {
                nextDelay = this.m_ep01.Tick(player, phoneOpen, fullGameplay);
            }
        } else if qs.GetFact(n"chispa_ep02_done") == 0 {
            if IsDefined(this.m_ep02) {
                nextDelay = this.m_ep02.Tick(player, phoneOpen, fullGameplay);
            }
        } else if qs.GetFact(n"chispa_ep03_done") == 0 {
            if IsDefined(this.m_ep03) {
                nextDelay = this.m_ep03.Tick(player, phoneOpen, fullGameplay);
            }
        } else if qs.GetFact(n"chispa_ep04_done") == 0 {
            if IsDefined(this.m_ep04) {
                nextDelay = this.m_ep04.Tick(player, phoneOpen, fullGameplay);
            }
        } else if IsDefined(this.m_ep05) {
            nextDelay = this.m_ep05.Tick(player, phoneOpen, fullGameplay);
            if ep05Completed && !this.m_isPlayingDialogueSequence && !this.m_dialogActive && nextDelay >= 0.95 {
                nextDelay = 1.50;
            }
        }
        if IsDefined(this.m_live) {
            this.m_live.WatchdogTick();
        }
        this.ScheduleTick(nextDelay);
    }
}

// ---------------------------------------------------------------------------
// 1. Conexión Inmediata de Llamadas al Pulsar [T] (PhoneSystem.OnPickupPhone)
// ---------------------------------------------------------------------------

@wrapMethod(PhoneSystem)
private final func OnPickupPhone(request: ref<PickupPhoneRequest>) -> Void {
    wrappedMethod(request);
    if Equals(request.CallInformation.contactName, n"chispa_ai") {
        let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGameInstance());
        if IsDefined(sys) {
            sys.OnCustomCallPickedUp(request.CallInformation.contactName, request.shouldBeRejected);
        }
    }
}

// ---------------------------------------------------------------------------
// 2. Visor Holográfico Ámbar/Cian Retro-2022 (HudPhoneAvatarController)
// ---------------------------------------------------------------------------

@addField(HudPhoneAvatarController)
private let m_chispaHoloFeed: wref<inkCanvas>;

@addField(HudPhoneAvatarController)
private let m_chispaPulseProxy: ref<inkAnimProxy>;

@addField(HudPhoneAvatarController)
private let m_chispaTelemetryLabel: wref<inkText>;

@addField(HudPhoneAvatarController)
private let m_chispaSubTelemetryLabel: wref<inkText>;

@addMethod(HudPhoneAvatarController)
public final func ChispaRefreshLiveStatus() -> Void {
    if IsDefined(this.m_chispaSubTelemetryLabel) {
        let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
        if IsDefined(sys) {
            this.m_chispaSubTelemetryLabel.SetText(sys.GetLiveHoloSubtitleStatus());
        }
    }
}

@wrapMethod(HudPhoneAvatarController)
private final func RefreshView(avatarID: TweakDBID, const contactName: script_ref<String>, mode: EHudAvatarMode) -> Void {
    wrappedMethod(avatarID, contactName, mode);

    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) {
        sys.SetHoloAvatarController(this);
    }
    let showChispaFeed: Bool = Equals(mode, EHudAvatarMode.Holocall) && IsDefined(sys) && sys.IsChispaVideocallActive();

    if showChispaFeed {
        inkWidgetRef.SetVisible(this.m_HolocallRenderTexture, false);
        if !IsDefined(this.m_chispaHoloFeed) {
            let parent: wref<inkCompoundWidget> = inkWidgetRef.Get(this.m_HolocallHolder) as inkCompoundWidget;
            if !IsDefined(parent) {
                parent = this.GetRootCompoundWidget();
            }
            if IsDefined(parent) {
                let feed: ref<inkCanvas> = new inkCanvas();
                feed.SetName(n"ChispaHoloFeed");
                feed.SetHAlign(inkEHorizontalAlign.Left);
                feed.SetVAlign(inkEVerticalAlign.Top);
                feed.SetSize(440.0, 440.0);
                feed.Reparent(parent);

                let bg: ref<inkRectangle> = new inkRectangle();
                bg.SetAnchor(inkEAnchor.Fill);
                bg.SetTintColor(new HDRColor(0.10, 0.06, 0.01, 0.90));
                bg.Reparent(feed);

                let topBar: ref<inkRectangle> = new inkRectangle();
                topBar.SetAnchor(inkEAnchor.TopCenter);
                topBar.SetAnchorPoint(new Vector2(0.50, 0.00));
                topBar.SetMargin(new inkMargin(0.0, 16.0, 0.0, 0.0));
                topBar.SetSize(396.0, 3.0);
                topBar.SetTintColor(new HDRColor(1.00, 0.78, 0.20, 0.85));
                topBar.Reparent(feed);

                let header: ref<inkText> = new inkText();
                header.SetName(n"ChispaHeaderLabel");
                header.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
                header.SetFontStyle(n"Semi-Bold");
                header.SetFontSize(20);
                header.SetAnchor(inkEAnchor.TopCenter);
                header.SetAnchorPoint(new Vector2(0.50, 0.00));
                header.SetHorizontalAlignment(textHorizontalAlignment.Center);
                header.SetMargin(new inkMargin(0.0, 26.0, 0.0, 0.0));
                header.SetTintColor(new HDRColor(0.30, 0.94, 1.00, 0.92));
                header.SetText("ZETATECH 2022 // KIROSHI");
                header.Reparent(feed);

                let portrait: ref<inkImage> = new inkImage();
                portrait.SetName(n"ChispaPortrait");
                portrait.SetAnchor(inkEAnchor.Centered);
                portrait.SetAnchorPoint(new Vector2(0.50, 0.50));
                portrait.SetMargin(new inkMargin(0.0, -14.0, 0.0, 0.0));
                portrait.SetSize(210.0, 210.0);
                portrait.SetTintColor(new HDRColor(1.00, 0.78, 0.20, 0.95));
                portrait.Reparent(feed);
                InkImageUtils.RequestAvatarOrUnknown(this, inkImageRef.Create(portrait), t"PhoneAvatars.Avatar_Bartmoss");

                let scanline: ref<inkRectangle> = new inkRectangle();
                scanline.SetName(n"ChispaScanline");
                scanline.SetAnchor(inkEAnchor.TopCenter);
                scanline.SetAnchorPoint(new Vector2(0.50, 0.00));
                scanline.SetSize(396.0, 5.0);
                scanline.SetTintColor(new HDRColor(0.25, 0.95, 1.00, 0.52));
                scanline.Reparent(feed);

                let scanAnim: ref<inkAnimDef> = new inkAnimDef();
                let marginInterp: ref<inkAnimMargin> = new inkAnimMargin();
                marginInterp.SetStartMargin(new inkMargin(0.0, 22.0, 0.0, 0.0));
                marginInterp.SetEndMargin(new inkMargin(0.0, 406.0, 0.0, 0.0));
                marginInterp.SetDuration(1.45);
                scanAnim.AddInterpolator(marginInterp);

                let alphaInterp: ref<inkAnimTransparency> = new inkAnimTransparency();
                alphaInterp.SetStartTransparency(0.30);
                alphaInterp.SetEndTransparency(0.90);
                alphaInterp.SetDuration(0.70);
                scanAnim.AddInterpolator(alphaInterp);

                let opts: inkAnimOptions;
                opts.loopType = inkanimLoopType.PingPong;
                opts.loopInfinite = true;
                this.m_chispaPulseProxy = scanline.PlayAnimationWithOptions(scanAnim, opts);

                let telemetry: ref<inkText> = new inkText();
                telemetry.SetName(n"ChispaTelemetryLabel");
                telemetry.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
                telemetry.SetFontStyle(n"Semi-Bold");
                telemetry.SetFontSize(24);
                telemetry.SetAnchor(inkEAnchor.BottomCenter);
                telemetry.SetAnchorPoint(new Vector2(0.50, 1.00));
                telemetry.SetHorizontalAlignment(textHorizontalAlignment.Center);
                telemetry.SetMargin(new inkMargin(0.0, 0.0, 0.0, 56.0));
                telemetry.SetTintColor(new HDRColor(1.00, 0.82, 0.24, 0.96));
                telemetry.SetText(sys.GetLoc(n"ch_holo_telemetry_title", "S.P.A.R.K.Y. v0.98b"));
                telemetry.Reparent(feed);
                this.m_chispaTelemetryLabel = telemetry;

                let subTextInit: String = sys.GetLiveHoloSubtitleStatus();
                let subTelemetry: ref<inkText> = new inkText();
                subTelemetry.SetName(n"ChispaSubTelemetryLabel");
                subTelemetry.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
                subTelemetry.SetFontStyle(n"Semi-Bold");
                subTelemetry.SetFontSize(18);
                subTelemetry.SetAnchor(inkEAnchor.BottomCenter);
                subTelemetry.SetAnchorPoint(new Vector2(0.50, 1.00));
                subTelemetry.SetHorizontalAlignment(textHorizontalAlignment.Center);
                subTelemetry.SetMargin(new inkMargin(0.0, 0.0, 0.0, 30.0));
                subTelemetry.SetTintColor(new HDRColor(0.30, 0.94, 1.00, 0.90));
                subTelemetry.SetText(subTextInit);
                subTelemetry.Reparent(feed);
                this.m_chispaSubTelemetryLabel = subTelemetry;

                let bottomBar: ref<inkRectangle> = new inkRectangle();
                bottomBar.SetAnchor(inkEAnchor.BottomCenter);
                bottomBar.SetAnchorPoint(new Vector2(0.50, 1.00));
                bottomBar.SetMargin(new inkMargin(0.0, 0.0, 0.0, 18.0));
                bottomBar.SetSize(396.0, 3.0);
                bottomBar.SetTintColor(new HDRColor(1.00, 0.78, 0.20, 0.85));
                bottomBar.Reparent(feed);

                this.m_chispaHoloFeed = feed;
            }
        }
        if IsDefined(this.m_chispaHoloFeed) {
            if IsDefined(this.m_chispaTelemetryLabel) {
                this.m_chispaTelemetryLabel.SetText(sys.GetLoc(n"ch_holo_telemetry_title", "S.P.A.R.K.Y. v0.98b"));
            }
            if IsDefined(this.m_chispaSubTelemetryLabel) {
                this.m_chispaSubTelemetryLabel.SetText(sys.GetLiveHoloSubtitleStatus());
            }
            this.m_chispaHoloFeed.SetVisible(true);
        }
    } else if IsDefined(this.m_chispaHoloFeed) {
        this.m_chispaHoloFeed.SetVisible(false);
    }
}

// ---------------------------------------------------------------------------
// 3. Entrada de Jugador para Diálogos, Interacciones [F] y GracePeriod
// ---------------------------------------------------------------------------

@addMethod(PlayerPuppet)
private final func SetChispaInputListeners(attach: Bool) -> Void {
    let actions: array<CName> = [
        n"Choice1",
        n"ChoiceApply",
        n"UI_Apply",
        n"ChoiceScrollUp",
        n"UI_MoveUp",
        n"dpad_up",
        n"UI_DPadUp",
        n"up_button",
        n"navigate_up",
        n"popup_navigate_up",
        n"option_switch_prev",
        n"NextWeapon",
        n"QuickMelee",
        n"UseConsumable",
        n"UseConsumable_Tutorial",
        n"DropCarriedObject",
        n"PickUpBodyFromTakedown",
        n"ChoiceScrollDown",
        n"UI_MoveDown",
        n"dpad_down",
        n"UI_DPadDown",
        n"down_button",
        n"navigate_down",
        n"popup_navigate_down",
        n"option_switch_next",
        n"PreviousWeapon",
        n"IconicCyberware",
        n"CycleObjectives",
        n"CycleTrackedQuestEntry",
        n"mouse_wheel",
        n"Keyboard_1",
        n"Keyboard_2",
        n"Keyboard_3",
        n"Keyboard_4",
        n"WeaponSlot1",
        n"WeaponSlot2",
        n"WeaponSlot3",
        n"WeaponSlot4",
        n"PhoneInteract",
        n"NotificationOpen",
        n"NotificationOpenSMS",
        n"ToggleCrouch",
        n"SceneFastForward",
        n"FastForward_Hold"
    ];
    for act in actions {
        if attach {
            this.RegisterInputListener(this, act);
        } else {
            this.UnregisterInputListener(this, act);
        }
    }
}

@wrapMethod(PlayerPuppet)
protected cb func OnGameAttached() -> Bool {
    let res: Bool = wrappedMethod();
    this.SetChispaInputListeners(true);
    return res;
}

@wrapMethod(PlayerPuppet)
protected cb func OnMakePlayerVisibleAfterSpawn(evt: ref<EndGracePeriodAfterSpawn>) -> Bool {
    let res: Bool = wrappedMethod(evt);
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGame());
    if IsDefined(sys) {
        sys.OnPlayerSpawnGraceEnded();
    }
    return res;
}

@wrapMethod(PlayerPuppet)
protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGame());
    if IsDefined(sys) && !sys.IsUiBlockingWorldInput() {
        let actionName: CName = ListenerAction.GetName(action);
        if sys.IsDialogActive() {
            if Equals(actionName, n"ChoiceScrollUp")
                || Equals(actionName, n"UI_MoveUp")
                || Equals(actionName, n"dpad_up")
                || Equals(actionName, n"UI_DPadUp")
                || Equals(actionName, n"up_button")
                || Equals(actionName, n"navigate_up")
                || Equals(actionName, n"popup_navigate_up")
                || Equals(actionName, n"option_switch_prev")
                || Equals(actionName, n"NextWeapon")
                || Equals(actionName, n"QuickMelee")
                || Equals(actionName, n"UseConsumable")
                || Equals(actionName, n"UseConsumable_Tutorial")
                || Equals(actionName, n"DropCarriedObject")
                || Equals(actionName, n"PickUpBodyFromTakedown") {
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.MoveDialogSelection(-1);
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"ChoiceScrollDown")
                || Equals(actionName, n"UI_MoveDown")
                || Equals(actionName, n"dpad_down")
                || Equals(actionName, n"UI_DPadDown")
                || Equals(actionName, n"down_button")
                || Equals(actionName, n"navigate_down")
                || Equals(actionName, n"popup_navigate_down")
                || Equals(actionName, n"option_switch_next")
                || Equals(actionName, n"PreviousWeapon")
                || Equals(actionName, n"IconicCyberware")
                || Equals(actionName, n"CycleObjectives")
                || Equals(actionName, n"CycleTrackedQuestEntry") {
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.MoveDialogSelection(1);
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"mouse_wheel") {
                let wheelVal: Float = ListenerAction.GetValue(action);
                if wheelVal > 0.05 {
                    sys.MoveDialogSelection(-1);
                } else if wheelVal < -0.05 {
                    sys.MoveDialogSelection(1);
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"Keyboard_1") || Equals(actionName, n"WeaponSlot1") {
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.SelectDialogChoiceIndex(0);
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"Keyboard_2") || Equals(actionName, n"WeaponSlot2") {
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.SelectDialogChoiceIndex(1);
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"Keyboard_3") || Equals(actionName, n"WeaponSlot3") {
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.SelectDialogChoiceIndex(2);
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"Keyboard_4") || Equals(actionName, n"WeaponSlot4") {
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.SelectDialogChoiceIndex(3);
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"PhoneInteract")
                || Equals(actionName, n"NotificationOpen")
                || Equals(actionName, n"NotificationOpenSMS") {
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if Equals(actionName, n"Choice1") || Equals(actionName, n"ChoiceApply") || Equals(actionName, n"UI_Apply") {
                if Equals(actionName, n"Choice1") && sys.IsNativeInteractionHubBlocking() {
                    return wrappedMethod(action, consumer);
                }
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.OnDialogConfirmPressed();
                } else if ListenerAction.IsButtonJustReleased(action) {
                    sys.ConfirmSelectedDialogChoice();
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
        } else if sys.IsSkippableSpeechPlaying() {
            if Equals(actionName, n"SceneFastForward")
                || Equals(actionName, n"FastForward_Hold")
                || Equals(actionName, n"Choice1")
                || Equals(actionName, n"ChoiceApply") {
                if ListenerAction.IsButtonJustPressed(action) {
                    sys.SkipCurrentSpeechStep();
                }
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
        } else if sys.IsInteractionActive() && Equals(actionName, n"Choice1") {
            if ListenerAction.IsButtonJustPressed(action) {
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
            if ListenerAction.IsButtonJustReleased(action) && sys.TryHandleWorldInteractionInput() {
                ListenerActionConsumer.Consume(consumer);
                return true;
            }
        }
    }
    return wrappedMethod(action, consumer);
}

@wrapMethod(PlayerPuppet)
protected cb func OnDetach() -> Bool {
    this.SetChispaInputListeners(false);
    return wrappedMethod();
}

// ---------------------------------------------------------------------------
// 4. Mapa del Mundo [M], Tooltips y Ruta GPS Automática
// ---------------------------------------------------------------------------

@addMethod(WorldMapMenuGameController)
public final func ChispaTryAutoTrack(ctrl: ref<BaseWorldMapMappinController>) -> Void {
    if !IsDefined(ctrl) || ctrl.IsTracked() {
        return;
    }
    if this.IsFastTravelEnabled() || this.IsDelamainTaxiEnabled() {
        return;
    }
    let ms: ref<MappinSystem> = GameInstance.GetMappinSystem(GetGameInstance());
    if IsDefined(ms) && !IsDefined(ms.GetMappin(ms.GetManuallyTrackedMappinID())) {
        let mappin: wref<IMappin> = ctrl.GetMappin();
        if IsDefined(mappin) && this.CanQuestTrackMappin(mappin) && !this.IsMappinQuestTracked(mappin) {
            this.UntrackCustomPositionMappin();
            this.TrackQuestMappin(ctrl);
        }
    }
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnInitialize() -> Bool {
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) {
        sys.SetActiveWorldMap(this, false);
    }
    return wrappedMethod();
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnRemovePreloader(widget: wref<inkWidget>) -> Bool {
    let res: Bool = wrappedMethod(widget);
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) {
        sys.SetActiveWorldMap(this, true);
    }
    return res;
}

@wrapMethod(WorldMapMenuGameController)
protected cb func OnUninitialize() -> Bool {
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) {
        sys.SetActiveWorldMap(null, false);
    }
    return wrappedMethod();
}

@addField(BaseWorldMapMappinController)
private let m_chispaPinCache: Int32;

@addMethod(BaseWorldMapMappinController)
private final func IsChispaOwnMappin() -> Bool {
    if this.m_chispaPinCache != 0 {
        return this.m_chispaPinCache == 2;
    }
    if this.IsExactlyA(n"WorldMapPlayerMappinController") {
        this.m_chispaPinCache = 1;
        return false;
    }
    let mappin: wref<IMappin> = this.GetMappin();
    if !IsDefined(mappin) || NotEquals(mappin.GetVariant(), gamedataMappinVariant.DefaultQuestVariant) {
        this.m_chispaPinCache = 1;
        return false;
    }
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) && sys.IsChispaMappin(mappin) {
        this.m_chispaPinCache = 2;
        return true;
    }
    this.m_chispaPinCache = 1;
    return false;
}

@wrapMethod(BaseWorldMapMappinController)
protected cb func OnIntro() -> Bool {
    this.m_chispaPinCache = 0;
    let res: Bool = wrappedMethod();
    if this.IsChispaOwnMappin() {
        let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
        if IsDefined(sys) {
            sys.NotifyWorldMapMappinReady(this);
        }
    }
    return res;
}

@wrapMethod(BaseWorldMapMappinController)
private final func GetDesiredOpacityAndInteractivity(out opacity: Float, out interactive: Bool) -> Void {
    wrappedMethod(opacity, interactive);
    if this.IsChispaOwnMappin() {
        interactive = true;
        opacity = 1.00;
        this.isVisibleInFilterAndZoom = true;
    }
}

@wrapMethod(BaseWorldMapMappinController)
protected func ComputeRootState() -> CName {
    let st: CName = wrappedMethod();
    if this.IsChispaOwnMappin() {
        return n"Quest";
    }
    return st;
}

@wrapMethod(WorldMapTooltipController)
public func SetData(const data: script_ref<WorldMapTooltipData>, menu: ref<WorldMapMenuGameController>) -> Void {
    wrappedMethod(data, menu);
    let mappin: wref<IMappin> = Deref(data).mappin;
    if IsDefined(mappin) && Equals(mappin.GetVariant(), gamedataMappinVariant.DefaultQuestVariant) {
        let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
        if IsDefined(sys) && sys.IsChispaMappin(mappin) {
            inkTextRef.SetText(this.m_titleText, sys.GetMappinTitle());
            inkTextRef.SetText(this.m_descText, sys.GetMappinDesc());
            inkWidgetRef.SetVisible(this.m_descText, true);
            this.GetRootWidget().SetState(n"Quest");
        }
    }
}

// ---------------------------------------------------------------------------
// 5. Control de Visibilidad de Diálogos (dialogWidgetGameController)
// ---------------------------------------------------------------------------

@addMethod(dialogWidgetGameController)
public final func ChispaEnsureVisible() -> Void {
    let root: wref<inkWidget> = this.GetRootWidget();
    if IsDefined(root) {
        root.SetVisible(true);
        root.SetOpacity(1.00);
        let parent: wref<inkWidget> = root.GetParentWidget();
        if IsDefined(parent) {
            parent.SetVisible(true);
            parent.SetOpacity(1.00);
        }
    }
}

@addMethod(dialogWidgetGameController)
public final func ChispaSyncAndReveal(hubsVar: Variant, hubId: Int32, selectedIdx: Int32) -> Void {
    this.OnDialogsData(hubsVar);
    this.OnDialogsActivateHub(hubId);
    this.OnDialogsSelectIndex(selectedIdx);
    this.ChispaEnsureVisible();
}

@addMethod(dialogWidgetGameController)
public final func ChispaIsVisuallyOpen() -> Bool {
    let root: wref<inkWidget> = this.GetRootWidget();
    return this.m_AreDialogsOpen && IsDefined(root) && root.IsVisible() && root.GetOpacity() > 0.50;
}

@wrapMethod(dialogWidgetGameController)
protected cb func OnInitialize() -> Bool {
    let res: Bool = wrappedMethod();
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) {
        sys.SetDialogWidgetController(this);
    }
    return res;
}

@wrapMethod(dialogWidgetGameController)
protected cb func OnUninitialize() -> Bool {
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) {
        sys.SetDialogWidgetController(null);
    }
    return wrappedMethod();
}

@wrapMethod(dialogWidgetGameController)
protected func OnInteractionsChanged() -> Void {
    wrappedMethod();
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) && sys.IsDialogActive() {
        this.ChispaEnsureVisible();
    }
}

@wrapMethod(DialogChoiceLogicController)
protected cb func OnInitialize() -> Bool {
    let res: Bool = wrappedMethod();
    if IsDefined(this.m_InActiveTextRoot) {
        this.m_InActiveTextRoot.SetEffectEnabled(inkEffectType.LinearWipe, n"LinearWipe_0", true);
        this.m_InActiveTextRoot.SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", 0.00);
    }
    if IsDefined(this.m_SelectedBg) {
        this.m_SelectedBg.SetEffectEnabled(inkEffectType.LinearWipe, n"LinearWipe_0", true);
        this.m_SelectedBg.SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", 0.00);
    }
    if IsDefined(this.m_SelectedBgJohnny) {
        this.m_SelectedBgJohnny.SetEffectEnabled(inkEffectType.LinearWipe, n"LinearWipe_0", true);
        this.m_SelectedBgJohnny.SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", 0.00);
    }
    return res;
}

@wrapMethod(DialogChoiceLogicController)
public final func AnimateSelection() -> Void {
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    if IsDefined(sys) && sys.IsDialogActive() {
        this.m_isPreserveSelectionFadeOut = false;
        let r: wref<inkWidget> = this.GetRootWidget();
        if IsDefined(r) {
            r.SetVisible(true);
            r.SetOpacity(1.00);
        }
    }
    if !this.m_isPreserveSelectionFadeOut && this.m_isSelected && !this.m_prevIsSelected && IsDefined(this.m_InActiveTextRoot) {
        let curWipe: Float = this.m_InActiveTextRoot.GetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition");
        if curWipe > 0.90 {
            this.m_InActiveTextRoot.SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", 0.00);
        }
    }
    wrappedMethod();
    if !this.m_isPreserveSelectionFadeOut && Equals(this.m_prevIsSelected, this.m_isSelected) {
        let targetWipe: Float = this.m_isSelected ? 1.00 : 0.00;
        if (!IsDefined(this.m_animSelectedBgProxy) || !this.m_animSelectedBgProxy.IsPlaying()) && IsDefined(this.m_SelectedBg) {
            this.m_SelectedBg.SetEffectEnabled(inkEffectType.LinearWipe, n"LinearWipe_0", true);
            this.m_SelectedBg.SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", targetWipe);
        }
        if (!IsDefined(this.m_animSelectedJohnnyBgProxy) || !this.m_animSelectedJohnnyBgProxy.IsPlaying()) && IsDefined(this.m_SelectedBgJohnny) {
            this.m_SelectedBgJohnny.SetEffectEnabled(inkEffectType.LinearWipe, n"LinearWipe_0", true);
            this.m_SelectedBgJohnny.SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", targetWipe);
        }
        if (!IsDefined(this.m_animActiveTextProxy) || !this.m_animActiveTextProxy.IsPlaying()) && IsDefined(this.m_InActiveTextRoot) {
            this.m_InActiveTextRoot.SetEffectEnabled(inkEffectType.LinearWipe, n"LinearWipe_0", true);
            this.m_InActiveTextRoot.SetEffectParamValue(inkEffectType.LinearWipe, n"LinearWipe_0", n"transition", targetWipe);
        }
    }
}

@wrapMethod(FastTravelSystem)
private final func SetFastTravelStarted() -> Void {
    let sys: ref<ChispaSystem> = GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"ChispaNC.ChispaSystem") as ChispaSystem;
    if IsDefined(sys) {
        sys.NotifyFastTravelLoadingChanged(true);
    }
    wrappedMethod();
}

@wrapMethod(FastTravelSystem)
protected cb func OnLoadingScreenFinished(value: Bool) -> Bool {
    let res: Bool = wrappedMethod(value);
    if value {
        let sys: ref<ChispaSystem> = GameInstance.GetScriptableSystemsContainer(this.GetGameInstance()).Get(n"ChispaNC.ChispaSystem") as ChispaSystem;
        if IsDefined(sys) {
            sys.NotifyFastTravelLoadingChanged(false);
        }
    }
    return res;
}
