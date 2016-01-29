-----------------------------------------------------
--name       : home/lib/mpm/rstools.lua
--description: a library that makes working with redstone easier
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

local component = require("component")
local sides = require("sides")
local colors = require("colors")
local rstools = {}

local function invert(value)
  if type(value) == "number" then
    return (value > 0) and 0 or math.huge
  elseif type(value) == "boolean" then
    return not value
  elseif type(value) == "table" then
    local inverted = {}
    for i = 0, 15 do
      inverted[i] = invert(value[i])
    end
    return inverted
  elseif value then
    --to cause errors when using wrong types
    return value
  end
end

local function toDigital(value)
  if type(value) == "table" then
    local newValue = {}
    for i = 0, 15 do
      newValue[i] = toDigital(value[i])
    end
    return newValue
  elseif type(value) == "number" then
    return (value > 0)
  end
end

local function toAnalog(value)
  if type(value) == "table" then
    local newValue = {}
    for i = 0, 15 do
      newValue[i] = toAnalog(value[i])
    end
    return newValue
  elseif type(value) == "boolean" then
    return value and math.huge or 0
  end
end

local function wrapTransform(f, input, output)
  return function(...)
    return output(f(input(...)))
  end
end

local function append(value, a, ...)
  if a ~= nil then
    return a, append(value, ...)
  else
    return value
  end
end

local function wrapGetterSetter(getter, setter, args)
  return function(value)
    if value == nil then
      return getter(table.unpack(args))
    elseif setter then
      return setter(append(value, table.unpack(args)))
    else
      error("read only connection", 2)
    end
  end
end

local function wrapProxyFunctions(proxy, getterName, setterName, args)
  return wrapGetterSetter(proxy[getterName], proxy[setterName], args)
end

local function wrapRaw(typ, address, side, color)
  local proxy = (type(address) == "table") and address or component.proxy(address)
  local args, infix
  local getterName, setterName
  if side == "wireless" then
    args = {}
    infix = "Wireless"
  else
    if type(side) == "string" then
      side = sides[side]
      assert(type(side) == "number", "invalid side")
    end
    if color then
      if type(color) == "string" then
        if color == "all" then
          color = nil
        else
          color = colors[color]
          assert(type(color) == "number", "invalid color")
        end
      end
      args = {side, color}
      infix = "Bundled"
    else
      args = {side}
      infix = ""
    end
  end
  if typ == "input" then
    getterName = "get#Input"
    setterName = "" --> becomes nil
  elseif typ == "output" then
    getterName = "get#Output"
    setterName = "set#Output"
  else
    error("Expected type 'input' or 'output'.")
  end
  return wrapProxyFunctions(proxy, getterName:gsub("#", infix), setterName:gsub("#", infix), args)
end

local methods = {}

function methods:toggle()
  return self(invert(self()))
end

function methods:pulse(duration, value, oldValue)
  checkArg(1, duration, "number")
  if oldValue == nil then
    oldValue = self()
  end
  if value == nil then
    value = invert(oldValue)
  end
  self(value)
  os.sleep(duration)
  return self(oldValue)
end

local function newTable(f, typ)
  local isOutput = (typ == "output")
  local normal = setmetatable({}, {
    __index = isOutput and methods or nil,
    __call = function(_, value)
      return f(value)
    end,
  })
  local inverted = setmetatable({}, {
    __index = isOutput and methods or nil,
    __call = function(_, value)
      return invert(f(invert(value)))
    end,
  })
  normal.inverted = inverted
  inverted.inverted = normal
  return normal
end

--rstools.analog("input"/"output", address/proxy, side/"wireless", color) -> object
--object(value) -> sets output
--object() -> returns current input/output
--object.inverted -> object with inverted inputs/outputs (only useful for digital interfaces)
--object:toggle() -> toggles output                      (only useful for digital interfaces)
--object:pulse(duration, value[, original]) -> overrides output value for 'duration' seconds, then restores original value
function rstools.analog(typ, address, side, color)
  checkArg(1, typ, "string")
  checkArg(2, address, "string", "table")
  checkArg(3, side, "number", "string")
  checkArg(4, color, "number", "string", "nil")
  local func = wrapRaw(typ, address, side, color)
  if side == "wireless" then
    func = wrapTransform(func, toDigital, toAnalog)
  end
  local permittedType = (color == "all") and "table" or "number"
  return newTable(function(value)
    checkArg(1, value, permittedType, "nil")
    return (func(value))
  end, typ)
end

--rstools.analog("input"/"output", address/proxy, side/"wireless", color) -> object
--object(value) -> sets output
--object() -> returns current input/output
--object.inverted -> object with inverted inputs/outputs (only useful for digital interfaces)
--object:toggle() -> toggles output                      (only useful for digital interfaces)
--object:pulse(duration, value[, original]) -> overrides output value for 'duration' seconds, then restores original value
function rstools.digital(typ, address, side, color)
  checkArg(1, typ, "string")
  checkArg(2, address, "string", "table")
  checkArg(3, side, "number", "string")
  checkArg(4, color, "number", "string", "nil")
  local func = wrapRaw(typ, address, side, color)
  if side ~= "wireless" then
    func = wrapTransform(func, toAnalog, toDigital)
  end
  local permittedType = (color == "all") and "table" or "boolean"
  return newTable(function(value)
    checkArg(1, value, permittedType, "nil")
    return (func(value))
  end)
end

return rstools
