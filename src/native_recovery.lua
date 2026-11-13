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
