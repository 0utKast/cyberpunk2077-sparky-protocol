// Protocolo CHISPA / SPARKY Protocol — Modular Core Engine (Base Game 2.x)
module ChispaNC

import Audioware.*
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

public class ChispaSubtitleHideCallback extends DelayCallback {
    public let system: wref<ChispaSystem>;
    public let eventName: CName;
    public let token: Int32;

    public func Call() -> Void {
        if IsDefined(this.system) {
            this.system.HideFallbackSubtitleIfActive(this.eventName, this.token);
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

    public static func IsSessionReady() -> Bool {
        let svc: ref<ChispaSessionService> = GameInstance.GetScriptableServiceContainer().GetService(n"ChispaNC.ChispaSessionService") as ChispaSessionService;
        if IsDefined(svc) {
            return svc.m_sessionReady;
        }
        return false;
    }

    private cb func OnLoad() -> Void {
        this.m_sessionReady = false;
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

    // Controlador de episodio actual (extensible por episodios en Episodes/*.reds)
    public let m_ep00: ref<ChispaEp00Handler>;
    public let m_ep01: ref<ChispaEp01Handler>;
    public let m_ep02: ref<ChispaEp02Handler>;
    public let m_ep03: ref<ChispaEp03Handler>;
    public let m_ep04: ref<ChispaEp04Handler>;
    public let m_ep05: ref<ChispaEp05Handler>;
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
    private let m_skipHintVisible: Bool;
    private let m_fallbackSubToken: Int32;

    // Holollamadas y proyección holográfica directa Kiroshi
    public let m_activeCallContact: CName;
    public let m_activeCallIsVideo: Bool;
    public let m_activeCallToken: Int32;
    public let m_activeCallPendingPickup: Bool;
    public let m_activeCallStageTag: Int32;
    private let m_directHoloFeedOpen: Bool;
    private let m_callHudQueuedOrOpen: Bool;

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
        this.m_smartBridgeMod = null;
        this.m_ricochetBridgeMod = null;

        this.m_tickScheduled = false;
        this.m_spawnGraceEnded = false;
        this.m_sessionReadyTicks = 0;
        this.m_isPlayingDialogueSequence = false;
        this.m_speechAllowManualSkip = false;
        this.m_currentSpeechIndex = 0;
        this.m_speechStepStartedAt = 0.00;
        this.m_currentPlayingEvent = n"None";
        this.m_currentPlayingEntity = new EntityID();
        this.m_currentPlayingSpeaker = n"None";
        this.m_skipHintVisible = false;
        this.m_fallbackSubToken = 0;
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
        this.ScheduleTick(0.60);
    }

    private func OnDetach() -> Void {
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
        this.m_smartBridgeMod = null;
        this.m_ricochetBridgeMod = null;
        this.m_directHoloFeedOpen = false;
        this.m_callHudQueuedOrOpen = false;
        this.m_activeWorldMap = null;
        this.m_dialogWidgetCtrl = null;
        this.m_tickScheduled = false;
        this.m_spawnGraceEnded = false;
        this.m_sessionReadyTicks = 0;
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
        if !IsDefined(player) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if !IsDefined(qs) || !IsDefined(ts) || !IsDefined(ss) {
            return;
        }
        let needsBridge: Bool = qs.GetFact(n"chispa_ep03_stage") >= 2
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Shingen_Chispa")) > 0
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
        if !IsDefined(player) {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let ts: ref<TransactionSystem> = GameInstance.GetTransactionSystem(game);
        let ss: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
        if !IsDefined(qs) || !IsDefined(ts) || !IsDefined(ss) {
            return;
        }
        let needsBridge: Bool = qs.GetFact(n"chispa_ep04_stage") >= 2
            || qs.GetFact(n"chispa_ep05_stage") >= 2
            || qs.GetFact(n"chispa_permanent_partner") > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Masamune_Chispa")) > 0
            || ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Overture_Chispa")) > 0;
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
        let awProvider: ref<LocalizationProvider> = GameInstance.GetScriptableSystemsContainer(game).Get(n"Audioware.LocalizationProvider") as LocalizationProvider;
        if IsDefined(awProvider) {
            awProvider.OnLocaleChange();
            awProvider.OnGenderChange();
        }
        if fullSync {
            let volSync: ref<VolumeSettingsListener> = new VolumeSettingsListener();
            volSync.Initialize(game);
            let miscSync: ref<MiscSettingsListener> = new MiscSettingsListener();
            miscSync.Initialize(game);
        }
    }

    public final func PlaySfx(sfxEvent: CName) -> Void {
        let game: GameInstance = this.GetGameInstance();
        this.SyncAudiowareEngineState(false);
        let settings: ref<AudioSettingsExt> = new AudioSettingsExt();
        settings.affectedByTimeDilation = false;
        let sfxLine: scnDialogLineType;
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            GameInstance.GetAudioSystemExt(game).Play(sfxEvent, player.GetEntityID(), n"ChispaSFX", sfxLine, settings);
        } else {
            let emptyId: EntityID;
            let emptyName: CName;
            GameInstance.GetAudioSystemExt(game).Play(sfxEvent, emptyId, emptyName, sfxLine, settings);
        }
    }

    // --- Motor de Locuciones, Salto Seguro en Escenas Presenciales y LipSync (Patrones #3, #5) ---

    private final func ClearCurrentSpeechTracking() -> Void {
        this.m_currentPlayingEvent = n"None";
        this.m_currentPlayingEntity = new EntityID();
        this.m_currentPlayingSpeaker = n"None";
    }

    public final func HideFallbackSubtitleIfActive(eventName: CName, token: Int32) -> Void {
        if token != this.m_fallbackSubToken || !IsNameValid(eventName) || Equals(eventName, n"None") {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            let hideIds: array<CRUID>;
            ArrayPush(hideIds, CreateCRUID(StringToUint64(NameToString(eventName))));
            board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine, ToVariant(hideIds), true);
        }
    }

    private final func ResolveFallbackEnglishSubtitle(eventName: CName) -> String {
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

    private final func EnsureFallbackSubtitleShown(eventName: CName, speakerEntity: EntityID, speakerName: CName, lineType: scnDialogLineType, duration: Float) -> Void {
        if !IsNameValid(eventName) || Equals(eventName, n"None") {
            return;
        }
        let key: String = NameToString(eventName);
        if StrLen(key) == 0 {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let locSys: ref<LocalizationSystem> = LocalizationSystem.GetInstance(game);
        if IsDefined(locSys) {
            let resolved: String = locSys.GetSubtitle(key);
            if StrLen(resolved) > 0 && NotEquals(key, resolved) {
                return;
            }
        }
        let fallbackText: String = this.ResolveFallbackEnglishSubtitle(eventName);
        if Equals(fallbackText, "") {
            return;
        }
        let targetObj: wref<GameObject> = EntityID.IsDefined(speakerEntity) ? (GameInstance.FindEntityByID(game, speakerEntity) as GameObject) : null;
        let line: scnDialogLineData;
        line.duration = duration;
        line.id = CreateCRUID(StringToUint64(key));
        line.isPersistent = false;
        line.speaker = targetObj;
        line.speakerName = NameToString(speakerName);
        line.text = fallbackText;
        line.type = lineType;
        let lines: array<scnDialogLineData>;
        ArrayPush(lines, line);
        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant(lines), true);
        }
        this.m_fallbackSubToken += 1;
        let hideCb: ref<ChispaSubtitleHideCallback> = new ChispaSubtitleHideCallback();
        hideCb.system = this;
        hideCb.eventName = eventName;
        hideCb.token = this.m_fallbackSubToken;
        GameInstance.GetDelaySystem(game).DelayCallback(hideCb, MaxF(0.25, duration), false);
    }

    private final func StopCurrentSpeechAudio() -> Void {
        this.m_fallbackSubToken += 1;
        if !IsNameValid(this.m_currentPlayingEvent) || Equals(this.m_currentPlayingEvent, n"None") {
            return;
        }
        let game: GameInstance = this.GetGameInstance();
        let prevEvt: CName = this.m_currentPlayingEvent;
        GameInstance.GetAudioSystemExt(game).Stop(prevEvt, this.m_currentPlayingEntity, this.m_currentPlayingSpeaker);
        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            let hideIds: array<CRUID>;
            ArrayPush(hideIds, CreateCRUID(StringToUint64(NameToString(prevEvt))));
            board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine, ToVariant(hideIds), true);
        }
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
        } else if this.m_directHoloFeedOpen && !this.IsAnyEpisodeInFinalTalkStage() {
            this.CloseDirectHoloFeed();
        }
        this.AdvanceSpeechSequence(this.m_speechToken, 0);
    }

    private final func ResolveStepDuration(step: ref<ChispaSpeechStep>, audioExt: ref<AudioSystemExt>) -> Float {
        let game: GameInstance = this.GetGameInstance();
        let locSys: ref<LocalizationSystem> = LocalizationSystem.GetInstance(game);
        let voiceLocale: LocaleExt = LocaleExt.Spanish;
        let gender: PlayerGender = PlayerGender.Default;
        if IsDefined(locSys) {
            voiceLocale = IntoLocaleExt(locSys.GetVoiceLanguage());
            gender = locSys.GetPlayerGender();
        }
        let dur: Float = audioExt.Duration(step.eventName, voiceLocale, gender, true);
        if dur <= 0.20 {
            dur = audioExt.Duration(step.eventName, LocaleExt.English, gender, true);
        }
        if dur <= 0.20 {
            dur = step.fallbackDuration;
        }
        return dur;
    }

    public final func AdvanceSpeechSequence(token: Int32, index: Int32) -> Void {
        if token != this.m_speechToken {
            return;
        }
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
            if this.m_directHoloFeedOpen && !this.IsAnyEpisodeInFinalTalkStage() {
                this.CloseDirectHoloFeed();
            }
            return;
        }

        let step: ref<ChispaSpeechStep> = this.m_speechSteps[index];
        let audioExt: ref<AudioSystemExt> = GameInstance.GetAudioSystemExt(game);
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

        let settings: ref<AudioSettingsExt> = new AudioSettingsExt();
        settings.affectedByTimeDilation = false;
        audioExt.Play(step.eventName, speakerEntity, resolvedSpeaker, step.lineType, settings);
        this.SetSkipSpeechHintVisible(this.m_speechAllowManualSkip && !this.IsPhoneOverlayOpen());

        let dur: Float = this.ResolveStepDuration(step, audioExt);
        this.EnsureFallbackSubtitleShown(step.eventName, speakerEntity, resolvedSpeaker, step.lineType, dur);
        this.StartNpcLipSync(step.speakerTag, speakerEntity, dur);

        let waitDur: Float;
        if index + 1 < ArraySize(this.m_speechSteps) {
            waitDur = MaxF(0.15, dur - 0.08);
        } else if this.IsHubRevealSpeechAction(this.m_speechActionOnComplete) {
            waitDur = MaxF(0.15, dur - 0.30);
        } else {
            waitDur = MaxF(0.15, dur - 0.04);
        }
        let cb: ref<ChispaSequenceCallback> = new ChispaSequenceCallback();
        cb.system = this;
        cb.token = token;
        cb.nextIndex = index + 1;
        GameInstance.GetDelaySystem(game).DelayCallback(cb, waitDur, false);
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
        this.m_lipSyncRemaining -= 0.11;
        if this.m_lipSyncRemaining <= 0.08 {
            this.m_lipSyncEntityId = new EntityID();
            return;
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
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Lexington_Chispa")) == 0 {
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
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Lexington_Chispa")) == 0 {
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
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector01")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector01"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Saratoga_Chispa")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Saratoga_Chispa"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.EMPOverloadLvl2Program")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.EMPOverloadLvl2Program"), 1);
                }
            }
            qs.SetFact(n"chispa_ep01_done", 1);
            qs.SetFact(n"chispa_ep01_stage", 5);
        }
        this.ResetEp02Only();
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
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_CoreDongle"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Lexington_Chispa")) == 0 {
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
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector01")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector01"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Saratoga_Chispa")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Saratoga_Chispa"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.EMPOverloadLvl2Program")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.EMPOverloadLvl2Program"), 1);
                }
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
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector02")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Chispa_MemorySector02"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.Preset_Achilles_Chispa")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.Preset_Achilles_Chispa"), 1);
                }
                if ts.GetItemQuantity(player, ItemID.FromTDBID(t"Items.BlindLvl2Program")) == 0 {
                    ts.GiveItem(player, ItemID.FromTDBID(t"Items.BlindLvl2Program"), 1);
                }
            }
            qs.SetFact(n"chispa_ep02_done", 1);
            qs.SetFact(n"chispa_ep02_stage", 5);
        }
        this.ResetEp03Only();
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
    }

    private final func EnsureItemOwned(ts: ref<TransactionSystem>, player: ref<PlayerPuppet>, itemId: TweakDBID) -> Void {
        if IsDefined(ts) && IsDefined(player) && ts.GetItemQuantity(player, ItemID.FromTDBID(itemId)) == 0 {
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
            this.EnsureItemOwned(ts, player, t"Items.EMPOverloadLvl2Program");
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
            this.EnsureItemOwned(ts, player, t"Items.BlindLvl2Program");
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
            this.EnsureItemOwned(ts, player, t"Items.ContagionLvl2Program");
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
            this.EnsureItemOwned(ts, player, t"Items.DisableCyberwareLvl2Program");
            qs.SetFact(n"chispa_ep04_done", 1);
            qs.SetFact(n"chispa_ep04_stage", 5);
        }
    }

    public final func StartEp04Directly() -> Void {
        let game: GameInstance = this.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !this.HasLiftedWatsonLockdown(player) {
            this.UnlockFullNightCityMap();
        }
        this.CompletePrerequisitesUpTo(3);
        this.ResetEp04Only();
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

        let fullGameplay: Bool = this.IsInFullGameplayTier(player);
        if fullGameplay {
            if this.m_sessionReadyTicks < 100 {
                this.m_sessionReadyTicks += 1;
            }
            if this.m_sessionReadyTicks == 1 || this.m_sessionReadyTicks == 3 || this.m_sessionReadyTicks == 7 {
                this.SyncAudiowareEngineState(true);
            }
            if (this.m_directHoloFeedOpen || this.m_callHudQueuedOrOpen) && !this.m_activeCallPendingPickup && this.IsExternalPhoneCallBusy() {
                this.m_directHoloFeedOpen = false;
                this.m_callHudQueuedOrOpen = false;
                this.m_activeCallIsVideo = false;
                this.m_activeCallContact = n"None";
            }
            this.EnsureSmartBridgeActive(player);
            this.EnsureRicochetBridgeActive(player);
        }

        let phoneOpen: Bool = this.IsPhoneOverlayOpen();
        if phoneOpen || this.IsControllingDevice() {
            this.SetSkipSpeechHintVisible(false);
            this.HideDialogChoices();
            this.HideWorldInteraction();
        }

        let nextDelay: Float = 1.00;
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

@wrapMethod(HudPhoneAvatarController)
private final func RefreshView(avatarID: TweakDBID, const contactName: script_ref<String>, mode: EHudAvatarMode) -> Void {
    wrappedMethod(avatarID, contactName, mode);

    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
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
                subTelemetry.SetText(sys.GetLoc(n"ch_holo_telemetry_sub", "DRILL SERGEANT // UNFILTERED"));
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
                this.m_chispaSubTelemetryLabel.SetText(sys.GetLoc(n"ch_holo_telemetry_sub", "DRILL SERGEANT // UNFILTERED"));
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

@addMethod(BaseWorldMapMappinController)
private final func IsChispaOwnMappin() -> Bool {
    if this.IsExactlyA(n"WorldMapPlayerMappinController") {
        return false;
    }
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
    return IsDefined(sys) && sys.IsChispaMappin(this.GetMappin());
}

@wrapMethod(BaseWorldMapMappinController)
protected cb func OnIntro() -> Bool {
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
    if Deref(data).mappin != null {
        let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(GetGameInstance());
        if IsDefined(sys) && sys.IsChispaMappin(Deref(data).mappin) {
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
