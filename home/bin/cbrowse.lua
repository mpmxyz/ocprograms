--[[


TABLES:
/br_reactor/
Key              |  |Value
type| value      |ID|
----+------------+--+----+
nil |            | a|nil |            
bool|true        | b|...
num |123.5       | c|
strg|"abcdef"  | d|...
"st"|"Long Text >| e|
func|f0123       | f|...
usrd|u0123       | g|
thrd|t0123       | h|...
tabl|t123456     | i|
tabl|{a=t123,   >| j|
----+------------+--+
>

FUNCTIONS CALLS/ COMMANDS:
/br_reactor/=func(a, b, c)
ID|type| value      
--+----+
 a|nil |            
 b|bool|true        
 c|num |123.5       
 d|strg|"abcdef"  
 e|strg|"Long Text >
 f|func|f0123       
 g|usrd|u0123       
 h|thrd|T0123       
 i|tabl|t123
 j|tabl|t123
 k|tabl|t123
--+----+-------------
>

STRINGS:
/test/longstring
abcdef
adaea
asese
...
--mark string with special foreground/ background color
--add special "line break" character


NUMBERS:
/test/number
0
0.105135
0x0




COMMAND LINE:
  1st: <cmd> -> dostring(cmd:gsub("^=" , "return "))
  2nd: "sh <cmd>" -> shell.execute(cmd, env)

for lua code:
  local environment
    default values
      _G: global_environment
      _K: list of keys, accessed by string id (middle column) or row number
      _V: list of values
      _OBJ: current object
      _REG: list of known values, accessed by automatic identifier (e.g. t1234 for a table)
              - >there is an automaticly updated registry (how to save memory with big strings? which types are registered?)
      _unpack(t): table.unpack(t, 1, table.maxn(t))
    metatable
      __newindex = if __index- value existing then apply there else apply at object end
      __index = 1st: default values, 2nd: object, 3rd: global_environment
    stdio, event code
      redirect to special view, when used
  ideas to name the 'path':
    if the value belongs to a string index, use the string index instead of a generic name
    if it was a direct call of a function with a string index, use this index as a name
  
for shell code:
  stdio and event redirect as with lua code
  use shell.execute(command_line, environment)
CLICK ON OBJECT:
  LEFT: 
    add object reference to command
  RIGHT:
    execute for non- functions
    set command line to = func(* ), where * is the cursor





DIMENSIONS:
(width - 4(separators) - 2(ID)) / 2 - 1,4,8(type)
(50 - 6)/2 - 8 -> 22 - 8 -> 14

FOR LATER:
  display tables in content table as a serialized string?
]]

local component = require("component")
local event     = require("event")
local term      = require("term")
local keyboard  = require("keyboard")
local computer  = require("computer")
local unicode   = require("unicode")

local cache            = require("mpm.cache")
local tables           = require("mpm.tables")
local draw_buffer      = require("mpm.draw_buffer")
local component_filter = require("mpm.component_filter")
local config           = require("mpm.config")


--****DEBUG****
local function interruptedTraceback(message)
  if message == "interrupted" or type(message) ~= "string" then
    return message
  else
    --don't add traceback twice - > wrap in table
    message = debug.traceback(message)
    return setmetatable({}, {__tostring = function() return message end})
  end
end
local function userError(err)
  io.stderr:write(err.."\n")
  error("interrupted", 0)
end
local function userAssert(check, err)
  if not check then
    userError(err)
  end
end

--****CONFIG****

local defaultConfig = [[
--several lists of type names
--They are used for the type column.
dictionaries = {
  normal = {
    --type: column header
    ["type"]     = "type    ",
    ["nil"]      = "nil     ",
    ["boolean"]  = "boolean ",
    ["number"]   = "number  ",
    ["string"]   = "string  ",
    ["function"] = "function",
    ["userdata"] = "userdata",
    ["thread"]   = "thread  ",
    ["table"]    = "table   ",
    --"function" and "userdata"
    width         = 8,
    requiredWidth = 50,
  },
  short = {
    ["type"]     = "type",
    ["nil"]      = "nil ",
    ["boolean"]  = "bool",
    ["number"]   = "num ",
    ["string"]   = "strg",
    ["function"] = "func",
    ["userdata"] = "usrd",
    ["thread"]   = "thrd",
    ["table"]    = "tabl",
    width = 4,
    requiredWidth = 42,
  },
  single_char = {
    ["type"]     = "t",
    ["nil"]      = "x",
    ["boolean"]  = "b",
    ["number"]   = "n",
    ["string"]   = "s",
    ["function"] = "f",
    ["userdata"] = "u",
    ["thread"]   = "T",
    ["table"]    = "t",
    width = 1,
    requiredWidth = 20,
  },
}
colors = {
  full = {
    default = 0xFFFFFF,
    type = {
      ["nil"]      = 0xCCCCCC, --light gray
      ["number"]   = 0x8888FF, --light blue
      ["boolean"]  = 0xFFFFFF, --white
      ["string"]   = 0xFFCC33, --orange
      ["function"] = 0xFFFF33, --yellow
      ["thread"]   = 0xCC66CC, --purple
      ["userdata"] = 0xFF6699, --magenta
      ["table"]    = 0x33CC33, --lime
    },
    value = {
      [true]  = 0x00FF00,
      [false] = 0xFF0000,
    },
    background = {
      header = 0x000000,
      --is alternated to make identifying a line easier
      content = {
        [1]  = 0x000000,
        [2]  = 0x333333, --gray
      },
      command = 0x000000,
    },
    requiredDepth = 4,
  },
  blackwhite = {
    default = 0xFFFFFF,
    type = {},
    value = {},
    background = {
      header  = 0x000000,
      content = {
        [1]   = 0x000000,
      },
      command = 0x000000,
    },
    requiredDepth = 1,
  },
}
--determines which keys are displayed and how they are sorted
displayedKeys = {
  "nil", --I wouldn't expect that, but who knows...
  "boolean",
  "string",
  "function",
  "userdata",
  "thread",
  "table",
  "number",
}
--tells cbrowse which key value pairs it should sort
sortedKeys = {
  "string",
  "number",
}
]]

local checkAllTypes = [[
for _, key in ipairs{"nil", "boolean", "number", "string", "function", "userdata", "thread", "table"} do
  if value[key] == nil then
    return false, 'Missing entry \"'..key..'\"!'
  end
end
return true
]]

--data driven config validation
local configFormat = {
  "= type(value.dictionaries) == 'table'",
  "= type(value.colors) == 'table'",
  "= type(value.displayedKeys) == 'table'",
  "= type(value.sortedKeys) == 'table'",
  --checks the values of the specified keys only
  --makes 'value' accessible to every check
  forkeys = {
    dictionaries = {
      "= next(value) ~= nil",
      forpairs = {
        "= type(value.width) == 'number'",
        "= type(value.requiredWidth) == 'number'",
        "= type(value.type) == 'string'",
        checkAllTypes,
        forpairs = {
          "= ({width = true, requiredWidth = true})[key] and ignore() or true",
          "= type(value) == 'string'",
        },
      },
    },
    colors = {
      "= next(value) ~= nil",
      forpairs = {
        "= type(value) == 'table'",
        "= type(value.default) == 'number'",
        "= type(value.type) == 'table'",
        "= type(value.value) == 'table'",
        "= type(value.background) == 'table'",
        "= type(value.requiredDepth) == 'number'",
        forkeys = {
          type = {
            forpairs = {
              "= type(key) == 'string'",
              "= type(value) == 'number'",
            },
          },
          value = {
            forpairs = {
              "= type(value) == 'number'",
            },
          },
          background = {
            "= type(value.header) == 'number'",
            "= type(value.content) == 'table'",
            "= type(value.command) == 'number'",
            forkeys = {
              content = {
                "= value[1] ~= nil",
                foripairs = {
                  "= type(value) == 'number'",
                },
              },
            },
          },
        },
      },
    },
    displayedKeys = {
      foripairs = {
        "= type(value) == 'string'"
      },
    },
    sortedKeys = {
      foripairs = {
        "= type(value) == 'string'"
      },
    },
  },
}

local CONFIG
local configDictionary, configColors
local function loadConfig()
  CONFIG = config.load("/etc/cbrowse.cfg", configFormat, defaultConfig, _ENV, true)
  
  configDictionary = cache.wrap(
    function(availableWidth)
      local best, bestWidth = nil, 0
      for _, dict in pairs (CONFIG.dictionaries) do
        if dict.requiredWidth <= availableWidth then
          if dict.requiredWidth > bestWidth then
            best = dict
            bestWidth = best.requiredWidth
          end
        end
      end
      return best
    end
  )
  configColors = cache.wrap(
    function(availableDepth)
      local best, bestDepth = nil, 0
      for _, colors in pairs(CONFIG.colors) do
        if colors.requiredDepth <= availableDepth then
          if colors.requiredDepth > bestDepth then
            best = colors
            bestDepth = best.requiredDepth
          end
        end
      end
      return best
    end
  )
end
loadConfig()

local function getValueColor(colors, value)
  return (value ~= nil) and colors.value[value] or colors.type[type(value)] or colors.default
end
local function getTypeColor(colors, typ)
  return colors.type[typ] or colors.default
end


--****INDEXING****
local reserved_keywords = {}
for _, keyword in ipairs{
    "and", "break", "do", "else", "elseif", "end",
    "false", "for", "function", "goto", "if", "in",
    "local", "nil", "not", "or", "repeat", "return",
    "then", "true", "until", "while",
  } do
  reserved_keywords[keyword] = true
end

local index_chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
--maps number indices to the string indices used for the ID column
--that way you can access >2500 objects instead of just 100 with 2 characters
--number - > string, string - > index
local string_indices = setmetatable({}, {
  __index = function(t, k)
    local k_type = type(k)
    if k_type == "number" and k >= 1 then
      --number - > string
      local num = math.floor(k - 1) --1 based indexing...
      local text = ""
      repeat
        local index = (num % #index_chars) + 1
        num = math.floor(num / #index_chars)
        text = index_chars:sub(index, index)..text
      until num <= 0
      t[text] = k
      t[k]    = text
      return text
    elseif k_type == "string" and k ~= "" then
      --string - > number
      local num
      if #k == 1 then
       --1 based indexing: first string index equals index 1
       num = index_chars:find(k, 1,true)
       if num == nil then
         return
       end
      else
       num = 0
       for char in k:gmatch(".") do
         local digitIndex = t[char]
         if digitIndex == nil then
           return
         end
         num = num * #index_chars + digitIndex - 1
       end
       num = num + 1 --1 based indexing...
      end
      t[k]   = num
      t[num] = k
      return num
    end    
  end,
})

--****REGISTRY****
local REG_PREFIXES = {
  ["function"] = "f",
  ["userdata"] = "u",
  ["thread"]   = "T",
  ["table"]    = "t",
}
--count number of created keys to assure that the same key will always refer to the same value
local REG_COUNTS = {}
--the registry table
--name - > object, object - > name
--An object is registered when using _REG[object].
--Entries are removed when the corresponding object is collected by the garbage collector.
--It depends on the fact that strings are treated as primitive values and
--therefore are not collected due to weak references.
local _REG = setmetatable({}, {
  __index = function(reg, object)
    local prefix = REG_PREFIXES[type(object)]
    if prefix then
      local number = (REG_COUNTS[prefix] or 0) + 1
      REG_COUNTS[prefix] = number
      local key = prefix..number
      reg[key]    = object
      reg[object] = key
      return key
    end
  end,
  __mode = "kv",
})


local function getDisplayedString(object)
  if type(object) == "string" then
    return ("%q"):format(object)
  else
    local regKey = _REG[object]
    if regKey then
      return regKey
    else
      return tostring(object)
    end
  end
end

local identifierPattern = "[%a_][%a%d_]*"
local function isValidIdentifier(object)
  if type(object) ~= "string" then
    return false
  end
  return object:match("^"..identifierPattern.."$") ~= nil and not reserved_keywords[object]
end

local function getDisplayedIndex(object, prefix)
  if object == nil then
    return nil
  end
  if isValidIdentifier(object) then
    if prefix then
      return prefix.."."..object
    else
      return object
    end
  end
  prefix = prefix or ""
  return prefix.."["..getDisplayedString(object).."]"
end



--****ENVIRONMENTS****
--the shared environment used to save values of interest and loaded modules
local global_environment = setmetatable({}, {
  __index = function(t, k)
    if type(k) == "string" then
      --autoloading modules
      local ok, module = pcall(require, k)
      if ok then
        t[k] = module
        return module
      end
    end
  end,
})
for k, v in pairs(_G) do
  global_environment[k] = v
end
global_environment._G = global_environment



--wrapper function
local function read_only(t, text)
  return setmetatable({}, {
    __metatable = "read only",
    __index = t,
    __newindex = function(t, k,v)
      error(text:format(k), 3)
    end,
    __pairs = function(self)
      return function(_, k)
        return next(t, k)
      end, self, nil
    end,
    __ipairs = function(self)
      return function(_, i)
        i = i + 1
        local v = rawget(t, i)
        if v ~= nil then
          return i, v
        end
      end, self, 0
    end,
    __len = function(self)
      return #t
    end,
  })
end


local function localEnvironment(object, keys, values)
  --This table even overrides the object because you can use this table
  --to access everything and that is rarely possible with the object you are visiting.
  local override = read_only({
    _G   = global_environment,
    _K   = keys   and read_only(keys  , "_K is read only!"),
    _V   = values and read_only(values, "_V is read only!"),
    _REG = read_only(_REG             , "_REG is read only!"),
    _OBJ = object,  --use this value e.g. if you intend to access the object field '_K'
  }, "_ENV.%s is read only!")
  --this is a function used to find values for __index and to find it's source for __newindex
  local function findNonNil(key, raw)
    local get
    if raw then
      get = function(t, k)
        if type(t) == "table" then
          --to avoid loading libraries when writing a value to the global environment...
          return rawget(t, k)
        else
          return t[k]
        end
      end
    else
      get = function(t, k)
        return t[k]
      end
    end
    --1st: override
    local value = override[key]
    if value ~= nil then
      return value, override, "override"
    end
    --2nd: object
    value = get(object, key)
    if value ~= nil then
      return value, object, "_OBJ"
    end
    --3rd: global environment
    value = get(global_environment, key)
    if value ~= nil then
      return value, global_environment, "_G"
    end
    --no value found: redirect writing access to object
    return nil, object, "_OBJ"
  end
  
  --create an individual environment...
  local env = setmetatable({}, {
    __newindex = function(t, k,v)
      local _, source = findNonNil(k, true)
      if types_indexable[type(source)] then
        source[k] = v
      else
        --redirect to _G if the object is not indexable (i.e. a string)
        global_environment[k] = v
      end
    end,
    __index = function(t, k)
      return (findNonNil(k))
    end,
  })
  return env
end


local searchedOverrideNames = {
 "_OBJ", "_K", "_G",
}

--findEnvironmentIndex(object, environment) - > key, environment name
local function findEnvironmentIndex(object, environment)
  if object == nil then
    return nil, nil
  end
  for _, overrideName in ipairs(searchedOverrideNames) do
    local sourceList = environment[overrideName]
    if rawequal(object, sourceList) then
      return overrideName, "_ENV"
    end
    if type(sourceList) == "table" then
      for k, v in pairs(sourceList) do
        if rawequal(object, v) then
          return k, overrideName
        end
      end
    end
  end
end

--****OBJECT LOADING****
local function loadKeyValues(object, fillNil)
  --Number keys are added last to make large arrays easier to look through.
  --(non numeric keys first, number keys sorted by numeric value)
  --That was the first idea. Now it's extended to a general sort by type system...
  local typeKeys = {}
  for k, v in pairs(object) do
    local k_type = type(k)
    local list = typeKeys[k_type]
    if list == nil then
      --no list 
      list = {n = 0}
      typeKeys[k_type] = list
    end
    local n = list.n + 1
    list.n = n
    list[n] = k
  end
  --sort numbers and strings for better readability
  for _, k_type in ipairs(CONFIG.sortedKeys) do
    local keyList = typeKeys[k_type]
    if keyList then
      table.sort(keyList)
    end
  end
  --now it's time to assemble the tables...
  local n = 0
  local keys, values = {}, {}
  local lastIndex = 0
  local function addLast(key, value)
      n = n + 1
      keys  [n] = key
      values[n] = value
      local string_index = string_indices[n]
      keys  [string_index] = key
      values[string_index] = value
  end
  for _, k_type in ipairs(CONFIG.displayedKeys) do
    local keyList = typeKeys[k_type]
    if keyList then
      local nilsBeforeLimit = 1024
      for _, key in ipairs(keyList) do
        if fillNil and k_type == "number" then
          --use fillNil to display nil values between non nil values
          --That is done for function returns because there are no keys for return values.
          --Normal tables are not filled because that would make
          --large sparse arrays unreadable and would use a lot of ressources.
          --It is filling a maximum of 128 empty indices at once. (and 1024 total)
          if key - lastIndex <= 129 and nilsBeforeLimit > 0 then
            for i = lastIndex + 1, key - 1 do
              --set missing indices
              addLast(key, nil)
              nilsBeforeLimit = nilsBeforeLimit - 1
              if nilsBeforeLimit == 0 then
                break
              end
            end
          end
          lastIndex = key
        end
        --add key to list
        addLast(key, object[key])
      end
    end
  end
  return keys, values, n
end

local loaders = {
  ["table"] = function(path, object)
    local keys, values, length = loadKeyValues(object)
    local environment = localEnvironment(object, keys, values)
    return {
      path   = path,             --How the path to this object is called. Gives the user some directions.
      object = object,           --the loaded object
      keys   = keys,             --list of keys, index(number or string) - > key
      values = values,           --list of values
      length = length,           --number of keys/values, useful if some of them are nil (no ipairs)
      environment = environment, --used when executing a command
      typ    = "table",          --used to get a drawing function
    }
  end,
  ["string"] = function(path, object)
    local environment = localEnvironment(object)
    --create an escaped version of the string
    --[[local text = object:gsub(".", function(old)
      local byte = old:byte()
      if byte < 32 and byte ~= 13 and byte ~= 10 then
        return string.format("\\%03u", byte)
      end
    end)]]
    --separates lines for easier processing
    local lines = {}
    local length = 0
    for line in string.gmatch(object, "([^\r\n]*)\r?\n?") do
      length = length + 1
      lines[length] = line
    end
    return {
      path   = path,
      object = object,
      lines  = lines,
      length = length,
      environment = environment,
      typ    = "string",
    }
  end,
  ["list"] = function(path, ...)
    local object = table.pack(...)
    local length = object.n
    if length == 0 then
      return nil
    end
    --delete length from list; else it's value would also be shown
    object.n = nil
    local keys, values = loadKeyValues(object, true)
    local environment  = localEnvironment(object, nil, values)
    return {
      path   = path,
      object = object,
      values = values,
      length = length,
      environment = environment,
      typ    = "list",
    }
  end,
}

local function loadObject(typ, ...)
  local loader = loaders[typ]
  local obj = loader and loader(...)
  return obj
end


--****VIEWS****
--views are reloaded, when there is a screen width change
local views = {
  ["table"] = function(obj, context)
    local dictionary  = context.dictionary
    local colors  = context.colors
    local content = tables.create{
      layout = { -dictionary.width, 1, -2, -dictionary.width, 1},
      alignment = {"l", "la", "r", "l", "la"},
      empty = " ",
      index = {"_K", "_K", nil, "_V", "_V"},
      separator = "|",
    }
    for index = 1, obj.length do
      local key   = obj.keys  [index]
      local value = obj.values[index]
      local bgColor = colors.background.content[((index - 1) % #colors.background.content) + 1]
      local keyColor   = getValueColor(colors, key)
      local keyTypeColor = getTypeColor(colors, type(key))
      local valueColor = getValueColor(colors, value)
      local valueTypeColor = getTypeColor(colors, type(value))
      content.add{
        dictionary[type(key)], getDisplayedString(key), string_indices[index], dictionary[type(value)], getDisplayedString(value),
        foreground = {keyTypeColor, keyColor, nil, valueTypeColor, valueColor},
        background = bgColor,
      }
    end
    local viewTables = {
      tables.create{
        {obj.path},
        alignment = "la",
        height = 1,
      },
      tables.create{
        {"Keys", "|  |", "Values"},
        layout    = {  1, - 4,  1},
        alignment = "cl",
        height = 1,
      },
      tables.create{
                 {dictionary.type, "|", "value", "|ID|", dictionary.type, "|", "value"},
                 {""             , "+", ""     , "+--+", ""             , "+", "",
                   padding = "-",
                 },
        layout = { -dictionary.width, -1, 1, -4, -dictionary.width, -1, 1},
        alignment = "l",
        height = 2,
      },
      content,
      tables.create{
                 {""             , "+", ""     , "+--+", ""             , "+", ""},
        layout = { -dictionary.width, -1, 1, -4, -dictionary.width, -1, 1},
        alignment = "l",
        padding = "-",
        height = 1,
      },
    }
    return viewTables, content
  end,
  ["list"] = function(obj, context)
    local dictionary  = context.dictionary
    local colors  = context.colors
    local content = tables.create{
      layout = { -2, -dictionary.width, 1},
      empty = " ",
      index = {nil, "_V", "_V"},
      separator = "|",
      alignment = {"r", "l", "la"},
    }
    for index = 1, obj.length do
      local value = obj.object[index]
      local bgColor = colors.background.content[((index - 1) % #colors.background.content) + 1]
      local valueColor = getValueColor(colors, value)
      local valueTypeColor = getTypeColor(colors, type(value))
      content.add{
        string_indices[index], dictionary[type(value)], getDisplayedString(value),
        foreground = {nil, valueTypeColor, valueColor},
        background = bgColor,
      }
    end
    local viewTables = {
      tables.create{
        {obj.path},
        alignment = "la",
        height = 1,
      },
      tables.create{
                 {"ID|", dictionary.type, "|", "value"},
                 {"--+", ""             , "+", "",
                   padding = "-",
                 },
        layout = { -3, -dictionary.width, -1, 1},
        alignment = "l",
        height = 2,
      },
      content,
      tables.create{
                 {"--+", "","+",""},
        layout = { -3, -dictionary.width, -1, 1},
        padding = "-",
        alignment = "l",
        height = 1,
      },
    }
    return viewTables, content    
  end,
  ["string"] = function(obj, context)
    local colors  = context.colors
    local typeColor = getTypeColor(colors, "string")
    local content = tables.create{
      alignment = "l",
      layout = {1, -1},
      foreground = {typeColor, 0xFF0000},
      background = bgcolor,
    }
    local index = 1
    for _, line in ipairs(obj.lines) do
      --line wrapping
      local writtenPerStep = math.max(context.width - 1, 1)
      local lineLength = unicode.len(line)
      for fromIndex = 1, lineLength, writtenPerStep do
        local bgColor = colors.background.content[((index - 1) % #colors.background.content) + 1]
        part = unicode.sub(line, fromIndex, fromIndex + writtenPerStep - 1)
        content.add{
          part, (fromIndex + writtenPerStep < lineLength) and ">" or " ",
        }
        index = index + 1
      end
    end
    local viewTables = {
      tables.create{
        {obj.path},
        {"",
          padding = "-",
        },
        alignment = "la",
        height = 2,
      },
      content,
      tables.create{
        {""},
        padding = "-",
        alignment = "l",
        height = 1,
      },
    }
    return viewTables, content    
  end,
}
local function initView(obj, context)
  local viewLoader = views[obj.typ]
  if not viewLoader then
    return nil
  end
  ---common loading code
  local view = {}
  local viewTables, content = viewLoader(obj, context)
  --positioning of tables
  local totalHeight = 0
  for _, tab in ipairs(viewTables) do
    totalHeight = totalHeight + (tab.height or 0)
  end
  content.height = context.height - totalHeight
  --calculate scrolling boundary
  view.maxScrollY = math.max(#content - content.height, 0)
  local y = 1
  for _, tab in ipairs(viewTables) do
    tab.y = y
    y = y + tab.height
  end
  --on initialization: draw everything
  function view.draw(scrollY)
    local gpu = context.gpu
    gpu.dirty()
    for _, tab in ipairs(viewTables) do
      tab.draw(gpu, 1,tab.y, context.width, tab.height, tab == content and scrollY or 0)
    end
    gpu.setForeground(context.colors.default)
    gpu.setBackground(context.colors.background.command)
    gpu.flush(true)
  end
  --else: only things that could have changed (content)
  function view.update(scrollY)
    local gpu = context.gpu
    gpu.dirty()
    content.draw(gpu, 1,content.y, context.width, content.height, scrollY)
    gpu.setForeground(context.colors.default)
    gpu.setBackground(context.colors.background.command)
    gpu.flush(true)
  end
  --ensures that the scrolling position remains in the range it is allowed to be
  function view.clipScrolling(scrollY)
    return math.max(math.min(view.maxScrollY, scrollY), 0)
  end
  --updates the table callbacks used for scrolling long strings
  function view.updateScrollingCallbacks()
    local gpu = context.gpu
    gpu.dirty()
    for _, tab in ipairs(viewTables) do
      tab.updateScrollingCallbacks()
    end
    gpu.setForeground(context.colors.default)
    gpu.setBackground(context.colors.background.command)
    gpu.flush(true)
  end
  if content.index then
    --returns a lua code representing the clicked object when used with the object environment
    function view.getClicked(x, y,scrollY)
      --determine the clicked column
      local column = content.getColumn(x - 1, context.width)
      if column then
        --get an index which is always able to reference the clicked object
        local env_index = content.index[column]
        if env_index then
          --determine the clicked row
          local row = content.getRow(y - content.y, content.height, scrollY)
          if row then
            --get the value to check for its type and to see if you can write a nicer reference
            local value = obj.environment[env_index][row]
            --nice references are only possible for values, not for keys
            if env_index == "_V" and obj.keys then
              local key = obj.keys[row]
              --their key has to be a valid identifier
              if isValidIdentifier(key) then
                --and this identifier has to work in the environment used by the command line
                if obj.environment[key] == value then
                  return key, type(value)
                end
              end
            end
            --if everything fails there is still the possibility for _K.a, _V.b etc.
            return env_index.."."..string_indices[row], type(value)
          end
        end
      end
    end
  end
  return view
end

--****GPU FILTERING****
local function catchGPUAccess(...)
  --This function executes the given function while monitoring the primary gpu for any access.
  --If the primary GPU is used, it resets the screen.
  --In that case it will also wait for the user after execution.
  --has the screen been modified?
  local touched = false
  --running command is trying to write to the screen, clean up the mess...
  local function touch(invoke, address, ...)
    touched = true
    --get screen size
    local width, height = invoke(address, "getResolution")
    --reset the screen
    local oldBackground = invoke(address, "getBackground")
    invoke(address, "setBackground", 0x000000)
    invoke(address, "fill", 1,1, width, height, " ")
    invoke(address, "setBackground", oldBackground)
    return invoke, address, ...
  end
  
  --a list of all method names, which are in one way or another
  --interacting with the screen and therefore triggering graphics execution mode
  --setResolution does not belong in there, because it is not touching the screen content
  local touchingMethods = {
    --these commands modify
    set = true,
    fill = true,
    bind = true,
    get = true,
  }
  --checks if the current access is doing anything important with the gpu
  local function check(invoke, address, method, ...)
    if not touched and component.isPrimary(address) then
      local f = touchingMethods[method]
      if f then
        if type(f) == "function" then
          --currently unused, could be used to give gpu.get
          --a fake output when the screen wasn't touched
          return f(invoke, address, method, ...)
        else
          --we've got a relevant access, reset screen and remember to wait after execution
          touch(invoke, address)
        end
      end
    end
    return invoke(address, method, ...)
  end
  local filters = {
    gpu = check,
  }
  --reads a given part of the screen and saves the contents
  local function readFrontbuffer(gpu, x,y, width)
    --the data structure used to store the old screen content
    local data = {
      characters = {},
      foreground = {},
      background = {},
    }
    local maxX, maxY = gpu.getResolution()
    if y > maxY then
      --boundary check: failed
      return data
    end
    for i = 1, width do
      if x > maxX then
        --boundary check: failed
        break
      end
      --get content on position (x, y) and remember it
      local char, fg,bg = gpu.get(x, y)
      data.characters[i] = char
      data.foreground[i] = fg
      data.background[i] = bg
      --move on
      x = x + 1
    end
    return data
  end
  --writes the given screen contents back to the screen
  local function writeFrontbuffer(gpu, x,y, data)
    local maxX, maxY = gpu.getResolution()
    if y > maxY then
      --boundary check: failed
      return
    end
    for i, char in ipairs(data.characters) do
      if x > maxX then
        --boundary check: failed
        return
      end
      --setting colors
      local fg = data.foreground[i]
      if fg then
        gpu.setForeground(fg)
      end
      local bg = data.background[i]
      if bg then
        gpu.setBackground(bg)
      end
      --drawing character
      gpu.set(x, y,char)
      --moving on
      x = x + 1
    end
  end
  --if graphics execution mode is active: wait until the user finished reading
  local function waitForKeyboardIfTouched(...)
    if touched then
      --display message to user, alternating between original content and message?
      local gpu = draw_buffer.new(component.gpu)
      local width, height = gpu.getResolution()
      local msg = "Press any key..."
      local originalContent = readFrontbuffer(gpu, 1, height, unicode.len(msg))
      local showMessage = true
      local timerID = event.timer(1.5, function()
        local width, height = gpu.getResolution()
        if showMessage then
          --draw message
          gpu.setForeground(0xFFFFFF)
          gpu.setBackground(0x000000)
          gpu.set(1, height, msg)
        else
          --restore original screen content
          writeFrontbuffer(gpu, 1,height, originalContent)
        end
        gpu.flush()
        showMessage = not showMessage
      end, math.huge)
      --Don't crash here! It would leave an annoying timer alive.
      pcall(function()
        --clear events
        os.sleep(0.1)
        --wait for key press event
        event.pull("key_down")
        event.pull("key_up")
      end)
      --cleanup
      writeFrontbuffer(gpu, 1, height, originalContent)
      gpu.flush()
      event.cancel(timerID)
    end
    return ...
  end
  return waitForKeyboardIfTouched(component_filter.call(filters, ...))
end

--****COMMAND LINE****
local shell = require("shell")
local function runCommand(cmd, environment)
  if cmd:match("^sh ") then
    --shell
    cmd = cmd:gsub("^sh ", "")
    return catchGPUAccess(shell.execute, cmd, environment)
  else
    --lua
    cmd = cmd:gsub("^=","return ")
    local func, err = load(cmd, nil, "t", environment)
    if func then
      return catchGPUAccess(xpcall, func, debug.traceback)
    else
      return false, err
    end
  end
end


--****BROWSING****
local browseValue, browseList
local function browse(typ, pathName, ...)
  local loadedObject, view, context
  local scrollY = 0
  local scrollStep = 1
  --marks that a context has been changed
  local contextDirty = false
  
  local function pressCtrlC()
    computer.pushSignal("key_down",  component.keyboard.address, 0, keyboard.keys.lcontrol)
    computer.pushSignal("key_down",  component.keyboard.address, 99,keyboard.keys.c)
    computer.pushSignal("key_up"  ,  component.keyboard.address, 99,keyboard.keys.c)
    computer.pushSignal("key_up"  ,  component.keyboard.address, 0, keyboard.keys.lcontrol)
  end
  local function forceContextReset()
    if not contextDirty then
      --remember the context after term.read fails
      contextDirty = true
      --send Ctrl + C
      pressCtrlC()
    end
  end
  --loaded on context changes...
  local function resetContext()
    --wait for a gpu and a screen
    while not term.isAvailable() do
      event.pull("term_available")
    end
    --acquire data
    local gpu = component.gpu
    local width, height = gpu.getResolution()
    local depth = gpu.getDepth()
    --anything less doesn't make sense and could lead to errors
    userAssert(width >= 20 and height >= 7, "20x7 resolution required!")
    context = {
      gpu         = draw_buffer.new(gpu),
      dictionary  = configDictionary(width),
      colors      = configColors(depth),
      width       = width,
      height      = height - 1,
    }
    userAssert(context.dictionary, "No dictionary found!")
    scrollStep = math.max(math.floor((height - 6) / 2), 1)
    view = initView(loadedObject, context)
    scrollY = view.clipScrolling(scrollY)
    view.draw(scrollY)
    gpu.fill(1, height, width, 1, " ")
    return true
  end
  local function reload(...)
    loadedObject = loadObject(typ, pathName or "/", ...)
    if loadedObject == nil then
      return false
    end
    resetContext()
    return true
  end
  --initialization, return if there is nothing to display
  if not reload(...) then
    return false
  end
  --sets the main variables to nil to reduce memory usage during recursion
  local function clean()
    loadedObject = nil --could be changed by command
    context      = nil --could be changed by command (e.g. setResolution(...))
    view         = nil --depends on the other two parts
  end
  ---registering event listeners
  local function scroll(dy)
    local oldScrollY = scrollY
    scrollY = view.clipScrolling(scrollY + dy)
    if scrollY ~= oldScrollY then
      view.update(scrollY)
    end
  end
  --list of listener functions
  local listeners = {
    screen_resized = function(_, address, width, height)
      if context.gpu.getScreen() == address then
        forceContextReset()
      end
    end,
    key_down = function(_, address, char, code, player)
      if component.isPrimary(address) then
        local keys = keyboard.keys
        if code == keys.pageUp then
          scroll(-scrollStep)
        elseif code == keys.pageDown then
          scroll( scrollStep)
        end
      end
    end,
    scroll = function(_, address, x, y, direction, player)
      if context.gpu.getScreen() == address then
        scroll(-direction * scrollStep)
      end
    end,
    touch = function(_, address, x, y, button, player)
      if context.gpu.getScreen() == address then
        if view.getClicked then
          local clickedIndex, clickedType = view.getClicked(x, y,scrollY)
          if clickedIndex then
            if button == 0 then
              --normal click: just add a reference to the selected object
              computer.pushSignal("clipboard", component.keyboard.address, clickedIndex, player)
            elseif button == 1 then
              --right click: combined functions
              if clickedType == "function" then
                --types "=index()" and moves cursor between the parenthesis
                computer.pushSignal("clipboard", component.keyboard.address, "="..clickedIndex.."()", player)
                computer.pushSignal("key_down",  component.keyboard.address, 0,keyboard.keys.left, player)
                computer.pushSignal("key_up"  ,  component.keyboard.address, 0,keyboard.keys.left, player)
              else
                --types "=index\n", that should also execute the command
                computer.pushSignal("clipboard", component.keyboard.address, "="..clickedIndex.."\n", player)
              end
            end
          end
        end
      end
    end,
  }
  local function updateScrollingCallbacks()
    view.updateScrollingCallbacks()
  end
  local scrollingTimer
  --registering loop
  local function listen()
    for name, listener in pairs(listeners) do
      event.listen(name, listener)
    end
    if scrollingTimer then
      event.cancel(scrollingTimer)
    end
    scrollingTimer = event.timer(1.5, updateScrollingCallbacks, math.huge)
  end
  --cleanup code
  local function ignore()
    for name, listener in pairs(listeners) do
     event.ignore(name, listener)
    end
    if scrollingTimer then
      event.cancel(scrollingTimer)
      scrollingTimer = nil
    end
  end
  --recursion part
  local function checkRecursion(cmd, ok,...)
    local nvalues = select("#", ...)
    local path = pathName or ""
    if nvalues > 0 then
      --get new path
      cmd = cmd:match("^[^\r\n]*")
      if nvalues == 1 then
        local index, environmentName = findEnvironmentIndex(..., loadedObject.environment)
        if environmentName == "_OBJ" then
          environmentName = nil
        end
        if type(index) == "string" then
          --limitting the displayed index size
          index = index:match("^[^\r\n]*")
          if unicode.len(index) > 32 then
            index = unicode.sub(index, 1, 32)
          end
        end
        path = path .. "/" .. (getDisplayedIndex(index, environmentName) or (cmd))
      else
        path = path .. "/" .. cmd
      end
      --freeing resources to reduce memory consumption
      clean()
      --display results
      if ok then
        if nvalues > 1 or not browseValue(path, ...) then
          return browseList(path, ...)
        else
          return true
        end
      else
        return browseValue(path.." -> Error", ...)
      end
    end
  end
  --term.read hints
  local function getHint(line, cursor)
    if loadedObject.keys == nil then
      return nil
    end
    local firstCode = unicode.sub(line, 1, cursor - 1)
    local nextCode = unicode.sub(line, cursor, -1)
    local previousCode, searchFilter = firstCode:match("^(.-)("..identifierPattern..")$")
    if not previousCode then
      --no preexisting identifier part
      return nil
    end
    local parentObject = loadedObject.object
    do
      --checking part before dot (current object only)
      local prefix, parents = previousCode, {}
      while prefix and prefix ~= "" do
        local key
        prefix, key = prefix:match("^(.-)("..identifierPattern..")%.$")
        if key then
          parents[#parents + 1] = key
        end
      end
      for i = #parents, 1, -1 do
        local key = parents[i]
        if not isValidIdentifier(key) then
          return nil
        end
        parentObject = parentObject[key]
        if parentObject == nil then
          return nil
        end
      end
    end
    local list = {}
    local searchedLength = unicode.len(searchFilter)
    for key in pairs(parentObject) do
      if type(key) == "string" and isValidIdentifier(key) then
        if unicode.len(key) > searchedLength then
          --compare prefix of key to already typed value
          if unicode.sub(key, 1, searchedLength) == searchFilter then
            table.insert(list, previousCode .. key .. nextCode)
          end
        end
      end
    end
    table.sort(list)
    if list[1] then
      return list
    else
      return nil
    end
  end
  --start event processing
  listen()
  --history remains local, if you want to reuse code: Use _G!
  local history = {}
  local ok, err = xpcall(function(...)
    while true do
      --using pcall for term.read because it has problems with screen resizing
      local ok, cmd = pcall(function()
        term.setCursor(1, context.height + 1)
        return term.read(history, false, getHint)
      end)
      if not ok then
        if cmd == "interrupted" then
          error("interrupted", 0)
        else
          --an error happened in term.read, most likely due to a screen size change
          contextDirty = true
        end
      end
      
      if #history > 20 then
        --limit history size
        table.remove(history, 1)
      end
      if cmd == nil and not term.isAvailable() then
        contextDirty = true
      end
      
      if contextDirty then
        --reload context
        contextDirty = false
        resetContext()
      elseif cmd ~= nil then
        --disable event processing because we are leaving this object for a minute...
        ignore()
        --prepare term: move cursor to top left corner, disable cursor blink
        pcall(term.setCursor, 1,1)
        pcall(term.setCursorBlink, false)
        --reset colors
        context.gpu.setForeground(0xFFFFFF)
        context.gpu.setForeground(0x000000)
        --calling
        checkRecursion(cmd, runCommand(cmd, loadedObject.environment))
        --ignore automatic context reloading...
        event.pull(0.1, "screen_resized")
        --due to possible side effects and because term.read shifts everything upwards: always reload everything
        reload(...)
        --reenable event processing for this object
        listen()
      else
        --Strg/Ctrl + C - > go up
        return
      end
    end
  end, interruptedTraceback, ...)
  --end event processing
  ignore()
  if ok then
    --everything ok, return
    return true
  else
    --forward error without modification
    error(err, 0)
  end
end
browseValue = function(pathName, value)
  return browse(type(value), pathName, value)
end
browseList = function(pathName, ...)
  return browse("list", pathName, ...)
end

--****MAIN****

local parameters, options = shell.parse(...)
--option: don't load proxies and libraries unless told to do so
local doListing = (not options.clean)
local doEventListening = not options.noevent

--**LOAD PARAMETERS**
local parameterValues = {}
for _, name in ipairs(parameters) do
  local address = component.get(name)
  if address ~= nil then
    --1st: component address
    parameterValues[name] = component.proxy(address)
  elseif component.isAvailable(name) then
    --2nd: component type
    parameterValues[name] = component.getPrimary(name)
  else
    --3rd: libraries
    local ok, lib = pcall(require, name)
    if ok then
      parameterValues[name] = lib
    else
      --4th: run command
      local function addResults(ok, ...)
        if ok then
          local list = table.pack(...)
          if list.n > 0 then
            parameterValues[name] = list
          end
        else
          parameterValues[name] = "No component or library found; error when executing as code: " .. (...)
        end
      end
      addResults(runCommand(name, global_environment))
    end
  end
end


--**LOAD COMPONENTS AND LIBRARIES**
local components
local libraries
local cleanup
if doListing then
  --find components
  components = component.list()
  local primaries = {}
  --by address
  for k, _ in pairs(components) do
    local comp_type = component.type(k)
    components[k] = component.proxy(k)
    primaries[comp_type] = true
  end
  --by type
  for k, _ in pairs(primaries) do
    components[k] = component.getPrimary(k)
  end
  
  --find libraries (loaded, preloaded and in lib directory)
  local filesystem = require("filesystem")
  libraries = {}
  --find libraries in files
  local libFiles = {}--absolute path -> library (
  local function addLibrary(name, path)
    local oldName = libFiles[path]
    if oldName == nil or #name < #oldName then
      libFiles[path] = name
    end
  end
  local function addLibs(path, dir, prefix, ext, subPath, libPrefix)
    if path then
      dir, prefix, ext, subPath = path:match("^(.-)([^/]*)%?([^/]*)(.-)$")
      libPrefix = ""
    end
    --don't search working dir
    if dir and prefix and ext and dir ~= "./" and dir ~= "" then
      for file in filesystem.list(dir) do
        if file:sub(1, #prefix) == prefix then
          if file:sub(-#ext, -1) == ext then
            local libname = libPrefix .. file:sub(#prefix + 1, -#ext - 1)
            local absolutePath = dir .. file .. subPath:sub(2, -1)
            if absolutePath:sub(1, 1) ~= "/" then
              absolutePath = fs.concat(os.getenv("PWD") or "/", absolutePath)
            end
            if filesystem.exists(absolutePath) and not filesystem.isDirectory(absolutePath) then
              addLibrary(libname, absolutePath)
            end
          end
        end
        if file:sub(-1, -1) == "/" then
          --directory: recursion
          --(expects "dir" to end with a slash if it isn't empty
          addLibs(nil, dir .. file, prefix, ext, subPath, libPrefix .. file:sub(1, -2) .. ".")
        end
      end
    end
  end
  for path in package.path:gmatch("[^;]+") do
    addLibs(path)
  end
  for path, libname in pairs(libFiles) do
    if libraries[libname] == nil then
      local ok, lib = pcall(require, libname)
      libraries[libname] = lib
    end
  end
  --add preloaded libraries
  for libname, loader in pairs(package.preload) do
    local ok, lib = pcall(require, libname)
    libraries[libname] = lib
  end
  --add loaded libraries
  for libname, library in pairs(package.loaded) do
    if library ~= false then
      libraries[libname] = library
    end
  end
  
  if doEventListening then
    --event listeners for a dynamic component list
    local function componentListener(event, key)
      if event == "component_added" then
        components[key] = component.proxy(key)
      elseif event == "component_available" then
        components[key] = component.getPrimary(key)
      elseif event == "component_removed" then
        components[key] = nil
      elseif event == "component_unavailable" then
        components[key] = nil
      end
    end
    event.listen("component_added", componentListener)
    event.listen("component_removed", componentListener)
    event.listen("component_available", componentListener)
    event.listen("component_unavailable", componentListener)
    
    function cleanup()
      event.ignore("component_added", componentListener)
      event.ignore("component_removed", componentListener)
      event.ignore("component_available", componentListener)
      event.ignore("component_unavailable", componentListener)
    end
  end
end

--**LAST STEPS TO FINAL ENVIRONMENT**
local default_object = {
  environment = global_environment,
  components = components and read_only(components, "components is read only!"),
  libraries = libraries and read_only(libraries, "libraries is read only!"),
}
local main_object = default_object
if #parameters > 0 and next(parameterValues) then
  parameterValues["==default=="] = default_object
  main_object = parameterValues
end

--**EXECUTE**

local ok, err = xpcall(browseValue, interruptedTraceback, nil, main_object)

if cleanup then
  cleanup()
end

if not ok and err ~= "interrupted" then
  error(err, 0)
end
