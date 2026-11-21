// Protocolo CHISPA / SPARKY Protocol — Telemetría Activa en Vivo (Kiroshi & Combate)
module ChispaNC

// ---------------------------------------------------------------------------
// 1. Escáner Kiroshi Personalizado y Reacción en Tiempo Real
// ---------------------------------------------------------------------------

@wrapMethod(NPCPuppet)
public const func CompileScannerChunks() -> Bool {
    let ok: Bool = wrappedMethod();
    let liveSys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGame());
    if IsDefined(liveSys) && IsDefined(liveSys.m_live) {
        liveSys.m_live.RecordScannedPuppet(this);
    }
    let recID: TweakDBID = this.GetRecordID();
    let isRocco: Bool = Equals(recID, t"Character.Chispa_Ep00_Rocco");
    let isTino: Bool = Equals(recID, t"Character.Chispa_Ep00_Tino");
    let isKostya: Bool = Equals(recID, t"Character.Chispa_Ep01_Kostya");
    let isVadik: Bool = Equals(recID, t"Character.Chispa_Ep01_Vadik");
    let isZina: Bool = Equals(recID, t"Character.Chispa_Ep01_Zina");
    let isKrag: Bool = Equals(recID, t"Character.Chispa_Ep02_Krag");
    let isVex: Bool = Equals(recID, t"Character.Chispa_Ep02_Vex");
    let isTuerca: Bool = Equals(recID, t"Character.Chispa_Ep02_Tuerca");
    let isAiko: Bool = Equals(recID, t"Character.Chispa_Ep03_Aiko");
    let isKenji: Bool = Equals(recID, t"Character.Chispa_Ep03_Kenji");
    let isRen: Bool = Equals(recID, t"Character.Chispa_Ep03_Ren");
    let isBuck: Bool = Equals(recID, t"Character.Chispa_Ep04_Buck");
    let isTammy: Bool = Equals(recID, t"Character.Chispa_Ep04_Tammy");
    let isMateo: Bool = Equals(recID, t"Character.Chispa_Ep04_Mateo");
    let isTiLuc: Bool = Equals(recID, t"Character.Chispa_Ep05_TiLuc");
    let isMireille: Bool = Equals(recID, t"Character.Chispa_Ep05_Mireille");
    let isBrutus: Bool = Equals(recID, t"Character.Chispa_Ep05_Brutus");
    if !isRocco && !isTino && !isKostya && !isVadik && !isZina && !isKrag && !isVex && !isTuerca && !isAiko && !isKenji && !isRen && !isBuck && !isTammy && !isMateo && !isTiLuc && !isMireille && !isBrutus {
        return ok;
    }

    let scannerBB: wref<IBlackboard> = GameInstance.GetBlackboardSystem(this.GetGame()).Get(GetAllBlackboardDefs().UI_ScannerModules);
    if IsDefined(scannerBB) {
        let customDescs: array<String>;
        let descChunk: ref<ScannerDescription> = new ScannerDescription();
        if isRocco {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_rocco_desc"),
                customDescs
            );
        } else if isTino {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_tino_desc"),
                customDescs
            );
        } else if isKostya {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_kostya_desc"),
                customDescs
            );
        } else if isVadik {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_vadik_desc"),
                customDescs
            );
        } else if isZina {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_zina_desc"),
                customDescs
            );
        } else if isKrag {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_krag_desc"),
                customDescs
            );
        } else if isVex {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_vex_desc"),
                customDescs
            );
        } else if isTuerca {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_tuerca_desc"),
                customDescs
            );
        } else if isAiko {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_aiko_desc"),
                customDescs
            );
        } else if isKenji {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_kenji_desc"),
                customDescs
            );
        } else if isRen {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_ren_desc"),
                customDescs
            );
        } else if isBuck {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_buck_desc"),
                customDescs
            );
        } else if isTammy {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_tammy_desc"),
                customDescs
            );
        } else if isMateo {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_mateo_desc"),
                customDescs
            );
        } else if isTiLuc {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_tiluc_desc"),
                customDescs
            );
        } else if isMireille {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_mireille_desc"),
                customDescs
            );
        } else {
            descChunk.Set(
                GetLocalizedTextByKey(n"ch_scan_brutus_desc"),
                customDescs
            );
        }
        scannerBB.SetVariant(GetAllBlackboardDefs().UI_ScannerModules.ScannerDescription, ToVariant(descChunk), true);
    }

    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGame());
    if IsDefined(sys) {
        if (isRocco || isTino) && IsDefined(sys.m_ep00) {
            sys.m_ep00.OnTargetScanned(recID);
        } else if (isKostya || isVadik || isZina) && IsDefined(sys.m_ep01) {
            sys.m_ep01.OnTargetScanned(recID);
        } else if (isKrag || isVex || isTuerca) && IsDefined(sys.m_ep02) {
            sys.m_ep02.OnTargetScanned(recID);
        } else if (isAiko || isKenji || isRen) && IsDefined(sys.m_ep03) {
            sys.m_ep03.OnTargetScanned(recID);
        } else if (isBuck || isTammy || isMateo) && IsDefined(sys.m_ep04) {
            sys.m_ep04.OnTargetScanned(recID);
        } else if (isTiLuc || isMireille || isBrutus) && IsDefined(sys.m_ep05) {
            sys.m_ep05.OnTargetScanned(recID);
        }
    }
    return ok;
}

