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

local function append(value, a, ...)
  if a ~= nil then
    return a, append(value, ...)
  else
    return value
  end
end

local function wrapGetterSetter(getter, setter, ...)
  local args = table.pack(...)
  return function(value)
    if value == nil then
      return getter(table.unpack(args, 1, args.n))
    elseif setter then
      return setter(append(value, table.unpack(args, 1, args.n)))
    else
      error("read only connection", 2)
    end
  end
end

local function wrapProxyFunctions(proxy, getterName, setterName, ...)
  return wrapGetterSetter(proxy[getterName], proxy[setterName], ...)
end

local function wrapAnalog(typ, address, side, color)
  local proxy = component.proxy(address)
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
  else
    getterName = "get#Output"
    setterName = "set#Output"
  end
  return wrapProxyFunctions(proxy, getterName:gsub("#", infix), setterName:gsub("#", infix), table.unpack(args))
end

local methods = {}

function methods:toggle()
  return self(invert(self()))
end

function methods:pulse(duration, value)
  checkArg(1, duration, "number")
  local oldValue = self()
  if value == nil then
    value = invert(oldValue)
  end
  self(value)
  os.sleep(duration)
  return self(oldValue)
end


local function newTable(f)
  local normal = setmetatable({}, {
    __index = methods,
    __call = function(_, value)
      return f(value)
    end,
  })
  local inverted = setmetatable({}, {
    __index = methods,
    __call = function(_, value)
      return inverted(f(inverted(value)))
    end,
  })
  normal.inverted = inverted
  inverted.inverted = normal
  return normal
end

function rstools.analog(typ, address, side, color)
  checkArg(1, typ, "string")
  checkArg(2, address, "string")
  checkArg(3, side, "number", "string")
  checkArg(4, color, "number", "string", "nil")
  local funcAnalog = wrapAnalog(typ, address, side, color)
  local permittedType = (color == "all") and "table" or "boolean"
  return newTable(function(value)
    checkArg(1, value, permittedType, "nil")
    value = funcAnalog(value)
    return value
  end)
end

function rstools.digital(typ, address, side, color)
  checkArg(1, typ, "string")
  checkArg(2, address, "string")
  checkArg(3, side, "number", "string")
  checkArg(4, color, "number", "string", "nil")
  local funcAnalog = wrapAnalog(typ, address, side, color)
  local permittedType = (color == "all") and "table" or "boolean"
  return newTable(function(value)
    checkArg(1, value, permittedType, "nil")
    return toDigital(funcAnalog(toAnalog(value)))
  end)
end

return rstools
