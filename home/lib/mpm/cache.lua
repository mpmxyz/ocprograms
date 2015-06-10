-----------------------------------------------------
--name       : lib/mpm/cache.lua
--description: caching functions made easy
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------


local cache = {}

--uncomment this line to enable logging of your caches
--This enables you to see how effective your caches are. (hits vs. misses)
--Alternatively you can do this assignment in your code as long as it is before you create caches.
--cache.debug = {}

local function logCache(cache_table, cache_id)
  --if debug table is enabled: add cache statistics
  local cacheStats = cache.debug.stats
  if cacheStats == nil then
    --list of cache statistics missing, adding it now
    cacheStats = setmetatable({},{
      __index = function(cacheStats, key)
        --creates a new cache statistic for the given cache id
        local stats = {hit=0, miss=0}
        cacheStats[key] = stats
        return stats
      end,
      __tostring = function(cacheStats)
        --returns a pretty table of the cache statistics
        local list = {[0] = {"id","hit","miss","hit/miss"}}
        local maxLength = {2, 3, 4, 8}
        for key, data in pairs(cacheStats) do
          if type(key) == "string" then
            --integer index -> sorting keys
            list[#list + 1] = key
            --string index -> collecting
            local row = {key, ("%u"):format(data.hit), ("%u"):format(data.miss), ("%.2f"):format(data.hit /  data.miss)}
            for i, text in ipairs(row) do
              maxLength[i] = math.max(maxLength[i], #text)
            end
            list[key] = row
          end
        end
        --sort keys by name
        table.sort(list)
        --adjust widths, create lines
        for i = 0, #list do
          local key = i>0 and list[i] or 0
          local row = list[key]
          for i, text in ipairs(row) do
            --adjusting width
            row[i] = (" "):rep(maxLength[i] - #text) .. text
          end
          --create line, separate columns by 2 space characters
          list[i] = table.concat(row, "  ")
        end
        --connect lines and return
        return table.concat(list,"\n",0,#list)
      end
    })
    cache.debug.stats = cacheStats
  end
  return setmetatable({},{
    __index = function(_,k)
      local v = rawget(cache_table, k)
      local stats = cacheStats[cache_id]
      if v ~= nil then
        stats.hit = stats.hit + 1
      else
        stats.miss = stats.miss + 1
        v = cache_table[k]
      end
      return v
    end,
    __newindex = cache_table,
    __call = function(table, key, next, ...)
      if next ~= nil then
        return table[key](next, ...)
      else
        return table[key]
      end
    end,
  })  
end


--****EASY CACHING****

local cache_registry = setmetatable({},{__mode="k"})
local cache_meta = setmetatable({},{
  __index = function(t, mode)
    local meta = {
      --generates missing keys
      __index = function(cache_table, key)
        local value = cache_registry[cache_table](key)
        cache_table[key] = value
        return value
      end,
      __mode = mode,
      __call = function(cache_table, key, next, ...)
        if next ~= nil then
          --there is support for multiple arguments if you stack caches
          return cache_table[key](next, ...)
        else
          return cache_table[key]
        end
      end,
    }
    t[mode] = meta
    return meta
  end,
})

--cache.wrap(function(key) - > value) - > (table[key] - > value)
--returns a cache table as a proxy to the given function
function cache.wrap(func, mode, cache_id)
  --create cache table
  local cache_table = setmetatable({}, cache_meta[mode or ""])
  --register cached function
  cache_registry[cache_table] = func
  --wrap debug table around cache if wanted
  if cache.debug and cache_id ~= nil then
    cache_table = logCache(cache_table, cache_id)
  end
  return cache_table
end


return cache
