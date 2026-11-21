// Protocolo CHISPA v2.0 — Barra Neural Kiroshi Nativa (Codeware.UI), Teclas [Y]/[U] y Telemetría en Vivo
module ChispaNC

import Codeware.UI.*
import Codeware.UI.TextInput.*

public class ChispaKiroshiTextInput extends HubTextInput {
    // Estado local de tecla muerta (0=ninguna, 1=aguda ´, 2=diéresis ¨, 3=grave `, 4=circunflejo ^, 5=virgulilla ~)
    private let m_pendingDeadKey: Int32;
    private let m_vk186IsAcute: Bool;

    public final func SetVk186IsAcute(isAcute: Bool) -> Void {
        this.m_vk186IsAcute = isAcute;
    }

    protected func CreateWidgets() -> Void {
        super.CreateWidgets();
        this.SetLetterCase(textLetterCase.OriginalCase);
        this.SetMaxLength(280);
        let rawText: wref<inkText> = this.m_text.GetRootWidget() as inkText;
        if IsDefined(rawText) {
            rawText.UnbindProperty(n"tintColor");
            rawText.SetTintColor(new HDRColor(0.90, 0.98, 1.00, 1.00));
            rawText.SetOpacity(0.55);
        }
        if IsDefined(this.m_caret) {
            this.m_caret.SetTintColor(new HDRColor(0.25, 0.95, 1.00, 1.00));
        }
    }

    protected cb func OnInitialize() -> Void {
        super.OnInitialize();
        this.RefreshPlaceholderOpacity();
    }

    public func SetText(text: String) -> Void {
        this.m_pendingDeadKey = 0;
        super.SetText(text);
    }

    protected cb func OnInputKey(event: ref<inkKeyInputEvent>) -> Void {
        let prevDead: Int32 = this.m_pendingDeadKey;
        super.OnInputKey(event);
        // Evitar que mantener pulsada una tecla muerta repita la tilde suelta en OnHoldTick.
        if Equals(event.GetAction(), EInputAction.IACT_Press) && prevDead == 0 && this.m_pendingDeadKey != 0 {
            this.m_lastInputEvent = null;
        }
    }

    private final func IsModifierOnlyKey(key: EInputKey) -> Bool {
        return Equals(key, EInputKey.IK_Shift)
            || Equals(key, EInputKey.IK_LShift)
            || Equals(key, EInputKey.IK_RShift)
            || Equals(key, EInputKey.IK_Ctrl)
            || Equals(key, EInputKey.IK_LControl)
            || Equals(key, EInputKey.IK_RControl)
            || Equals(key, EInputKey.IK_Alt)
            || Equals(key, EInputKey.IK_UnknownA4)
            || Equals(key, EInputKey.IK_UnknownA5)
            || Equals(key, EInputKey.IK_CapsLock)
            || Equals(key, EInputKey.IK_NumLock)
            || Equals(key, EInputKey.IK_ScrollLock);
    }

    private final func DetectDeadKey(event: ref<inkKeyInputEvent>, isAltGr: Bool) -> Int32 {
        // Codeware llama ToUnicode(..., 0x4) después de TranslateMessage() de Win32: cuando Win32 ya cargó
        // una tecla muerta en ese frame, Codeware recibe el diacrítico duplicado ("´´", "¨¨", "``", "^^", "~~").
        let evChar: String = event.IsCharacter() ? event.GetCharacter() : "";
        if NotEquals(evChar, "") {
            if Equals(evChar, "´´") {
                return 1;
            }
            if Equals(evChar, "¨¨") {
                return 2;
            }
            if Equals(evChar, "``") {
                return 3;
            }
            if Equals(evChar, "^^") {
                return 4;
            }
            if Equals(evChar, "~~") {
                return 5;
            }
            return 0;
        }
        let key: EInputKey = event.GetKey();
        if isAltGr {
            if Equals(key, EInputKey.IK_4) {
                return 5;
            }
            if Equals(key, EInputKey.IK_Slash) {
                return 3;
            }
            if Equals(key, EInputKey.IK_SingleQuote) {
                return 4;
            }
            return 0;
        }
        if Equals(key, EInputKey.IK_SingleQuote) {
            return event.IsShiftDown() ? 2 : 1;
        }
        if Equals(key, EInputKey.IK_Semicolon) {
            if this.m_vk186IsAcute {
                return event.IsShiftDown() ? 2 : 1;
            }
            return event.IsShiftDown() ? 4 : 3;
        }
        return 0;
    }

    private final func DeadKeySymbol(deadKind: Int32) -> String {
        switch deadKind {
            case 1: return "'";
            case 2: return "\"";
            case 3: return "`";
            case 4: return "^";
            case 5: return "~";
        }
        return "";
    }

    private final func ComposeDeadKey(deadKind: Int32, ch: String) -> String {
        switch deadKind {
            case 1:
                if Equals(ch, "a") || Equals(ch, "á") { return "á"; }
                if Equals(ch, "e") || Equals(ch, "é") { return "é"; }
                if Equals(ch, "i") || Equals(ch, "í") { return "í"; }
                if Equals(ch, "o") || Equals(ch, "ó") { return "ó"; }
                if Equals(ch, "u") || Equals(ch, "ú") { return "ú"; }
                if Equals(ch, "y") || Equals(ch, "ý") { return "ý"; }
                if Equals(ch, "A") || Equals(ch, "Á") { return "Á"; }
                if Equals(ch, "E") || Equals(ch, "É") { return "É"; }
                if Equals(ch, "I") || Equals(ch, "Í") { return "Í"; }
                if Equals(ch, "O") || Equals(ch, "Ó") { return "Ó"; }
                if Equals(ch, "U") || Equals(ch, "Ú") { return "Ú"; }
                if Equals(ch, "Y") || Equals(ch, "Ý") { return "Ý"; }
                break;
            case 2:
                if Equals(ch, "u") || Equals(ch, "ü") { return "ü"; }
                if Equals(ch, "U") || Equals(ch, "Ü") { return "Ü"; }
                if Equals(ch, "a") || Equals(ch, "ä") { return "ä"; }
                if Equals(ch, "e") || Equals(ch, "ë") { return "ë"; }
                if Equals(ch, "i") || Equals(ch, "ï") { return "ï"; }
                if Equals(ch, "o") || Equals(ch, "ö") { return "ö"; }
                if Equals(ch, "y") || Equals(ch, "ÿ") { return "ÿ"; }
                if Equals(ch, "A") || Equals(ch, "Ä") { return "Ä"; }
                if Equals(ch, "E") || Equals(ch, "Ë") { return "Ë"; }
                if Equals(ch, "I") || Equals(ch, "Ï") { return "Ï"; }
                if Equals(ch, "O") || Equals(ch, "Ö") { return "Ö"; }
                break;
            case 3:
                if Equals(ch, "a") || Equals(ch, "à") { return "à"; }
                if Equals(ch, "e") || Equals(ch, "è") { return "è"; }
                if Equals(ch, "i") || Equals(ch, "ì") { return "ì"; }
                if Equals(ch, "o") || Equals(ch, "ò") { return "ò"; }
                if Equals(ch, "u") || Equals(ch, "ù") { return "ù"; }
                if Equals(ch, "A") || Equals(ch, "À") { return "À"; }
                if Equals(ch, "E") || Equals(ch, "È") { return "È"; }
                if Equals(ch, "I") || Equals(ch, "Ì") { return "Ì"; }
                if Equals(ch, "O") || Equals(ch, "Ò") { return "Ò"; }
                if Equals(ch, "U") || Equals(ch, "Ù") { return "Ù"; }
                break;
            case 4:
                if Equals(ch, "a") || Equals(ch, "â") { return "â"; }
                if Equals(ch, "e") || Equals(ch, "ê") { return "ê"; }
                if Equals(ch, "i") || Equals(ch, "î") { return "î"; }
                if Equals(ch, "o") || Equals(ch, "ô") { return "ô"; }
                if Equals(ch, "u") || Equals(ch, "û") { return "û"; }
                if Equals(ch, "A") || Equals(ch, "Â") { return "Â"; }
                if Equals(ch, "E") || Equals(ch, "Ê") { return "Ê"; }
                if Equals(ch, "I") || Equals(ch, "Î") { return "Î"; }
                if Equals(ch, "O") || Equals(ch, "Ô") { return "Ô"; }
                if Equals(ch, "U") || Equals(ch, "Û") { return "Û"; }
                break;
            case 5:
                if Equals(ch, "n") || Equals(ch, "ñ") { return "ñ"; }
                if Equals(ch, "N") || Equals(ch, "Ñ") { return "Ñ"; }
                if Equals(ch, "a") || Equals(ch, "ã") { return "ã"; }
                if Equals(ch, "o") || Equals(ch, "õ") { return "õ"; }
                if Equals(ch, "A") || Equals(ch, "Ã") { return "Ã"; }
                if Equals(ch, "O") || Equals(ch, "Õ") { return "Õ"; }
                break;
        }
        return "";
    }

