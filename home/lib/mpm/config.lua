-----------------------------------------------------
--name       : lib/mpm/config.lua
--description: simple reading and verification of config files
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local config = {}

--adds some boilerplate text
local function onError(name, text)
  error("Config validation failed; error in '"..name.."': "..text,0)
end
--
local function toIndex(key)
  if type(key) == "string" then
    if key:match("^[%a_][%a%d_]*$") then
      return "."..key
    else
      return ("[%q]"):format(key)
    end
  end
  return ("[%s]"):format(tostring(key))
end

local function validator(key, value, format, configName, formatName, functionCache)
  if type(format) ~= "table" then
    onError(formatName,"Format description needs to be a table!")
  end
  --ignored -> don't check this part of format
  local ignored = false
  local function ignore()
    ignored = true
    return true
  end
  
  for i,check in ipairs(format) do
    local func, defaultMessage
    if type(check) == "function" then
      func = check
      defaultMessage = "Custom check failed! (No additional information!)"
    elseif type(check) == "string" then
      func = functionCache[check]
      if func == nil then
        local errMsg
        func,errMsg = load("local key,value,ignore=...;"..check:gsub("^=","return "))
        if func then
          functionCache[check] = func
        else
          onError(formatName..toIndex(i),errMsg or "Loading '"..check.."' failed!")
        end
      end
      defaultMessage = "'"..check.."' failed!"
    else
      onError(formatName..toIndex(i),"Condition needs to be a string or function!")
    end
    
    local ok,err = func(key,value,ignore)
    if ignored then
      --ignoring the rest of the format rule
      return
    end
    if not ok then
      onError(configName, err or defaultMessage)
    end
  end
  if format.oneof then
    if type(format.oneof) ~= "table" then
      onError(formatName,"'oneof' has to be a table!")
    end
    local oneOK = false
    for i,subFormat in ipairs(format.oneof) do
      local ok = pcall(validator, key, value, subFormat, configName, formatName..".oneof"..toIndex(i), functionCache)
      if ok then
        oneOK = true
        break
      end
    end
    if not oneOK then
      onError(configName,format.oneof.message or "'oneof' check failed!")
    end
  end
  if format.forkeys then
    if type(format.forkeys) ~= "table" then
      onError(formatName,"'forkeys' has to be a table!")
    end
    for nextKey,nextFormat in pairs(format.forkeys) do
      validator(nextKey, value[nextKey], nextFormat, configName..toIndex(nextKey), formatName..".forkeys"..toIndex(nextKey), functionCache)
    end
  end
  if format.foripairs then
    if type(value) ~= "table" then
      onError(configName,"Value has to be iterable! (foripairs)")
    end
    for nextKey,nextValue in ipairs(value) do
      validator(nextKey, nextValue, format.foripairs, configName..toIndex(nextKey), formatName..".foripairs", functionCache)
    end
  end
  if format.forpairs then
    if type(value) ~= "table" then
      onError(configName,"Value has to be iterable! (forpairs)")
    end
    for nextKey,nextValue in pairs(value) do
      validator(nextKey, nextValue, format.forpairs, configName..toIndex(nextKey), formatName..".forpairs", functionCache)
    end
  end
end


function config.check(cfg,format)
  assert(type(cfg) == "table","'config' isn't a table!")
  validator(nil,cfg,format,"config","format",{})
end

function config.load(file,format,default,env,autoTables)
  if default then
    local fs = require "filesystem"
    --auto generate config
    if not fs.exists(file) then
      if type(default) == "string" then
        --create new file with <default> as content
        local stream = io.open(file,"wb")
        stream:write(default)
        stream:close()
      elseif type(default) == "table" then
        return checkConfig(default,format)
      elseif type(default) == "function" then
        return checkConfig(default(file,format),format)
      end
    end
  end
  
  local cfg
  local auto_meta, auto_create
  if autoTables then
    auto_create = function()
      local t = setmetatable({},auto_meta)
      if type(autoTables) == "table" then
        table.insert(autoTables, t)
      elseif type(autoTables) == "function" then
        autoTables(t)
      end
      return t
    end
    auto_meta = {
      __index = function(t,k)
        local v = auto_create()
        t[k] = v
        return v
      end,
    }
    cfg = auto_create()
  else
    cfg = {}
  end
  
  local env_meta = {
    __index = function(t,k)
      --1st: stay "local" -> config
      local v = rawget(cfg,k)
      if v ~= nil then
        return v
      end
      --2nd: now searching the given environment
      if env then
        v = env[k]
        if v ~= nil then
          return v
        end
      end
      --3rd: create new table if cfg has got a metatable
      --Using cfg that way avoids the need for special handling of the environment
      --if one wants to disable the 'autoTables' feature after loading.
      return cfg[k]
    end,
    --always writing to the configuration table
    __newindex = cfg,
  }
  
  local func = assert(loadfile(file, "t", setmetatable({}, env_meta)))
  func()
  if format then
    config.check(cfg, format)
  end
  return cfg
end

return config
