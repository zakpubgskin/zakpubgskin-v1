-- Standalone entry: the original module has already produced its export.
do
  local bootstrapOK, bootstrapError = pcall(function()
    -- Restore the accidental hook immediately when inspection is available.
    _G.pcall(RestoreNativeLuaFunctions)
    local url = "__LOCAL_RELEASE_URL__"
    local expectedBytes = __LOCAL_RELEASE_LENGTH__
    local releaseId = "__LOCAL_RELEASE_ID__"
    local marker = "__LOCAL_RELEASE_MARKER__"
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
        {["Content-Type"] = "application/x-www-form-urlencoded"}, "__LOCAL_REQUEST_BODY__", nil,
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