    private final func InsertCustomText(rawStr: String) -> Void {
        if Equals(rawStr, "") {
            return;
        }
        let str: String = StrReplaceAll(rawStr, "´", "'");
        str = StrReplaceAll(str, "¨", "\"");
        switch this.m_text.GetLetterCase() {
            case textLetterCase.UpperCase:
                str = UTF8StrUpper(str);
                break;
            case textLetterCase.LowerCase:
                str = UTF8StrLower(str);
                break;
        }
        let addLen: Int32 = UTF8StrLen(str);
        if addLen <= 0 {
            return;
        }
        let selLen: Int32 = this.m_selection.IsEmpty()
            ? 0
            : (this.m_selection.GetRightPosition() - this.m_selection.GetLeftPosition());
        if (this.m_text.GetLength() - selLen + addLen) > this.m_text.GetMaxLength() {
            return;
        }

        let insertPos: Int32 = this.m_caret.GetPosition();
        if !this.m_selection.IsEmpty() {
            insertPos = this.m_selection.GetLeftPosition();
            this.m_text.DeleteCharRange(
                this.m_selection.GetLeftPosition(),
                this.m_selection.GetRightPosition()
            );
            this.m_selection.Clear();
            this.m_caret.SetMaxPosition(this.m_text.GetLength());
            this.m_caret.SetPosition(insertPos);
        }

        let idx: Int32 = 0;
        let curPos: Int32 = insertPos;
        while idx < addLen {
            let oneChar: String = UTF8StrMid(str, idx, 1);
            if NotEquals(oneChar, "") {
                this.m_text.InsertCharAt(curPos, oneChar);
                curPos += 1;
                this.m_caret.SetMaxPosition(this.m_text.GetLength());
                this.m_caret.SetPosition(curPos);
                this.m_selection.SetMaxPosition(this.m_text.GetLength());
                this.m_selection.Clear();
                this.m_measurer.MeasureChar(oneChar, curPos);
            }
            idx += 1;
        }
        this.UpdateLayout();
        this.RefreshPlaceholderOpacity();
        this.TriggerChangeCallback();
    }

    protected func ProcessInputEvent(event: ref<inkKeyInputEvent>) -> Void {
        let key: EInputKey = event.GetKey();
        if Equals(key, EInputKey.IK_Enter)
            || Equals(key, EInputKey.IK_Tab)
            || Equals(key, EInputKey.IK_Escape)
            || Equals(key, EInputKey.IK_Up) {
            this.m_pendingDeadKey = 0;
            return;
        }
        if this.IsModifierOnlyKey(key) {
            return;
        }

        let isAltGr: Bool = event.IsRightAltDown() || (event.IsControlDown() && event.IsAltDown());
        if (event.IsControlDown() && !isAltGr) || (event.IsAltDown() && !isAltGr) {
            this.m_pendingDeadKey = 0;
            super.ProcessInputEvent(event);
            return;
        }

        let deadKind: Int32 = this.DetectDeadKey(event, isAltGr);
        if deadKind != 0 {
            if this.m_pendingDeadKey == 0 {
                this.m_pendingDeadKey = deadKind;
                return;
            }
            let combinedDead: String = this.DeadKeySymbol(this.m_pendingDeadKey) + this.DeadKeySymbol(deadKind);
            this.m_pendingDeadKey = 0;
            this.InsertCustomText(combinedDead);
            return;
        }

        let rawChar: String = "";
        if event.IsCharacter() {
            rawChar = event.GetCharacter();
        } else if !isAltGr && Equals(key, EInputKey.IK_IntlBackslash) {
            rawChar = event.IsShiftDown() ? ">" : "<";
        }

        if this.m_pendingDeadKey != 0 {
            if Equals(key, EInputKey.IK_Backspace) {
                this.m_pendingDeadKey = 0;
                return;
            }
            if Equals(key, EInputKey.IK_Space) {
                let spaceDead: Int32 = this.m_pendingDeadKey;
                this.m_pendingDeadKey = 0;
                this.InsertCustomText(this.DeadKeySymbol(spaceDead));
                return;
            }
            if NotEquals(rawChar, "") {
                let deadKindPending: Int32 = this.m_pendingDeadKey;
                this.m_pendingDeadKey = 0;
                if UTF8StrLen(rawChar) == 1 {
                    let composed: String = this.ComposeDeadKey(deadKindPending, rawChar);
                    if NotEquals(composed, "") {
                        this.InsertCustomText(composed);
                        return;
                    }
                    this.InsertCustomText(this.DeadKeySymbol(deadKindPending) + rawChar);
                    return;
                }
                this.InsertCustomText(rawChar);
                return;
            }
            this.m_pendingDeadKey = 0;
            super.ProcessInputEvent(event);
            return;
        }

        if NotEquals(rawChar, "") {
            this.InsertCustomText(rawChar);
            return;
        }

        super.ProcessInputEvent(event);
    }

    public final func RefreshPlaceholderOpacity() -> Void {
        let rawText: wref<inkText> = this.m_text.GetRootWidget() as inkText;
        if IsDefined(rawText) {
            rawText.SetOpacity(this.m_text.IsEmpty() ? 0.55 : 1.00);
        }
    }

    public static func Create() -> ref<ChispaKiroshiTextInput> {
        let self: ref<ChispaKiroshiTextInput> = new ChispaKiroshiTextInput();
        self.CreateInstance();
        return self;
    }
}

public class ChispaKiroshiInputPopup extends CustomPopup {
    private let m_sys: wref<ChispaSystem>;
    private let m_textInput: ref<ChispaKiroshiTextInput>;
    private let m_statusBadge: wref<inkText>;
    private let m_openedAt: Float;
    private let m_contextPushed: Bool;
    private let m_dilationActive: Bool;
    private let m_isClosing: Bool;
    private let m_submitted: Bool;
    private let m_cleanedUp: Bool;

    public final func Setup(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
    }

    public func GetQueueName() -> CName {
        return n"chispa_kiroshi_popup";
    }

    public func IsBlocking() -> Bool {
        return true;
    }

    public func UseCursor() -> Bool {
        return false;
    }