// ---------------------------------------------------------------------------
// 2. Provocación Coordinada de Escuadrones al Recibir Daño del Jugador
// ---------------------------------------------------------------------------

@wrapMethod(ScriptedPuppet)
public final func PuppetDamagePipelineFinalized(evt: ref<gameHitEvent>) -> Void {
    wrappedMethod(evt);

    if !IsDefined(evt) || !IsDefined(evt.attackData) || this.IsPlayer() {
        return;
    }
    let instigator: wref<GameObject> = evt.attackData.GetInstigator();
    if !IsDefined(instigator) || !instigator.IsPlayer() {
        return;
    }
    let recID: TweakDBID = this.GetRecordID();
    let player: ref<PlayerPuppet> = instigator as PlayerPuppet;
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGame());
    if !IsDefined(sys) || !IsDefined(player) {
        return;
    }
    if Equals(recID, t"Character.Chispa_Ep00_Rocco") || Equals(recID, t"Character.Chispa_Ep00_Tino") {
        if IsDefined(sys.m_ep00) {
            sys.m_ep00.OnThugsProvoked(player);
        }
    } else if Equals(recID, t"Character.Chispa_Ep01_Kostya")
        || Equals(recID, t"Character.Chispa_Ep01_Vadik")
        || Equals(recID, t"Character.Chispa_Ep01_Zina") {
        if IsDefined(sys.m_ep01) {
            sys.m_ep01.OnScavsProvoked(player, false);
        }
    } else if Equals(recID, t"Character.Chispa_Ep02_Krag")
        || Equals(recID, t"Character.Chispa_Ep02_Vex")
        || Equals(recID, t"Character.Chispa_Ep02_Tuerca") {
        if IsDefined(sys.m_ep02) {
            sys.m_ep02.OnMaelstromProvoked(player, false);
        }
    } else if Equals(recID, t"Character.Chispa_Ep03_Aiko")
        || Equals(recID, t"Character.Chispa_Ep03_Kenji")
        || Equals(recID, t"Character.Chispa_Ep03_Ren") {
        if IsDefined(sys.m_ep03) {
            sys.m_ep03.OnTygerProvoked(player, false);
        }
    } else if Equals(recID, t"Character.Chispa_Ep04_Buck")
        || Equals(recID, t"Character.Chispa_Ep04_Tammy")
        || Equals(recID, t"Character.Chispa_Ep04_Mateo") {
        if IsDefined(sys.m_ep04) {
            sys.m_ep04.OnBorderSquadProvoked(player, false);
            if evt.attackData.GetNumRicochetBounces() > 0 {
                sys.m_ep04.OnRicochetHitLanded();
            }
        }
    } else if Equals(recID, t"Character.Chispa_Ep05_TiLuc")
        || Equals(recID, t"Character.Chispa_Ep05_Mireille")
        || Equals(recID, t"Character.Chispa_Ep05_Brutus") {
        if IsDefined(sys.m_ep05) {
            sys.m_ep05.OnVoodooSquadProvoked(player, false);
            if evt.attackData.GetNumRicochetBounces() > 0 || evt.hasPiercedTechSurface {
                sys.m_ep05.OnBallisticMasteryLanded();
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 3. Cámaras Dinámicas Encadenadas, Servidores Explosivos y Quickhacks (Ep. 1)
// ---------------------------------------------------------------------------

@addMethod(ScriptableDeviceComponentPS)
public final func ChispaConfigureSecurityCamera() -> Void {
    this.SetPlayerTakeOverControl(true);
    this.m_canBeInDeviceChain = true;
    this.SetDeviceState(EDeviceStatus.ON);
    this.m_shouldScannerShowStatus = true;
    this.m_shouldScannerShowNetwork = true;
}

@addMethod(ExplosiveDeviceControllerPS)
public final func ChispaConfigureExplosiveServer() -> Void {
    this.m_explosiveWithQhacks = true;
    this.SetDeviceState(EDeviceStatus.ON);
    this.m_shouldScannerShowStatus = true;
    this.m_shouldScannerShowNetwork = true;
}

@wrapMethod(TakeOverControlSystem)
private final func OnRequestTakeControl(request: ref<RequestTakeControl>) -> Void {
    wrappedMethod(request);
    let game: GameInstance = this.GetGameInstance();
    let controlled: ref<GameObject> = this.GetControlledObject();
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(game);
    if IsDefined(sys) && IsDefined(controlled) {
        if IsDefined(sys.m_ep01) && sys.m_ep01.IsEp01Camera(controlled.GetEntityID()) {
            sys.m_ep01.PopulateEp01CameraChain(controlled.GetEntityID());
            this.ShowChainControls(true);
            sys.m_ep01.OnCameraTakenOver(controlled.GetEntityID(), false);
        } else if IsDefined(sys.m_ep02) && sys.m_ep02.IsEp02Turret(controlled.GetEntityID()) {
            sys.m_ep02.OnTurretSubverted(false, false);
        } else if IsDefined(sys.m_ep05) && sys.m_ep05.IsEp05Camera(controlled.GetEntityID()) {
            sys.m_ep05.PopulateEp05CameraChain(controlled.GetEntityID());
            this.ShowChainControls(true);
            sys.m_ep05.OnCameraOrQuickHackUsed();
        }
    }
}

@wrapMethod(TakeOverControlSystem)
private final func ToggleToOtherDeviceFromChain(const otherPackage: script_ref<SWidgetPackage>) -> Void {
    wrappedMethod(otherPackage);
    let game: GameInstance = this.GetGameInstance();
    let controlled: ref<GameObject> = this.GetControlledObject();
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(game);
    if IsDefined(sys) && IsDefined(controlled) {
        if IsDefined(sys.m_ep01) && sys.m_ep01.IsEp01Camera(controlled.GetEntityID()) {
            sys.m_ep01.PopulateEp01CameraChain(controlled.GetEntityID());
            this.ShowChainControls(true);
            sys.m_ep01.OnCameraTakenOver(controlled.GetEntityID(), true);
        } else if IsDefined(sys.m_ep05) && sys.m_ep05.IsEp05Camera(controlled.GetEntityID()) {
            sys.m_ep05.PopulateEp05CameraChain(controlled.GetEntityID());
            this.ShowChainControls(true);
            sys.m_ep05.OnCameraOrQuickHackUsed();
        }
    }
}

@wrapMethod(QuickhacksListGameController)
private final func ApplyQuickHack(shouldUseUI: Bool) -> Bool {
    let applied: Bool = wrappedMethod(shouldUseUI);
    if applied && IsDefined(this.m_selectedData) && IsDefined(this.m_selectedData.m_action) {
        let pcObj: wref<GameObject> = this.GetPlayerControlledObject();
        if IsDefined(pcObj) {
            let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(pcObj.GetGame());
            if IsDefined(sys) {
                if IsDefined(sys.m_ep01) {
                    sys.m_ep01.OnQuickHackApplied(
                        this.m_selectedData.m_actionOwner,
                        this.m_selectedData.m_action.GetClassName(),
                        this.m_selectedData.m_action.GetObjectActionID()
                    );
                }
                if IsDefined(sys.m_ep02) {
                    sys.m_ep02.OnQuickHackApplied(
                        this.m_selectedData.m_actionOwner,
                        this.m_selectedData.m_action.GetClassName(),
                        this.m_selectedData.m_action.GetObjectActionID()
                    );
                }
                if IsDefined(sys.m_ep03) {
                    sys.m_ep03.OnQuickHackApplied(
                        this.m_selectedData.m_actionOwner,
                        this.m_selectedData.m_action.GetClassName(),
                        this.m_selectedData.m_action.GetObjectActionID()
                    );
                }
                if IsDefined(sys.m_ep04) {
                    sys.m_ep04.OnQuickHackApplied(
                        this.m_selectedData.m_actionOwner,
                        this.m_selectedData.m_action.GetClassName(),
                        this.m_selectedData.m_action.GetObjectActionID()
                    );
                }
                if IsDefined(sys.m_ep05) {
                    sys.m_ep05.OnQuickHackApplied(
                        this.m_selectedData.m_actionOwner,
                        this.m_selectedData.m_action.GetClassName(),
                        this.m_selectedData.m_action.GetObjectActionID()
                    );
                }
            }
        }
    }
    return applied;
}

@wrapMethod(ExplosiveDeviceControllerPS)
public final func OnQuickHackExplodeExplosive(evt: ref<QuickHackExplodeExplosive>) -> EntityNotificationType {
    let res: EntityNotificationType = wrappedMethod(evt);
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGameInstance());
    let devId: EntityID = PersistentID.ExtractEntityID(this.GetID());
    if IsDefined(sys) {
        if IsDefined(sys.m_ep01) && sys.m_ep01.IsEp01ExplosiveServer(devId) {
            sys.m_ep01.OnExplosiveServerOverloaded();
        } else if IsDefined(sys.m_ep02) && sys.m_ep02.IsEp02FuelTank(devId) {
            sys.m_ep02.OnFuelTankDetonated();
        } else if IsDefined(sys.m_ep03) && sys.m_ep03.IsEp03JammerBomb(devId) {
            sys.m_ep03.OnJammerBombDetonated();
        } else if IsDefined(sys.m_ep04) && sys.m_ep04.IsEp04AmmoTank(devId) {
            sys.m_ep04.OnAmmoTankDetonated();
        } else if IsDefined(sys.m_ep05) && sys.m_ep05.IsEp05CryoServer(devId) {
            sys.m_ep05.OnCryoServerDetonated();
        }
    }
    return res;
}

// ---------------------------------------------------------------------------
// 4. Torretas Automáticas y Tanques Explosivos CHOOH2 (Ep. 2 - Northside)
// ---------------------------------------------------------------------------

@addMethod(SecurityTurretControllerPS)
public final func ChispaConfigureSecurityTurret(enableDetection: Bool) -> Void {
    this.SetPlayerTakeOverControl(true);
    this.SetDeviceState(EDeviceStatus.ON);
    this.m_shouldScannerShowStatus = true;
    this.m_shouldScannerShowNetwork = true;
    if enableDetection {
        this.ExecutePSAction(this.ActionQuestSetDetectionToTrue(), this);
    } else {
        this.ExecutePSAction(this.ActionQuestSetDetectionToFalse(), this);
    }
}

@addMethod(SecurityTurretControllerPS)
public final func ChispaDisableSecurityTurret() -> Void {
    this.ExecutePSAction(this.ActionQuestForceDisabled(), this);
    this.SetBlockSecurityWakeUp(true);
}

@wrapMethod(SecurityTurretControllerPS)
public final func OnRipOff(evt: ref<RipOff>) -> EntityNotificationType {
    let res: EntityNotificationType = wrappedMethod(evt);
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGameInstance());
    if IsDefined(sys) && IsDefined(sys.m_ep02) && sys.m_ep02.IsEp02Turret(PersistentID.ExtractEntityID(this.GetID())) {
        sys.m_ep02.OnTurretSubverted(true, false);
    }
    return res;
}

@wrapMethod(ExplosiveDevice)
protected final func StartExplosionPipeline(instigator: wref<GameObject>, opt additionalDelays: Float) -> Void {
    wrappedMethod(instigator, additionalDelays);
    let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGame());
    if IsDefined(sys) {
        if IsDefined(sys.m_ep02) && sys.m_ep02.IsEp02FuelTank(this.GetEntityID()) {
            sys.m_ep02.OnFuelTankDetonated();
        } else if IsDefined(sys.m_ep03) && sys.m_ep03.IsEp03JammerBomb(this.GetEntityID()) {
            sys.m_ep03.OnJammerBombDetonated();
        } else if IsDefined(sys.m_ep04) && sys.m_ep04.IsEp04AmmoTank(this.GetEntityID()) {
            sys.m_ep04.OnAmmoTankDetonated();
        } else if IsDefined(sys.m_ep05) && sys.m_ep05.IsEp05CryoServer(this.GetEntityID()) {
            sys.m_ep05.OnCryoServerDetonated();
        }
    }
}

