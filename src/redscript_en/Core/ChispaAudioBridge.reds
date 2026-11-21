// Protocolo CHISPA / SPARKY Protocol — Dual Optional Audio Bridge (AudioXL + Audioware + Safe Fallback)
module ChispaNC

import Codeware.Localization.*

@if(ModuleExists("AudioXL"))
import AudioXL.*

@if(ModuleExists("Audioware"))
import Audioware.*

public abstract class ChispaAudioBridge {
    // Backend IDs: 0 = Subtitle-only safe fallback, 1 = AudioXL, 2 = Audioware

    public static func SyncBackendState(game: GameInstance, fullSync: Bool) -> Void {
        ChispaAudioBridge.SyncAudiowareInternal(game, fullSync);
    }

    @if(ModuleExists("Audioware"))
    private static func SyncAudiowareInternal(game: GameInstance, fullSync: Bool) -> Void {
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

    @if(!ModuleExists("Audioware"))
    private static func SyncAudiowareInternal(game: GameInstance, fullSync: Bool) -> Void {
    }

    public static func PlaySfx(game: GameInstance, sfxEvent: CName, player: ref<PlayerPuppet>) -> Void {
        if ChispaAudioBridge.TryPlaySfxAudioXL(game, sfxEvent) {
            return;
        }
        ChispaAudioBridge.TryPlaySfxAudioware(game, sfxEvent, player);
    }

    @if(ModuleExists("AudioXL"))
    private static func TryPlaySfxAudioXL(game: GameInstance, sfxEvent: CName) -> Bool {
        if !AudioXLNative.Enabled() || !AudioXLNative.Has(sfxEvent) {
            return false;
        }
        return AudioXLAPI.Play(sfxEvent);
    }

    @if(!ModuleExists("AudioXL"))
    private static func TryPlaySfxAudioXL(game: GameInstance, sfxEvent: CName) -> Bool {
        return false;
    }

    @if(ModuleExists("Audioware"))
    private static func TryPlaySfxAudioware(game: GameInstance, sfxEvent: CName, player: ref<PlayerPuppet>) -> Void {
        let audioExt: ref<AudioSystemExt> = GameInstance.GetAudioSystemExt(game);
        if !IsDefined(audioExt) {
            return;
        }
        let settings: ref<AudioSettingsExt> = new AudioSettingsExt();
        settings.affectedByTimeDilation = false;
        let sfxLine: scnDialogLineType;
        if IsDefined(player) {
            audioExt.Play(sfxEvent, player.GetEntityID(), n"ChispaSFX", sfxLine, settings);
        } else {
            let emptyId: EntityID;
            let emptyName: CName;
            audioExt.Play(sfxEvent, emptyId, emptyName, sfxLine, settings);
        }
    }

    @if(!ModuleExists("Audioware"))
    private static func TryPlaySfxAudioware(game: GameInstance, sfxEvent: CName, player: ref<PlayerPuppet>) -> Void {
    }

    public static func PlaySpeech(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        resolvedSpeaker: CName,
        player: ref<PlayerPuppet>,
        out playedVariant: CName
    ) -> Int32 {
        if ChispaAudioBridge.TryPlaySpeechAudioXL(game, eventName, speakerEntity, player, playedVariant) {
            return 1;
        }
        if ChispaAudioBridge.TryPlaySpeechAudioware(game, eventName, speakerEntity, resolvedSpeaker) {
            playedVariant = eventName;
            return 2;
        }
        playedVariant = n"None";
        return 0;
    }

    @if(ModuleExists("AudioXL"))
    private static func TryPlaySpeechAudioXL(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        player: ref<PlayerPuppet>,
        out playedVariant: CName
    ) -> Bool {
        if !AudioXLNative.Enabled() {
            playedVariant = n"None";
            return false;
        }
        let chosen: CName = AudioXLAPI.ResolveVariant(eventName, game, speakerEntity);
        if !AudioXLNative.Has(chosen) {
            playedVariant = n"None";
            return false;
        }
        let targetId: EntityID;
        if IsDefined(player) {
            targetId = player.GetEntityID();
        }
        if AudioXLAPI.Play(chosen, targetId) {
            playedVariant = chosen;
            return true;
        }
        playedVariant = n"None";
        return false;
    }

    @if(!ModuleExists("AudioXL"))
    private static func TryPlaySpeechAudioXL(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        player: ref<PlayerPuppet>,
        out playedVariant: CName
    ) -> Bool {
        playedVariant = n"None";
        return false;
    }

    @if(ModuleExists("Audioware"))
    private static func TryPlaySpeechAudioware(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        resolvedSpeaker: CName
    ) -> Bool {
        let audioExt: ref<AudioSystemExt> = GameInstance.GetAudioSystemExt(game);
        if !IsDefined(audioExt) {
            return false;
        }
        let settings: ref<AudioSettingsExt> = new AudioSettingsExt();
        settings.affectedByTimeDilation = false;
        audioExt.Play(eventName, speakerEntity, resolvedSpeaker, scnDialogLineType.Invisible, settings);
        return true;
    }

    @if(!ModuleExists("Audioware"))
    private static func TryPlaySpeechAudioware(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        resolvedSpeaker: CName
    ) -> Bool {
        return false;
    }

    public static func ResolveSpeechDuration(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        activeBackend: Int32,
        playedVariant: CName,
        fallbackDuration: Float
    ) -> Float {
        let dur: Float = 0.00;
        if activeBackend == 1 {
            dur = ChispaAudioBridge.ResolveDurationAudioXL(game, eventName, speakerEntity, playedVariant);
        } else if activeBackend == 2 {
            dur = ChispaAudioBridge.ResolveDurationAudioware(game, eventName);
        }
        if dur > 0.20 {
            return dur;
        }
        return fallbackDuration;
    }

    @if(ModuleExists("AudioXL"))
    private static func ResolveDurationAudioXL(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        playedVariant: CName
    ) -> Float {
        if IsNameValid(playedVariant) && NotEquals(playedVariant, n"None") && AudioXLNative.Has(playedVariant) {
            return AudioXLNative.Duration(playedVariant);
        }
        if AudioXLNative.Available() {
            let resolved: CName = AudioXLAPI.ResolveVariant(eventName, game, speakerEntity);
            if AudioXLNative.Has(resolved) {
                return AudioXLNative.Duration(resolved);
            }
        }
        return 0.00;
    }

    @if(!ModuleExists("AudioXL"))
    private static func ResolveDurationAudioXL(
        game: GameInstance,
        eventName: CName,
        speakerEntity: EntityID,
        playedVariant: CName
    ) -> Float {
        return 0.00;
    }

    @if(ModuleExists("Audioware"))
    private static func ResolveDurationAudioware(game: GameInstance, eventName: CName) -> Float {
        let audioExt: ref<AudioSystemExt> = GameInstance.GetAudioSystemExt(game);
        if !IsDefined(audioExt) {
            return 0.00;
        }
        let locSys: ref<LocalizationSystem> = LocalizationSystem.GetInstance(game);
        let voiceLocale: LocaleExt = LocaleExt.Spanish;
        let gender: PlayerGender = PlayerGender.Default;
        if IsDefined(locSys) {
            voiceLocale = IntoLocaleExt(locSys.GetVoiceLanguage());
            gender = locSys.GetPlayerGender();
        }
        let dur: Float = audioExt.Duration(eventName, voiceLocale, gender, true);
        if dur <= 0.20 {
            dur = audioExt.Duration(eventName, LocaleExt.English, gender, true);
        }
        return dur;
    }

    @if(!ModuleExists("Audioware"))
    private static func ResolveDurationAudioware(game: GameInstance, eventName: CName) -> Float {
        return 0.00;
    }

    public static func StopSpeech(
        game: GameInstance,
        activeBackend: Int32,
        prevEvt: CName,
        prevVariant: CName,
        prevEntity: EntityID,
        prevSpeaker: CName
    ) -> Void {
        if activeBackend == 1 {
            ChispaAudioBridge.StopSpeechAudioXL(game, prevEvt, prevVariant, prevEntity);
        } else if activeBackend == 2 {
            ChispaAudioBridge.StopSpeechAudioware(game, prevEvt, prevEntity, prevSpeaker);
        }
    }

    @if(ModuleExists("AudioXL"))
    private static func StopSpeechAudioXL(
        game: GameInstance,
        prevEvt: CName,
        prevVariant: CName,
        prevEntity: EntityID
    ) -> Void {
        if !AudioXLNative.Available() {
            return;
        }
        if IsNameValid(prevVariant) && NotEquals(prevVariant, n"None") {
            AudioXLAPI.Stop(prevVariant, 0.02);
        }
        if IsNameValid(prevEvt) && NotEquals(prevEvt, n"None") && NotEquals(prevEvt, prevVariant) {
            let resolved: CName = AudioXLAPI.ResolveVariant(prevEvt, game, prevEntity);
            if IsNameValid(resolved) && NotEquals(resolved, n"None") && NotEquals(resolved, prevVariant) {
                AudioXLAPI.Stop(resolved, 0.02);
            }
            AudioXLAPI.Stop(prevEvt, 0.02);
        }
    }

    @if(!ModuleExists("AudioXL"))
    private static func StopSpeechAudioXL(
        game: GameInstance,
        prevEvt: CName,
        prevVariant: CName,
        prevEntity: EntityID
    ) -> Void {
    }

    @if(ModuleExists("Audioware"))
    private static func StopSpeechAudioware(
        game: GameInstance,
        prevEvt: CName,
        prevEntity: EntityID,
        prevSpeaker: CName
    ) -> Void {
        let audioExt: ref<AudioSystemExt> = GameInstance.GetAudioSystemExt(game);
        if IsDefined(audioExt) {
            audioExt.Stop(prevEvt, prevEntity, prevSpeaker);
        }
    }

    @if(!ModuleExists("Audioware"))
    private static func StopSpeechAudioware(
        game: GameInstance,
        prevEvt: CName,
        prevEntity: EntityID,
        prevSpeaker: CName
    ) -> Void {
    }
}