    protected cb func OnCreate() -> Void {
        super.OnCreate();

        let rootCanvas: wref<inkCompoundWidget> = this.GetRootCompoundWidget();
        let container: ref<inkCanvas> = new inkCanvas();
        container.SetName(n"ChispaKiroshiBar");
        container.SetAnchor(inkEAnchor.BottomCenter);
        container.SetAnchorPoint(new Vector2(0.50, 1.00));
        container.SetMargin(new inkMargin(0.0, 0.0, 0.0, 175.0));
        container.SetSize(new Vector2(1380.0, 218.0));
        container.Reparent(rootCanvas);
        this.SetContainerWidget(container);

        let bg: ref<inkRectangle> = new inkRectangle();
        bg.SetName(n"ChispaBarBg");
        bg.SetAnchor(inkEAnchor.Fill);
        bg.SetTintColor(new HDRColor(0.04, 0.06, 0.09, 0.93));
        bg.Reparent(container);

        let stroke: ref<inkImage> = new inkImage();
        stroke.SetName(n"ChispaBarStroke");
        stroke.SetAtlasResource(r"base\\gameplay\\gui\\widgets\\notifications\\notification_assets.inkatlas");
        stroke.SetTexturePart(n"Plate_main_Stroke");
        stroke.SetNineSliceScale(true);
        stroke.SetAnchor(inkEAnchor.Fill);
        stroke.SetTintColor(new HDRColor(0.25, 0.95, 1.00, 0.45));
        stroke.Reparent(container);

        let topAccent: ref<inkRectangle> = new inkRectangle();
        topAccent.SetName(n"ChispaTopAccent");
        topAccent.SetAnchor(inkEAnchor.TopCenter);
        topAccent.SetAnchorPoint(new Vector2(0.50, 0.00));
        topAccent.SetMargin(new inkMargin(0.0, 6.0, 0.0, 0.0));
        topAccent.SetSize(new Vector2(1340.0, 3.0));
        topAccent.SetTintColor(new HDRColor(1.00, 0.78, 0.20, 0.90));
        topAccent.Reparent(container);

        let leftBracket: ref<inkImage> = new inkImage();
        leftBracket.SetName(n"ChispaLeftBracket");
        leftBracket.SetAtlasResource(r"base\\gameplay\\gui\\common\\shapes\\atlas_shapes_sync.inkatlas");
        leftBracket.SetTexturePart(n"notification_bracket_fg");
        leftBracket.SetNineSliceScale(true);
        leftBracket.SetAnchor(inkEAnchor.LeftFillVerticaly);
        leftBracket.SetSize(new Vector2(22.0, 218.0));
        leftBracket.SetTintColor(new HDRColor(0.25, 0.95, 1.00, 0.70));
        leftBracket.Reparent(container);

        let headerTitle: ref<inkText> = new inkText();
        headerTitle.SetName(n"ChispaBarHeader");
        headerTitle.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        headerTitle.SetFontStyle(n"Semi-Bold");
        headerTitle.SetFontSize(24);
        headerTitle.SetAnchor(inkEAnchor.TopLeft);
        headerTitle.SetMargin(new inkMargin(36.0, 18.0, 0.0, 0.0));
        headerTitle.SetTintColor(new HDRColor(0.28, 0.95, 1.00, 0.96));
        headerTitle.SetText("KIROSHI NEURAL LINK // S.P.A.R.K.Y. v2.0");
        headerTitle.Reparent(container);

        let badge: ref<inkText> = new inkText();
        badge.SetName(n"ChispaBarStatusBadge");
        badge.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        badge.SetFontStyle(n"Semi-Bold");
        badge.SetFontSize(22);
        badge.SetAnchor(inkEAnchor.TopRight);
        badge.SetAnchorPoint(new Vector2(1.00, 0.00));
        badge.SetHorizontalAlignment(textHorizontalAlignment.Right);
        badge.SetMargin(new inkMargin(0.0, 19.0, 36.0, 0.0));
        let isOnline: Bool = IsDefined(this.m_sys) && this.m_sys.IsLiveDaemonOnline();
        if isOnline {
            badge.SetTintColor(new HDRColor(0.22, 1.00, 0.53, 0.95));
            badge.SetText("● LOCAL AI ONLINE");
        } else {
            badge.SetTintColor(new HDRColor(1.00, 0.72, 0.22, 0.95));
            badge.SetText("▲ RUN START_SPARKY_SERVICE.BAT");
        }
        badge.Reparent(container);
        this.m_statusBadge = badge;

        let inputCtrl: ref<ChispaKiroshiTextInput> = ChispaKiroshiTextInput.Create();
        inputCtrl.SetName(n"ChispaKiroshiInput");
        inputCtrl.SetVk186IsAcute(IsDefined(this.m_sys) && this.m_sys.IsLiveVk186Acute());
        inputCtrl.Reparent(container);
        inputCtrl.SetWidth(1308.0);
        inputCtrl.SetDefaultText("Type your message for S.P.A.R.K.Y. and press [ENTER]...");
        let inputRoot: wref<inkWidget> = inputCtrl.GetRootWidget();
        if IsDefined(inputRoot) {
            inputRoot.SetMargin(new inkMargin(36.0, 64.0, 36.0, 0.0));
        }
        inputCtrl.RegisterToCallback(n"OnInput", this, n"OnTextInputChanged");
        this.m_textInput = inputCtrl;

        let footerHints: ref<inkText> = new inkText();
        footerHints.SetName(n"ChispaFooterHints");
        footerHints.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        footerHints.SetFontStyle(n"Medium");
        footerHints.SetFontSize(21);
        footerHints.SetAnchor(inkEAnchor.BottomCenter);
        footerHints.SetAnchorPoint(new Vector2(0.50, 1.00));
        footerHints.SetHorizontalAlignment(textHorizontalAlignment.Center);
        footerHints.SetMargin(new inkMargin(0.0, 0.0, 0.0, 18.0));
        footerHints.SetTintColor(new HDRColor(0.86, 0.90, 0.95, 0.85));
        footerHints.SetText("[ENTER] TRANSMIT    •    [TAB] QUICK TACTICAL SCAN    •    [↑] LAST MESSAGE    •    [ESC] CANCEL");
        footerHints.Reparent(container);
    }

    protected cb func OnAttach() -> Void {
        let game: GameInstance = this.GetGame();
        this.m_openedAt = EngineTime.ToFloat(GameInstance.GetEngineTime(game));

        let uiSystem: ref<UISystem> = GameInstance.GetUISystem(game);
        if IsDefined(uiSystem) {
            // Bloquear controles de movimiento/armas al teclear sin activar inkModalPopupState, para mantener visible el HUD y el holograma.
            uiSystem.PushGameContext(UIGameContext.ModalPopup);
            this.m_contextPushed = true;
        }

        let player: ref<PlayerPuppet> = this.GetPlayer();
        if IsDefined(player) {
            TimeDilationHelper.SetTimeDilationWithProfile(player, "radialMenu", true, true);
            this.m_dilationActive = true;
            GameObject.PlaySoundEvent(player, n"ui_menu_hover");
        }

        super.OnAttach();
        if IsDefined(this.m_textInput) && IsDefined(this.GetGameController()) {
            this.GetGameController().RequestSetFocus(this.m_textInput.GetRootWidget());
            this.m_textInput.RefreshPlaceholderOpacity();
        }
    }

    protected cb func OnShow() -> Void {
        let alphaAnim: ref<inkAnimTransparency> = new inkAnimTransparency();
        alphaAnim.SetStartTransparency(0.00);
        alphaAnim.SetEndTransparency(1.00);
        alphaAnim.SetType(inkanimInterpolationType.Linear);
        alphaAnim.SetMode(inkanimInterpolationMode.EasyOut);
        alphaAnim.SetDuration(0.10);
        let animDef: ref<inkAnimDef> = new inkAnimDef();
        animDef.AddInterpolator(alphaAnim);
        this.m_transitionAnimProxy = this.GetRootWidget().PlayAnimation(animDef);
        this.m_transitionAnimProxy.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnShowFinish");
    }

    protected cb func OnShown() -> Void {
        if !this.m_isClosing && IsDefined(this.m_textInput) && IsDefined(this.GetGameController()) {
            this.GetGameController().RequestSetFocus(this.m_textInput.GetRootWidget());
            this.m_textInput.RefreshPlaceholderOpacity();
        }
    }

    protected cb func OnHide() -> Void {
        let alphaAnim: ref<inkAnimTransparency> = new inkAnimTransparency();
        alphaAnim.SetStartTransparency(1.00);
        alphaAnim.SetEndTransparency(0.00);
        alphaAnim.SetType(inkanimInterpolationType.Linear);
        alphaAnim.SetMode(inkanimInterpolationMode.EasyIn);
        alphaAnim.SetDuration(0.08);
        let animDef: ref<inkAnimDef> = new inkAnimDef();
        animDef.AddInterpolator(alphaAnim);
        this.m_transitionAnimProxy = this.GetRootWidget().PlayAnimation(animDef);
        this.m_transitionAnimProxy.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnHideFinish");
    }