// ---------------------------------------------------------------------------
// 5. Desvío de Balas Inteligentes contra Tatuajes Inhibidores (Ep. 3 - Garra de Tigre)
// ---------------------------------------------------------------------------

@wrapMethod(NPCPuppet)
protected cb func OnSmartBulletDeflectedEvent(evt: ref<SmartBulletDeflectedEvent>) -> Bool {
    let handled: Bool = wrappedMethod(evt);
    if IsDefined(evt) && IsDefined(evt.instigator) && evt.instigator.IsPlayer() {
        let sys: ref<ChispaSystem> = ChispaSystem.GetInstance(this.GetGame());
        if IsDefined(sys) && IsDefined(sys.m_ep03) && sys.m_ep03.IsEp03Npc(this.GetEntityID()) {
            sys.m_ep03.OnSmartBulletJammed();
        }
    }
    return handled;
}

// ---------------------------------------------------------------------------
// 6. Lectura de Pinchos (Shards) en Vivo para Enlace Kiroshi
// ---------------------------------------------------------------------------

@wrapMethod(PopupsManager)
protected cb func OnShardRead(evt: ref<NotifyShardRead>) -> Bool {
    let res: Bool = wrappedMethod(evt);
    let pc: wref<GameObject> = this.GetPlayerControlledObject();
    if IsDefined(pc) && IsDefined(evt) {
        let liveSys: ref<ChispaSystem> = ChispaSystem.GetInstance(pc.GetGame());
        if IsDefined(liveSys) && IsDefined(liveSys.m_live) {
            if evt.isCrypted {
                liveSys.m_live.OnShardPopupOpened("", "");
            } else {
                let titleStr: String = CodexUtils.GetShardTitleString(false, evt.title);
                let bodyStr: String = CodexUtils.GetShardTextString(false, evt.text);
                if Equals(titleStr, "") && IsDefined(evt.entry) {
                    titleStr = GetLocalizedText(evt.entry.GetTitle());
                }
                if Equals(bodyStr, "") && IsDefined(evt.entry) {
                    bodyStr = GetLocalizedText(evt.entry.GetDescription());
                }
                liveSys.m_live.OnShardPopupOpened(titleStr, bodyStr);
            }
        }
    }
    return res;
}

@wrapMethod(PopupsManager)
protected cb func OnShardReadClosed(data: ref<inkGameNotificationData>) -> Bool {
    let res: Bool = wrappedMethod(data);
    let pc: wref<GameObject> = this.GetPlayerControlledObject();
    if IsDefined(pc) {
        let liveSys: ref<ChispaSystem> = ChispaSystem.GetInstance(pc.GetGame());
        if IsDefined(liveSys) && IsDefined(liveSys.m_live) {
            liveSys.m_live.OnShardPopupClosed();
        }
    }
    return res;
}
