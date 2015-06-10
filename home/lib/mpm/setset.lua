-----------------------------------------------------
--name       : lib/mpm/setset.lua
--description: a set of sets that helps to ensure a raw equality between sets with same contents
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--load libraries
local cache = require("mpm.cache").wrap
local hashset = require("mpm.hashset")
local sets  = require("mpm.sets")

--library table
local setset = {}

--collects usage statistics for the given id
--"n" is the size of the accessed object,
local function onDebug(id, n)
  local stats = setset.debug.stats
  if stats == nil then
    stats = setmetatable({},{
      __index = function(cacheStats, key)
        --creates a new cache statistic for the given cache id
        local stats = {
          count = 0,
          total = 0,
          average = 0,
          min=math.huge,
          max=0,
        }
        cacheStats[key] = stats
        return stats
      end,
    })
    setset.debug.stats = stats
  end
  stats = stats[id]
  stats.count = stats.count + 1
  stats.total = stats.total + n
  stats.average = stats.total / stats.count
  stats.max = math.max(stats.max, n)
  stats.min = math.min(stats.min, n)
  stats.nsets = nsets
  stats.knownObjects = knownObjects
end

--give objects an unique integer id
local knownObjects = 0
local objectToValue = cache(function()
  knownObjects = knownObjects + 1
  return knownObjects
end, "k")

--returns a hash value for the given object using the seed and size as additional parameters
local function hashObject(obj, seed, size)
  local typ = type(obj)
  if typ == "string" then
    local value = (seed + #obj) % size
    for i = 1, #obj do
      value = (value * seed + obj:byte(i,i)) % size
    end
    return value
  elseif typ == "number" then
    local m, e = math.frexp(obj)
    return math.floor(seed * (e+m*size)) % size
  elseif typ == "table" then
    return (seed * objectToValue[obj]) % size
  else
    error("Can't hash "..typ.."s!")
  end
end

--returns a hash value for the given set or list using the seed and size as additional parameters
function setset.hash(setOrList, seed, size)
  local value = (seed) % size
  for k, v in pairs(setOrList) do
    value = (value + hashObject(v, seed, size)) % size
  end
  return value
end


--returns a function that takes a set and returns a set or list
--The returned set will be the same whenever you input a set or list with equal contents.
function setset.manager(mode, id)
  local set = hashset.new(setset.hash, sets.equals, 1024)
  
  return function(setOrList)
    if setset.debug and id then
      local n = 0
      for k,v in pairs(setOrList) do
        n = n + 1
      end
      onDebug(id, n)
    end
    
    local existing = set.get(setOrList)
    if existing then
      return existing
    else
      return set.insert(sets.new(setOrList))
    end
  end
end

--return library
return setset