    private final func RestorePlayerState() -> Void {
        if this.m_cleanedUp {
            return;
        }
        this.m_cleanedUp = true;
        if this.m_dilationActive {
            let player: ref<PlayerPuppet> = this.GetPlayer();
            if IsDefined(player) {
                TimeDilationHelper.SetTimeDilationWithProfile(player, "radialMenu", false, false);
            }
            this.m_dilationActive = false;
        }
        if this.m_contextPushed {
            let uiSystem: ref<UISystem> = GameInstance.GetUISystem(this.GetGame());
            if IsDefined(uiSystem) {
                uiSystem.PopGameContext(UIGameContext.ModalPopup);
            }
            this.m_contextPushed = false;
        }
        if IsDefined(this.m_sys) {
            this.m_sys.OnKiroshiPromptClosed(this.m_submitted);
        }
    }

    protected cb func OnDetach() -> Void {
        this.RestorePlayerState();
        super.OnDetach();
    }

    protected cb func OnTextInputChanged(widget: wref<inkWidget>) -> Bool {
        if !IsDefined(this.m_textInput) {
            return false;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(this.GetGame()));
        let current: String = this.m_textInput.GetText();
        // Descarta una posible 'y' residual de la pulsación que abrió el popup.
        if (now - this.m_openedAt) < 0.04 && (Equals(current, "y") || Equals(current, "Y")) {
            this.m_textInput.SetText("");
        }
        this.m_textInput.RefreshPlaceholderOpacity();
        return true;
    }

    public final func SubmitTyped() -> Void {
        if this.m_isClosing {
            return;
        }
        let txt: String = IsDefined(this.m_textInput) ? this.m_textInput.GetText() : "";
        let trimmed: String = StrReplaceAll(txt, "\n", " ");
        trimmed = StrReplaceAll(trimmed, "\r", "");
        if NotEquals(trimmed, "") && IsDefined(this.m_sys) {
            this.m_submitted = true;
            this.m_sys.OnNativePromptSubmitted(trimmed);
            let player: ref<PlayerPuppet> = this.GetPlayer();
            if IsDefined(player) {
                GameObject.PlaySoundEvent(player, n"ui_menu_onpress");
            }
        }
        this.m_isClosing = true;
        this.Close();
    }

    public final func SubmitQuickTactical() -> Void {
        if this.m_isClosing {
            return;
        }
        if IsDefined(this.m_sys) {
            this.m_submitted = true;
            this.m_sys.TriggerQuickTacticalRemark();
        }
        this.m_isClosing = true;
        this.Close();
    }

    public final func RecallLastMessage() -> Void {
        if this.m_isClosing || !IsDefined(this.m_textInput) || !IsDefined(this.m_sys) {
            return;
        }
        let prevMsg: String = this.m_sys.GetLastTypedLiveMessage();
        if NotEquals(prevMsg, "") {
            this.m_textInput.SetText(prevMsg);
            this.m_textInput.SetCaretToEnd();
            this.m_textInput.RefreshPlaceholderOpacity();
        }
    }

    public final func CancelPrompt() -> Void {
        if this.m_isClosing {
            return;
        }
        this.m_submitted = false;
        this.m_isClosing = true;
        this.Close();
    }
}

public class ChispaKeyInputService extends ScriptableService {
    private cb func OnLoad() -> Void {
        let cbSys: ref<CallbackSystem> = GameInstance.GetCallbackSystem();
        if IsDefined(cbSys) {
            cbSys.RegisterCallback(n"Input/Key", this, n"OnGlobalKeyInput");
        }
    }

    private cb func OnGlobalKeyInput(event: ref<KeyInputEvent>) -> Void {
        if !Equals(event.GetAction(), EInputAction.IACT_Press) || event.IsControlDown() || event.IsAltDown() {
            return;
        }
        let game: GameInstance = GetGameInstance();
        let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(game);
        if !IsDefined(sys) {
            return;
        }

        let key: EInputKey = event.GetKey();
        if sys.IsKiroshiPromptOpen() {
            if Equals(key, EInputKey.IK_Enter) {
                sys.ConfirmKiroshiPrompt();
            } else if Equals(key, EInputKey.IK_Tab) {
                sys.SubmitTacticalFromKiroshiPrompt();
            } else if Equals(key, EInputKey.IK_Up) {
                sys.RecallLastKiroshiPrompt();
            } else if Equals(key, EInputKey.IK_Escape) {
                sys.CancelKiroshiPrompt();
            }
            return;
        }

        if NotEquals(key, EInputKey.IK_Y) && NotEquals(key, EInputKey.IK_U) {
            return;
        }

        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        if IsDefined(qs) && qs.GetFact(n"chispa_disable_default_yu_keys") > 0 {
            return;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !ChispaSessionService.IsSessionReady()
            || !sys.IsGameplayReady(player)
            || !sys.IsInFullGameplayTier(player)
            || sys.IsCetOverlayOpen()
            || sys.IsInSystemOrPauseMenu()
            || sys.IsPhoneOverlayOpen()
            || sys.IsDialogActive()
            || sys.m_isPlayingDialogueSequence
            || sys.IsExternalPhoneCallBusy() {
            return;
        }

        if Equals(key, EInputKey.IK_Y) {
            sys.OpenKiroshiPrompt();
        } else if Equals(key, EInputKey.IK_U) {
            sys.TriggerQuickTacticalRemark();
        }
    }
}

public class ChispaLiveSubtitleCallback extends DelayCallback {
    public let handler: wref<ChispaLiveCompanionHandler>;
    public let token: Int32;
    public let nextPageIndex: Int32;

    public func Call() -> Void {
        if IsDefined(this.handler) {
            this.handler.AdvanceLiveSubtitlePage(this.token, this.nextPageIndex);
        }
    }
}

public class ChispaLiveCompanionHandler extends IScriptable {
    private let m_sys: wref<ChispaSystem>;
    private let m_isSpeaking: Bool;
    private let m_lastScannedEntityId: EntityID;
    private let m_lastScannedName: String;
    private let m_lastScannedAffiliation: String;
    private let m_lastScannedIsBoss: Bool;
    private let m_lastScannedRarity: String;
    private let m_lastScannedSeq: Int32;
    private let m_lastScannedAt: Float;
    private let m_shardPopupOpen: Bool;
    private let m_lastShardSeq: Int32;
    private let m_lastShardTitle: String;
    private let m_lastShardText: String;
    private let m_subtitleSeq: Uint64;
    private let m_activeCruid: CRUID;
    private let m_hasActiveCruid: Bool;
    private let m_liveSubToken: Int32;
    private let m_liveSubCurrentPageIdx: Int32;
    private let m_liveSubPages: array<String>;
    private let m_liveSubPageDurs: array<Float>;
    private let m_lastPacketAt: Float;

    private let m_outReqSeq: Int32;
    private let m_outReqAction: String;
    private let m_outReqText: String;
    private let m_daemonOnline: Bool;
    private let m_vk186IsAcute: Bool;
    private let m_cetOverlayOpen: Bool;
    private let m_promptOpen: Bool;
    private let m_waitingReply: Bool;
    private let m_waitingSince: Float;
    private let m_lastTacticalAt: Float;
    private let m_lastTypedText: String;
    private let m_activePopup: ref<ChispaKiroshiInputPopup>;
    private let m_cachedLifepath: String;
    private let m_cachedLevel: Int32;
    private let m_cachedStreetCred: Int32;
    private let m_cachedActPhase: Int32;
    private let m_cachedMemUid: Int32;
    private let m_cachedPtSec: Int32;
    private let m_cachedSeasonStage: Int32;
    private let m_cachedEp05Done: Int32;
    private let m_cachedEp05Ending: Int32;

    public final func Init(sys: ref<ChispaSystem>) -> Void {
        this.m_sys = sys;
    }

    public final func ResetRuntime() -> Void {
        if IsDefined(this.m_activePopup) {
            this.m_activePopup.CancelPrompt();
            this.m_activePopup = null;
        }
        this.HideActiveLiveSubtitle();
        this.m_isSpeaking = false;
        this.m_lastScannedEntityId = new EntityID();
        this.m_lastScannedName = "";
        this.m_lastScannedAffiliation = "";
        this.m_lastScannedIsBoss = false;
        this.m_lastScannedRarity = "";
        this.m_lastScannedSeq = 0;
        this.m_lastScannedAt = 0.00;
        this.m_shardPopupOpen = false;
        this.m_lastShardSeq = 0;
        this.m_lastShardTitle = "";
        this.m_lastShardText = "";
        this.m_hasActiveCruid = false;
        this.m_liveSubToken = 0;
        this.m_liveSubCurrentPageIdx = -1;
        ArrayClear(this.m_liveSubPages);
        ArrayClear(this.m_liveSubPageDurs);
        this.m_lastPacketAt = 0.00;
        this.m_promptOpen = false;
        this.m_waitingReply = false;
        this.m_waitingSince = 0.00;
        this.m_lastTacticalAt = 0.00;
        this.m_cachedLifepath = "";
        this.m_cachedLevel = 1;
        this.m_cachedStreetCred = 1;
        this.m_cachedActPhase = 1;
        this.m_cachedMemUid = 0;
        this.m_cachedPtSec = 0;
        this.m_cachedSeasonStage = 0;
        this.m_cachedEp05Done = 0;
        this.m_cachedEp05Ending = 0;
    }

    public final func IsSpeaking() -> Bool {
        return this.m_isSpeaking;
    }

    public final func IsPromptOpen() -> Bool {
        return this.m_promptOpen;
    }

    public final func IsWaitingReply() -> Bool {
        return this.m_waitingReply;
    }

    public final func IsBusy() -> Bool {
        return this.m_isSpeaking || this.m_promptOpen || this.m_waitingReply;
    }

    public final func SetCetOverlayOpen(isOpen: Bool) -> Void {
        this.m_cetOverlayOpen = isOpen;
    }

    public final func IsCetOverlayOpen() -> Bool {
        return this.m_cetOverlayOpen;
    }

    public final func SetDaemonOnline(online: Bool) -> Void {
        this.m_daemonOnline = online;
    }

    public final func IsDaemonOnline() -> Bool {
        return this.m_daemonOnline;
    }

    public final func SetVk186IsAcute(isAcute: Bool) -> Void {
        this.m_vk186IsAcute = isAcute;
    }

    public final func IsVk186Acute() -> Bool {
        return this.m_vk186IsAcute;
    }

    public final func GetPendingReqSeq() -> Int32 {
        return this.m_outReqSeq;
    }

    public final func GetPendingReqAction() -> String {
        return this.m_outReqAction;
    }

    public final func GetPendingReqText() -> String {
        return this.m_outReqText;
    }

    public final func GetLastTypedText() -> String {
        return this.m_lastTypedText;
    }

    public final func GetHoloSubtitleStatus() -> String {
        if this.m_promptOpen {
            return "NEURAL CHANNEL // LISTENING TO V";
        }
        if this.m_waitingReply {
            return "PROCESSING NEURAL LINK...";
        }
        if this.m_isSpeaking {
            return "LOCAL AI LINK // LIVE";
        }
        if IsDefined(this.m_sys) {
            return this.m_sys.GetLoc(n"ch_holo_telemetry_sub", "DRILL SERGEANT // UNFILTERED");
        }
        return "DRILL SERGEANT // UNFILTERED";
    }

    private final func QueueOutgoingRequest(action: String, text: String) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        this.m_outReqSeq += 1;
        this.m_outReqAction = action;
        this.m_outReqText = text;

        if Equals(action, "chat") || Equals(action, "tactical") {
            let game: GameInstance = this.m_sys.GetGameInstance();
            this.m_waitingReply = true;
            this.m_waitingSince = EngineTime.ToFloat(GameInstance.GetEngineTime(game));
            if this.m_sys.IsVideocallModeEnabled() {
                this.m_sys.OpenDirectHoloFeed();
            }
            this.m_sys.RefreshHoloStatusLabel();

            if !this.m_daemonOnline {
                this.ShowTransientLiveLine("LOCAL AI OFFLINE — Run start_sparky_service.bat to activate SPARKY's live voice.", 4.50);
            }
        }
    }

    private final func HideCurrentLiveSubtitleElementOnly() -> Void {
        if !this.m_hasActiveCruid || !IsDefined(this.m_sys) {
            return;
        }
        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(this.m_sys.GetGameInstance()).Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            let hideIds: array<CRUID>;
            ArrayPush(hideIds, this.m_activeCruid);
            board.SetVariant(GetAllBlackboardDefs().UIGameData.HideDialogLine, ToVariant(hideIds), true);
        }
        this.m_hasActiveCruid = false;
    }

    private final func EmitLiveSubtitleLine(cruid: CRUID, pageText: String, pageDur: Float) -> Void {
        if !IsDefined(this.m_sys) || Equals(pageText, "") {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !IsDefined(player) {
            return;
        }
        let line: scnDialogLineData;
        line.id = cruid;
        line.duration = MaxF(0.25, pageDur);
        line.isPersistent = false;
        line.speaker = player;
        line.speakerName = this.m_sys.GetLoc(n"ch_speaker_chispa", "SPARKY");
        line.text = pageText;
        line.type = this.m_sys.IsVideocallModeEnabled() ? scnDialogLineType.Holocall : scnDialogLineType.Regular;

        let board: ref<IBlackboard> = GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UIGameData);
        if IsDefined(board) {
            let lines: array<scnDialogLineData>;
            ArrayPush(lines, line);
            board.SetVariant(GetAllBlackboardDefs().UIGameData.ShowDialogLine, ToVariant(lines), true);
        }
    }

    public final func OnUiMenuExited() -> Void {
        if !this.m_isSpeaking
            || !this.m_hasActiveCruid
            || this.m_liveSubCurrentPageIdx < 0
            || this.m_liveSubCurrentPageIdx >= ArraySize(this.m_liveSubPages) {
            return;
        }
        let pageDur: Float = (this.m_liveSubCurrentPageIdx < ArraySize(this.m_liveSubPageDurs))
            ? this.m_liveSubPageDurs[this.m_liveSubCurrentPageIdx]
            : 2.50;
        this.EmitLiveSubtitleLine(
            this.m_activeCruid,
            this.m_liveSubPages[this.m_liveSubCurrentPageIdx],
            pageDur
        );
    }

    public final func AdvanceLiveSubtitlePage(token: Int32, pageIndex: Int32) -> Void {
        if token != this.m_liveSubToken || !IsDefined(this.m_sys) {
            return;
        }
        this.HideCurrentLiveSubtitleElementOnly();
        if pageIndex >= ArraySize(this.m_liveSubPages) {
            this.m_liveSubCurrentPageIdx = -1;
            ArrayClear(this.m_liveSubPages);
            ArrayClear(this.m_liveSubPageDurs);
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let pageDur: Float = (pageIndex < ArraySize(this.m_liveSubPageDurs)) ? this.m_liveSubPageDurs[pageIndex] : 2.50;
        let isLastPage: Bool = (pageIndex + 1) >= ArraySize(this.m_liveSubPages);

        this.m_liveSubCurrentPageIdx = pageIndex;
        this.m_subtitleSeq += 1ul;
        this.m_activeCruid = CreateCRUID(8899202200ul + this.m_subtitleSeq);
        this.m_hasActiveCruid = true;

        this.EmitLiveSubtitleLine(this.m_activeCruid, this.m_liveSubPages[pageIndex], pageDur);

        if !isLastPage {
            let subCb: ref<ChispaLiveSubtitleCallback> = new ChispaLiveSubtitleCallback();
            subCb.handler = this;
            subCb.token = token;
            subCb.nextPageIndex = pageIndex + 1;
            GameInstance.GetDelaySystem(game).DelayCallback(subCb, MaxF(0.25, pageDur), false);
        }
    }

    private final func ShowTransientLiveLine(text: String, durationSec: Float) -> Void {
        if !IsDefined(this.m_sys) || Equals(text, "") {
            return;
        }
        let pages: array<String> = this.m_sys.PaginateSubtitleText(text, 148);
        let count: Int32 = ArraySize(pages);
        if count == 0 {
            return;
        }
        this.HideActiveLiveSubtitle();
        let totalDur: Float = MaxF(2.50, durationSec);
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
        this.m_liveSubPages = pages;
        this.m_liveSubPageDurs = durs;
        this.AdvanceLiveSubtitlePage(this.m_liveSubToken, 0);
    }

    public final func OpenPrompt() -> Void {
        if !IsDefined(this.m_sys) || this.m_promptOpen {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if !this.m_sys.IsGameplayReady(player)
            || !this.m_sys.IsInFullGameplayTier(player)
            || this.m_sys.m_isPlayingDialogueSequence
            || this.m_sys.IsDialogActive()
            || this.m_sys.IsExternalPhoneCallBusy()
            || this.m_sys.IsPhoneOverlayOpen() {
            return;
        }

        let popupMgr: ref<CustomPopupManager> = CustomPopupManager.GetInstance();
        if !IsDefined(popupMgr) || !popupMgr.IsInitialized() {
            return;
        }

        if this.m_isSpeaking {
            this.QueueOutgoingRequest("stop", "");
            this.m_isSpeaking = false;
            this.HideActiveLiveSubtitle();
        }
        this.m_waitingReply = false;
        this.m_promptOpen = true;
        if this.m_sys.IsVideocallModeEnabled() {
            this.m_sys.OpenDirectHoloFeed();
        }
        this.m_sys.RefreshHoloStatusLabel();

        let popup: ref<ChispaKiroshiInputPopup> = new ChispaKiroshiInputPopup();
        popup.Setup(this.m_sys);
        this.m_activePopup = popup;
        popupMgr.ShowPopup(popup);
    }

    public final func ConfirmPrompt() -> Void {
        if IsDefined(this.m_activePopup) {
            this.m_activePopup.SubmitTyped();
        }
    }

    public final func SubmitTacticalFromPrompt() -> Void {
        if IsDefined(this.m_activePopup) {
            this.m_activePopup.SubmitQuickTactical();
        }
    }

    public final func RecallLastPrompt() -> Void {
        if IsDefined(this.m_activePopup) {
            this.m_activePopup.RecallLastMessage();
        }
    }

    public final func CancelPrompt() -> Void {
        if IsDefined(this.m_activePopup) {
            this.m_activePopup.CancelPrompt();
        }
    }

    public final func OnPromptSubmitted(text: String) -> Void {
        this.m_lastTypedText = text;
        this.QueueOutgoingRequest("chat", text);
    }

    public final func OnPromptClosed(submitted: Bool) -> Void {
        this.m_promptOpen = false;
        this.m_activePopup = null;
        if !IsDefined(this.m_sys) {
            return;
        }
        if !submitted && !this.m_isSpeaking && !this.m_waitingReply {
            if this.m_sys.IsDirectHoloFeedOpenInternal()
                && !this.m_sys.m_isPlayingDialogueSequence
                && !this.m_sys.IsAnyEpisodeInFinalTalkStage() {
                this.m_sys.CloseDirectHoloFeed();
            }
        }
        this.m_sys.RefreshHoloStatusLabel();
    }

    public final func TriggerQuickTacticalRemark() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let now: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(game));
        if (now - this.m_lastTacticalAt) < 1.20 {
            return;
        }
        this.m_lastTacticalAt = now;
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        if IsDefined(player) {
            GameObject.PlaySoundEvent(player, n"ui_menu_hover");
        }
        this.QueueOutgoingRequest("tactical", "[AUTO_SITUACION]");
    }

    public final func ForceAbortForScriptedScene() -> Void {
        if IsDefined(this.m_activePopup) {
            this.m_activePopup.CancelPrompt();
            this.m_activePopup = null;
        }
        if this.m_isSpeaking || this.m_waitingReply {
            this.QueueOutgoingRequest("stop", "");
        }
        this.m_waitingReply = false;
        this.m_isSpeaking = false;
        this.m_promptOpen = false;
        this.HideActiveLiveSubtitle();
    }

    public final func OnShardPopupOpened(title: String, body: String) -> Void {
        this.m_shardPopupOpen = true;
        if NotEquals(title, "") || NotEquals(body, "") {
            let cleanTitle: String = StrLen(title) > 120 ? StrLeft(title, 120) : title;
            let cleanBody: String = StrLen(body) > 550 ? StrLeft(body, 550) : body;
            this.m_lastShardTitle = cleanTitle;
            this.m_lastShardText = cleanBody;
            this.m_lastShardSeq += 1;
        }
    }

    public final func OnShardPopupClosed() -> Void {
        this.m_shardPopupOpen = false;
    }

    public final func RecordScannedPuppet(npc: ref<NPCPuppet>) -> Void {
        if !IsDefined(npc) || npc.IsPlayer() {
            return;
        }
        let displayName: String = npc.GetDisplayName();
        if Equals(displayName, "") {
            return;
        }
        let affText: String = "";
        let charRec: wref<Character_Record> = TweakDBInterface.GetCharacterRecord(npc.GetRecordID());
        if IsDefined(charRec) {
            let affRec: wref<Affiliation_Record> = charRec.Affiliation();
            if IsDefined(affRec) {
                let locAff: String = GetLocalizedTextByKey(affRec.LocalizedName());
                if NotEquals(locAff, "") {
                    affText = locAff;
                } else {
                    affText = ToString(affRec.EnumName());
                }
            }
        }
        let game: GameInstance = npc.GetGame();
        let now: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(game));
        let eid: EntityID = npc.GetEntityID();
        if NotEquals(eid, this.m_lastScannedEntityId) || (now - this.m_lastScannedAt) > 12.00 {
            this.m_lastScannedSeq += 1;
        }
        this.m_lastScannedEntityId = eid;
        this.m_lastScannedName = displayName;
        this.m_lastScannedAffiliation = affText;
        this.m_lastScannedIsBoss = npc.IsBoss();
        this.m_lastScannedRarity = ToString(npc.GetNPCRarity());
        this.m_lastScannedAt = now;
    }

    private final func EscapeJson(raw: String) -> String {
        if Equals(raw, "") {
            return "";
        }
        // Escapar "\" primero para no duplicar escapes generados después.
        let s: String = StrReplaceAll(raw, "\\", "\\\\");
        s = StrReplaceAll(s, "\"", "\\\"");
        s = StrReplaceAll(s, "\n", " ");
        s = StrReplaceAll(s, "\r", "");
        s = StrReplaceAll(s, "\t", " ");
        return s;
    }

    public final func BuildTelemetryJson() -> String {
        if !IsDefined(this.m_sys) {
            return "{\"session_ready\":false,\"full_gameplay\":false,\"in_menu\":true,\"blocking_scene_or_call\":true}";
        }
        let game: GameInstance = this.m_sys.GetGameInstance();
        let sessionReady: Bool = ChispaSessionService.IsSessionReady();
        let sessionLoadSeq: Int32 = ChispaSessionService.GetSessionLoadSeq();
        let inMenu: Bool = this.m_sys.IsInSystemOrPauseMenu();
        if inMenu {
            let jmMenu: String = "{";
            jmMenu += "\"session_ready\":" + (sessionReady ? "true" : "false");
            jmMenu += ",\"session_load_seq\":" + ToString(sessionLoadSeq);
            jmMenu += ",\"mem_uid\":" + ToString(this.m_cachedMemUid);
            jmMenu += ",\"playthrough_sec\":" + ToString(this.m_cachedPtSec);
            jmMenu += ",\"full_gameplay\":false,\"in_menu\":true,\"blocking_scene_or_call\":true";
            jmMenu += ",\"loading_or_fast_travel\":" + (this.m_sys.IsFastTravelOrLoadingActive() ? "true" : "false");
            jmMenu += ",\"in_combat\":false,\"in_vehicle\":false,\"hp_pct\":100,\"wanted_stars\":0";
            jmMenu += ",\"lifepath\":\"" + this.EscapeJson(this.m_cachedLifepath) + "\"";
            jmMenu += ",\"level\":" + ToString(Max(1, this.m_cachedLevel));
            jmMenu += ",\"street_cred\":" + ToString(Max(1, this.m_cachedStreetCred));
            jmMenu += ",\"act_phase\":" + ToString(Max(1, this.m_cachedActPhase));
            jmMenu += ",\"shard_popup_open\":" + (this.m_shardPopupOpen ? "true" : "false");
            jmMenu += ",\"last_shard_seq\":" + ToString(this.m_lastShardSeq);
            jmMenu += ",\"season_stage\":" + ToString(this.m_cachedSeasonStage);
            jmMenu += ",\"ep05_done\":" + ToString(this.m_cachedEp05Done);
            jmMenu += ",\"ep05_ending\":" + ToString(this.m_cachedEp05Ending);
            jmMenu += "}";
            return jmMenu;
        }
        let player: ref<PlayerPuppet> = GameInstance.GetPlayerSystem(game).GetLocalPlayerMainGameObject() as PlayerPuppet;
        let fullGameplay: Bool = this.m_sys.IsGameplayReady(player) && this.m_sys.IsInFullGameplayTier(player);
        let blocking: Bool = !sessionReady
            || !IsDefined(player)
            || this.m_shardPopupOpen
            || this.m_sys.IsExternalPhoneCallBusy()
            || this.m_sys.m_isPlayingDialogueSequence
            || this.m_sys.IsDialogActive();

        let inCombat: Bool = false;
        let inVehicle: Bool = false;
        let hpPct: Int32 = 100;
        let wantedStars: Int32 = 0;
        let districtName: String = "";
        let weaponName: String = "";
        let scannedSummary: String = "";
        let scannedBoss: Bool = false;
        let scannedRarity: String = "";
        let lifepathStr: String = "";
        let playerLevel: Int32 = 1;
        let streetCred: Int32 = 1;
        let gameHourStr: String = "";
        let actPhase: Int32 = 1;
        let trackedQuestId: String = "";
        let trackedQuestTitle: String = "";
        let trackedQuestObj: String = "";

        if IsDefined(player) {
            inCombat = player.IsInCombat();
            inVehicle = VehicleComponent.IsMountedToVehicle(game, player);

            let poolSys: ref<StatPoolsSystem> = GameInstance.GetStatPoolsSystem(game);
            if IsDefined(poolSys) {
                let hpVal: Float = poolSys.GetStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, true);
                hpPct = Clamp(RoundF(hpVal), 0, 100);
            }

            let statsSys: ref<StatsSystem> = GameInstance.GetStatsSystem(game);
            if IsDefined(statsSys) {
                let pStatsId: StatsObjectID = Cast<StatsObjectID>(player.GetEntityID());
                playerLevel = Max(1, RoundF(statsSys.GetStatValue(pStatsId, gamedataStatType.Level)));
                streetCred = Max(1, RoundF(statsSys.GetStatValue(pStatsId, gamedataStatType.StreetCred)));
            }

            let devData: ref<PlayerDevelopmentData> = PlayerDevelopmentSystem.GetData(player);
            if IsDefined(devData) {
                lifepathStr = ToString(devData.GetLifePath());
            }

            let ps: ref<PreventionSystem> = GameInstance.GetScriptableSystemsContainer(game).Get(n"PreventionSystem") as PreventionSystem;
            if IsDefined(ps) {
                wantedStars = Cast<Int32>(ps.GetHeatStageAsInt());
                let dist: wref<District> = ps.GetCurrentDistrict();
                if IsDefined(dist) {
                    let distRec: ref<District_Record> = dist.GetDistrictRecord();
                    if IsDefined(distRec) {
                        districtName = GetLocalizedText(distRec.LocalizedName());
                    }
                }
            }

            let wpn: ref<WeaponObject> = GameObject.GetActiveWeapon(player);
            if IsDefined(wpn) {
                let wpnRec: wref<Item_Record> = TweakDBInterface.GetItemRecord(ItemID.GetTDBID(wpn.GetItemID()));
                if IsDefined(wpnRec) {
                    weaponName = GetLocalizedTextByKey(wpnRec.DisplayName());
                }
            }

            let now: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(game));
            if NotEquals(this.m_lastScannedName, "") && (now - this.m_lastScannedAt) <= 60.00 {
                if NotEquals(this.m_lastScannedAffiliation, "") {
                    scannedSummary = this.m_lastScannedName + " (" + this.m_lastScannedAffiliation + ")";
                } else {
                    scannedSummary = this.m_lastScannedName;
                }
                scannedBoss = this.m_lastScannedIsBoss;
                scannedRarity = this.m_lastScannedRarity;
            }
        }

        let gt: GameTime = GameInstance.GetTimeSystem(game).GetGameTime();
        let hr: Int32 = GameTime.Hours(gt);
        let mn: Int32 = GameTime.Minutes(gt);
        gameHourStr = (hr < 10 ? "0" : "") + ToString(hr) + ":" + (mn < 10 ? "0" : "") + ToString(mn);

        let jm: ref<JournalManager> = GameInstance.GetJournalManager(game);
        if IsDefined(jm) {
            if this.m_cachedActPhase >= 2 {
                actPhase = 2;
            } else {
                let qAct1: wref<JournalEntry> = jm.GetEntryByString("quests/main_quest/act_01/q101_resurrection", "gameJournalQuest");
                if IsDefined(qAct1) {
                    let stAct1: gameJournalEntryState = jm.GetEntryState(qAct1);
                    if Equals(stAct1, gameJournalEntryState.Active) || Equals(stAct1, gameJournalEntryState.Succeeded) {
                        actPhase = 2;
                    }
                }
                this.m_cachedActPhase = actPhase;
            }
            let tracked: wref<JournalEntry> = jm.GetTrackedEntry();
            let qObj: wref<JournalQuestObjective> = tracked as JournalQuestObjective;
            if IsDefined(qObj) {
                trackedQuestObj = GetLocalizedText(qObj.GetDescription());
                let phaseEntry: wref<JournalEntry> = jm.GetParentEntry(qObj);
                if IsDefined(phaseEntry) {
                    let questEntry: wref<JournalQuest> = jm.GetParentEntry(phaseEntry) as JournalQuest;
                    if IsDefined(questEntry) {
                        trackedQuestId = questEntry.GetId();
                        trackedQuestTitle = GetLocalizedText(questEntry.GetTitle(jm));
                    }
                }
            } else {
                let directQuest: wref<JournalQuest> = tracked as JournalQuest;
                if IsDefined(directQuest) {
                    trackedQuestId = directQuest.GetId();
                    trackedQuestTitle = GetLocalizedText(directQuest.GetTitle(jm));
                }
            }
        }

        let qs: ref<QuestsSystem> = GameInstance.GetQuestsSystem(game);
        let playthroughSec: Float = EngineTime.ToFloat(GameInstance.GetPlaythroughTime(game));
        let ptSecInt: Int32 = Max(0, RoundF(playthroughSec));
        let seasonStage: Int32 = 0;
        let ep05Done: Int32 = 0;
        let ep05Ending: Int32 = 0;
        let memUid: Int32 = 0;
        if IsDefined(qs) {
            seasonStage = qs.GetFact(n"chispa_season_stage");
            ep05Done = qs.GetFact(n"chispa_ep05_done");
            ep05Ending = qs.GetFact(n"chispa_ep05_ending");
            memUid = qs.GetFact(n"chispa_mem_uid");
            if memUid <= 0 && sessionReady && fullGameplay && IsDefined(player) {
                let lpCode: Uint64 = Equals(lifepathStr, "Corporate")
                    ? 1ul
                    : (Equals(lifepathStr, "Nomad") ? 2ul : (Equals(lifepathStr, "StreetKid") ? 3ul : 4ul));
                let femCode: Uint64 = Equals(player.GetResolvedGenderName(), n"Female") ? 1ul : 0ul;
                let h: Uint64 = 2166136261ul;
                h = (h ^ lpCode) * 16777619ul;
                h = (h ^ femCode) * 16777619ul;
                h = (h ^ Cast<Uint64>(Clamp(playerLevel, 1, 99))) * 16777619ul;
                h = (h ^ Cast<Uint64>(Clamp(streetCred, 1, 99))) * 16777619ul;
                h = (h ^ Cast<Uint64>(ptSecInt / 120)) * 16777619ul;
                h = (h ^ Cast<Uint64>(Max(0, GameTime.GetSeconds(gt)) / 60)) * 16777619ul;
                h = (h ^ Cast<Uint64>(Max(0, seasonStage + ep05Done * 1000 + ep05Ending * 100))) * 16777619ul;
                let minted: Int32 = Cast<Int32>((h % 899900000ul) + 100000ul);
                qs.SetFact(n"chispa_mem_uid", minted);
                memUid = minted;
            }
        }

        if NotEquals(lifepathStr, "") {
            this.m_cachedLifepath = lifepathStr;
        }
        this.m_cachedLevel = playerLevel;
        this.m_cachedStreetCred = streetCred;
        this.m_cachedActPhase = actPhase;
        this.m_cachedMemUid = memUid;
        this.m_cachedPtSec = ptSecInt;
        this.m_cachedSeasonStage = seasonStage;
        this.m_cachedEp05Done = ep05Done;
        this.m_cachedEp05Ending = ep05Ending;

        let j: String = "{";
        j += "\"session_ready\":" + (sessionReady ? "true" : "false");
        j += ",\"session_load_seq\":" + ToString(sessionLoadSeq);
        j += ",\"mem_uid\":" + ToString(memUid);
        j += ",\"playthrough_sec\":" + ToString(ptSecInt);
        j += ",\"full_gameplay\":" + (fullGameplay ? "true" : "false");
        j += ",\"in_menu\":" + (inMenu ? "true" : "false");
        j += ",\"blocking_scene_or_call\":" + (blocking ? "true" : "false");
        j += ",\"loading_or_fast_travel\":" + (this.m_sys.IsFastTravelOrLoadingActive() ? "true" : "false");
        j += ",\"in_combat\":" + (inCombat ? "true" : "false");
        j += ",\"in_vehicle\":" + (inVehicle ? "true" : "false");
        j += ",\"hp_pct\":" + ToString(hpPct);
        j += ",\"wanted_stars\":" + ToString(wantedStars);
        j += ",\"district\":\"" + this.EscapeJson(districtName) + "\"";
        j += ",\"weapon\":\"" + this.EscapeJson(weaponName) + "\"";
        j += ",\"scanned_target\":\"" + this.EscapeJson(scannedSummary) + "\"";
        j += ",\"scanned_is_boss\":" + (scannedBoss ? "true" : "false");
        j += ",\"scanned_rarity\":\"" + this.EscapeJson(scannedRarity) + "\"";
        j += ",\"scanned_seq\":" + ToString(this.m_lastScannedSeq);
        j += ",\"lifepath\":\"" + this.EscapeJson(lifepathStr) + "\"";
        j += ",\"level\":" + ToString(playerLevel);
        j += ",\"street_cred\":" + ToString(streetCred);
        j += ",\"game_hour\":\"" + this.EscapeJson(gameHourStr) + "\"";
        j += ",\"act_phase\":" + ToString(actPhase);
        j += ",\"tracked_quest_id\":\"" + this.EscapeJson(trackedQuestId) + "\"";
        j += ",\"tracked_quest_title\":\"" + this.EscapeJson(trackedQuestTitle) + "\"";
        j += ",\"tracked_quest_obj\":\"" + this.EscapeJson(trackedQuestObj) + "\"";
        j += ",\"shard_popup_open\":" + (this.m_shardPopupOpen ? "true" : "false");
        j += ",\"last_shard_seq\":" + ToString(this.m_lastShardSeq);
        j += ",\"last_shard_title\":\"" + this.EscapeJson(this.m_lastShardTitle) + "\"";
        j += ",\"last_shard_text\":\"" + this.EscapeJson(this.m_lastShardText) + "\"";
        j += ",\"season_stage\":" + ToString(seasonStage);
        j += ",\"ep05_done\":" + ToString(ep05Done);
        j += ",\"ep05_ending\":" + ToString(ep05Ending);
        j += "}";
        return j;
    }

    public final func HideActiveLiveSubtitle() -> Void {
        this.m_liveSubToken += 1;
        this.m_liveSubCurrentPageIdx = -1;
        ArrayClear(this.m_liveSubPages);
        ArrayClear(this.m_liveSubPageDurs);
        this.HideCurrentLiveSubtitleElementOnly();
    }

    public final func OnPacket(stateCode: Int32, subtitleText: String, durationSec: Float) -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        this.m_waitingReply = false;
        if stateCode == 0 {
            this.m_isSpeaking = false;
            this.HideActiveLiveSubtitle();
            if this.m_sys.IsDirectHoloFeedOpenInternal()
                && !this.m_promptOpen
                && !this.m_sys.m_isPlayingDialogueSequence
                && !this.m_sys.IsAnyEpisodeInFinalTalkStage() {
                this.m_sys.CloseDirectHoloFeed();
            }
            this.m_sys.RefreshHoloStatusLabel();
            return;
        }

        if this.m_sys.m_isPlayingDialogueSequence || this.m_sys.IsExternalPhoneCallBusy() {
            this.HideActiveLiveSubtitle();
            this.m_isSpeaking = false;
            this.m_sys.RefreshHoloStatusLabel();
            return;
        }

        let game: GameInstance = this.m_sys.GetGameInstance();
        let wasSpeaking: Bool = this.m_isSpeaking;
        this.m_isSpeaking = true;
        this.m_lastPacketAt = EngineTime.ToFloat(GameInstance.GetEngineTime(game));

        if stateCode == 1 && !wasSpeaking {
            this.m_sys.PlaySfx(n"ch_sfx_kiroshi_lock");
        }
        if this.m_sys.IsVideocallModeEnabled() {
            this.m_sys.OpenDirectHoloFeed();
        }
        this.m_sys.RefreshHoloStatusLabel();

        this.ShowTransientLiveLine(subtitleText, durationSec);
    }

    public final func WatchdogTick() -> Void {
        if !IsDefined(this.m_sys) {
            return;
        }
        let now: Float = EngineTime.ToFloat(GameInstance.GetEngineTime(this.m_sys.GetGameInstance()));

        if this.m_promptOpen {
            if this.m_sys.IsInSystemOrPauseMenu()
                || this.m_sys.IsExternalPhoneCallBusy()
                || this.m_sys.m_isPlayingDialogueSequence
                || this.m_sys.IsDialogActive() {
                this.CancelPrompt();
            }
        }

        if this.m_waitingReply {
            let timeoutLimit: Float = this.m_daemonOnline ? 12.00 : 4.50;
            if (now - this.m_waitingSince) > timeoutLimit
                || this.m_sys.IsExternalPhoneCallBusy()
                || this.m_sys.m_isPlayingDialogueSequence {
                this.m_waitingReply = false;
                if !this.m_isSpeaking
                    && !this.m_promptOpen
                    && this.m_sys.IsDirectHoloFeedOpenInternal()
                    && !this.m_sys.m_isPlayingDialogueSequence
                    && !this.m_sys.IsAnyEpisodeInFinalTalkStage() {
                    this.m_sys.CloseDirectHoloFeed();
                }
                this.m_sys.RefreshHoloStatusLabel();
            }
        }

        if this.m_isSpeaking {
            if this.m_sys.IsExternalPhoneCallBusy()
                || this.m_sys.m_isPlayingDialogueSequence
                || (now - this.m_lastPacketAt) > 18.00 {
                this.OnPacket(0, "", 0.00);
            }
        }
    }
}
