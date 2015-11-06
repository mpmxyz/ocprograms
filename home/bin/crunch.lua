-----------------------------------------------------
--name       : bin/crunch.lua
--description: lua source code compressor
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/511-crunch-break-the-4k-limit/
-----------------------------------------------------
--[[
  source code compressor for OpenComputers
  for further information check the usage text or man page
  
  TODO: debug output / replacement table (--whatis=T -> "require")
  TODO: optional "local" removal -> make locals globals
  TODO: marking constant expressions -> constant folding
  TODO: dependency tree -> "local" concatenation
]]

--**load libraries**--
local parser    = require("parser.main")
local luaparser = require("parser.lua")
local cache     = require("mpm.cache").wrap
local lib       = require("mpm.lib")

--pcall require for compatibility with lua standalone
local shell
do
  local ok
  ok, shell = pcall(require, "shell")
  if not ok then
    --minimal implementation
    shell = {
      resolve = function(path)
        return path
      end,
      parse = function(...)
        return {...}, {}
      end,
    }
  end
end
local computer
do
  local ok
  ok, computer = pcall(require, "computer")
  if not ok then
    computer = {
      uptime = function()
        return 0
      end,
    }
  end
end
local event
do
  local ok
  ok, event = pcall(require, "event")
  if not ok then
    event = nil
  end
end

--**parse arguments**--
local files, options = shell.parse(...)
--tree/notree
if options.tree == nil then
  --default: use tree if available
  options.tree = (luaparser.lrTable ~= nil)
end
options.tree = options.tree and not options.notree

--lz77 settings
if options.lz77 then
  if options.lz77 == true then
    options.lz77 = 80
  else
    options.lz77 = math.max(10, math.min(230, tonumber(options.lz77)))
  end
end

--verbose output function
local verbose
if options.verbose then
  verbose = function(s, ...)
    print(s:format(...))
  end
else
  verbose = function() end
end

--checking arguments
local USAGE_TEXT = [[
Usage:
crunch [options] INPUT.lua [OUTPUT, default: INPUT.cr.lua]
option             description
--blacklist=a,b...  does not touch given globals
--blacklist=*       does not touch globals at all
--tree --notree     enforce doing or not doing
                    full parsing (->renaming)
                    (default: do full parsing
                     if parsing table is known)
--lz77[=10..230]    enables LZ77 compression,
                    (default value of reference
                     length limit: 80)
]]
--no files given: print usage text
if #files == 0 then
  io.stdout:write(USAGE_TEXT)
  return
end

--**blacklists**--
local blacklisted_names  = {_ENV = true, self = true}

--blacklist keywords to prevent them being used as a replacement name
for _, keyword in pairs(luaparser.keywords) do
  blacklisted_names[keyword] = true
end

--blacklist custom names, applies to globals and replacement names
if type(options.blacklist) == "string" then
  for name in options.blacklist:gmatch(luaparser.patterns.name) do
    blacklisted_names[name] = true
  end
end

--**helper functions**--
local namePrefix = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
local nameRest   = namePrefix .. "0123456789"
local function extractChar(prefix, num, charTable)
  local i = (num - 1) % #charTable + 1
  return prefix .. charTable:sub(i,i), math.max(math.floor((num - 1) / #charTable), 0)
end

--take a 1 based index and return an associated identifier
--that may be a valid variable name (keywords are not filtered out)
local numberToName = cache(function(num)
  local name, num = extractChar("", num, namePrefix)
  while num > 0 do
    name, num = extractChar(name, num, nameRest)
  end
  return name
end)

--takes the given path and inserts the infix in front of the file extension of the file path
--appends the infix to the end of the path if there is no file extension
local function addInfix(path, infix)
  local prefix, dot, extension = path:match("^(.-)(%.?)([^%.%/]*)$")
  if dot == "" then
    return path .. infix
  else
    return prefix .. infix .. dot .. extension
  end
end

--**compression**--
--designed as a two pass compiler
--first pass: reading from file; analyzing code; counting name occurences
--intermediate: create name conversion table
--second pass: converting code; shortening names; writing to file

--iterates the contents of the given tree node
--determines actions by using the token type as the index for the table 'actions'
local function traverseTree(node, actions)
  if type(node) == "table" then
    --couldn't use ipairs due to "yielding across c boundary" errors
    local i = 1
    while node[i] do
      local token = node[i]
      local typ = type(token) == "table" and token.typ or ""
      local action = actions[typ]
      if action == nil then
        action = actions.default
      end
      if action ~= nil then
        local replacement = action(token)
        if replacement then
          node[i] = replacement
        end
      end
      i = i + 1
    end
  end
end

--returns a function which is returning a new index on every call
--(starts with index 1)
local function idGenerator(lastID)
  lastID = lastID or 0
  return function()
    lastID = lastID + 1
    return lastID
  end
end

--creates a new 'scope' table
--This table helps to identify variables at certain positions in the code.
local function createScope()
  local scope = {}
  --ids
  local newID = idGenerator()
  --tables for names and stack positions
  scope.names = {}
  scope.stackIndices = {}
  --_ENV
  scope._ENV = cache(function(name)
    --_ENV access is marked by string ids
    local id = newID()
    scope.names[id] = name
    return id
  end)
  --stack functions, numeric indices are used for the scope stack
  scope[1] = scope._ENV
  --pushes a copy of the top scope on the stack
  function scope:push()
    self[#self+1] = self:fork()
  end
  --removes the top scope
  function scope:pop()
    local top = self:top()
    self[#self] = nil
    return top
  end
  --returns the top scope
  function scope:top()
    return self[#self]
  end
  --overwrites the top scope
  function scope:setTop(obj)
    self[#self] = obj
  end
  --scope forking: copies the scope
  function scope:fork()
    local parent = self:top()
    local forked = cache(function(name)
      return self._ENV[name]
    end)
    --always do a full copy to avoid memory problems with many local definitions
    for k,v in pairs(parent) do
      forked[k] = v
    end
    --index 0 is used to count the local variables on the stack
    forked[0] = rawget(parent, 0) or 0
    return forked
  end
  --adds a new local definition
  function scope:newLocal(name)
    local top = self:top()
    local id = newID()
    top[name] = id
    self.names[id] = name
    local stackIndex = top[0] + 1
    top[0] = stackIndex
    self.stackIndices[id] = stackIndex
  end
  --returns the numeric id associated to the given name
  function scope:get(name)
    local top = self:top()
    return top[name]
  end
  --returns the local stack index for the given name
  --returns nil if the name refers to a global variable
  function scope:stackIndex(name)
    local id = self:get(name)
    return self.stackIndices[id]
  end
  return scope
end


--forward declaration of the 'compressor' table
--used as the object responsible for compressing
local compressor

--creates a generic tree processor
--takes a table with callbacks (token typ -> function)
--returns an actions table for traverseTree
local function createTreeProcessor(callbacks, scope)
  local statements
  local actions
  
  local function onFunction(token)
    --function name <funcbody>
    actions.default (token[1])
    actions.funcname(token[2])
    actions.funcbody(token[3])
  end
  local function onLocal(token)
    actions.default(token[1])
    local original = scope:top()
    local forked = scope:fork()
    local second = token[2]
    local third  = token[3]
    local fourth = token[4]
    if second == "function" then
      --local function abc <funcbody>
      scope:setTop(forked)
      scope:newLocal(third[1])
      actions.default(second)
      token[3] = actions.access(third)
      actions.funcbody(fourth)
    elseif second.typ == "namelist" then
      --local a,b,c
      scope:setTop(forked)
      for i = 1, #second, 2 do
        scope:newLocal(second[i][1])
      end
      actions.namelist(second)
      if third then
        --=d,e,f
        scope:setTop(original)
        actions.default(third)
        actions.default(fourth)
        scope:setTop(forked)
      end
    else
      error()
    end
  end
  local function onDo(token)
    --do <block> end
    scope:push()
    traverseTree(token, actions)
    scope:pop()
  end
  local function onRepeat(token)
    --repeat <block> until <exp>
    scope:push()
    traverseTree(token, actions)
    scope:pop()
  end
  local function onFor(token)
    actions.default(token[1])
    local original = scope:top()
    local forked = scope:fork()
    local second = token[2]
    
    scope:setTop(forked)
    if second.typ == "name" then
      --for name = <exp>,<exp>[,<exp>] do <block> end
      scope:newLocal(second[1])
      token[2] = actions.access(second)
    elseif second.typ == "namelist" then
      --for name in <explist> do <block> end
      for i = 1, #second, 2 do
        scope:newLocal(second[i][1])
      end
      actions.namelist(second)
    else
      error()
    end
    local i = 3
    scope:setTop(original)
    while token[i] ~= "do" do
      actions.default(token[i])
      i = i + 1
    end
    scope:setTop(forked)
    while token[i] do
      actions.default(token[i])
      i = i + 1
    end
    scope:setTop(original)
  end
  local function onIf(token)
    --if exp then block
    actions.default(token[1])
    actions.default(token[2])
    actions.default(token[3])
    scope:push()
    actions.default(token[4])
    scope:pop()
    local i = 5
    while token[i] == "elseif" do
      --elseif exp then block
      actions.default(token[i+0])
      actions.default(token[i+1])
      actions.default(token[i+2])
      scope:push()
      actions.default(token[i+3])
      scope:pop()
      i = i + 4
    end
    if token[i] == "else" then
      --else block
      actions.default(token[i+0])
      scope:push()
      actions.default(token[i+1])
      scope:pop()
    end
    --end
    actions.default(token[#token])
  end
  local function onWhile(token)
    --while exp do block end
    actions.default(token[1])
    actions.default(token[2])
    actions.default(token[3])
    scope:push()
    actions.default(token[4])
    scope:pop()
    actions.default(token[5])
  end
  
  --statement look up table
  statements = {
    ["function"] = onFunction,
    ["local"] = onLocal,
    ["do"] = onDo,
    ["repeat"] = onRepeat,
    ["for"] = onFor,
    ["if"] = onIf,
    ["while"] = onWhile,
  }

  local function onVar(token)
    --get type of first token
    --if it is a name: add usage to name
    if type(token[1]) == "table" and token[1].typ == "name" then
      token[1] = actions.access(token[1])
      for i = 2, #token do
        actions.default(token[i])
      end
    else
      traverseTree(token, actions)
    end
  end
  local function onNamelist(token)
    --name[,name]*
    for i = 1, #token, 2 do
      if i > 1 then
        actions.default(token[i-1])
      end
      token[i] = actions.access(token[i])
    end
  end
  
  local function onFunctiondef(token)
    --function <funcbody>
    actions.default(token[1])
    actions.funcbody(token[2])
  end
  local onFuncname = onVar
  local function onFuncbody(token)
    --(<parlist>) <block> end
    scope:push()
    traverseTree(token, actions)
    scope:pop()
  end
  local function onParlist(token)
    --[name[,name]*[,...]|...]
    for i = 1, #token, 2 do
      if i > 1 then
        actions.default(token[i-1])
      end
      local arg = token[i]
      if arg ~= "..." then
        scope:newLocal(arg[1])
        token[i] = actions.access(arg)
      else
        actions.default(arg)
      end
    end
  end
  local function onStat(token)
    --decision based on the first token
    local action = statements[token[1]]
    if action then
      return action(token)
    else
      actions.default(token)
    end
  end
  local function onDefault(token)
    return traverseTree(token, actions)
  end
  local function onString(token)
    --process the string with its quotes at once
    actions.default(table.concat(token))
  end
  local function onNumber(token)
    --process the contents of the number
    actions.default(token[1])
  end
  
  --action look up table
  actions = {
    var = onVar,
    stat = onStat,
    parlist = onParlist,
    functiondef = onFunctiondef,
    funcbody = onFuncbody,
    funcname = onFuncname,
    namelist = onNamelist,
    default  = onDefault,
    access   = onDefault,
    string   = onString,
    number   = onNumber,
  }
  --add callbacks
  for key, action in pairs(actions) do
    local callback = callbacks[key] or callbacks.default
    if callback then
      actions[key] = function(token)
        --execute callback before action
        local replacement = callback(token) or token
        action(replacement)
        return replacement
      end
    end
  end
  return actions
end

local function onError(msg, inputFile)
  local line = type(msg.line) == "number" and ("%u"):format(msg.line) or msg.line or ""
  error{msg = ("%s:%s: %s"):format(inputFile, line, options.debug and msg.traceback or msg.error)}
end

local function isIdentifier(name)
  return type(name) == "string" and not luaparser.keywords[name] and name:match(luaparser.patterns.name) == name
end

--**main**--
--compress all given files separately

local loadedModules
local cleanupModules
local function loadModules()
  loadedModules  = {}
  cleanupModules = {}
  --iterate crunch libraries
  for libname, absolutePath in lib.list((package.path:gsub("%?","crunch/?"))) do
    --load libraries, TODO: don't use require to avoid keeping modules in memory?
    local module = require("crunch." .. libname)
    if type(module) == "table" then
      if module.run ~= nil then
        --add all libraries with "run" method to the list
        table.insert(loadedModules, module)
      end
      if module.cleanup then
        table.insert(cleanupModules, module)
      end
    end
  end
end

local function runModules(context, options)
  local wrap
  if options.debug then
    wrap = function(f)
      return function(...)
        --the reason of wrapping: proper traceback information
        local ok, msg = xpcall(f, debug.traceback, ...)
        if not ok then
          --also included: proper error object forwarding
          if type(msg) == "string" then
            error({msg = msg}, 0)
          else
            error(msg, 0)
          end
        end
      end
    end
  else
    wrap = function(f)
      return f
    end
  end
  
  local lastYield = computer.uptime()
  local function antiTimeout()
    if computer.uptime() > lastYield + 0.1 then
      local ev = event.pull(0.0)
      if ev == "interrupted" then
        error{msg = "interrupted"}
      end
      lastYield = computer.uptime()
    end
  end
  
  
  --list of running coroutines
  local running = {}
  --resumes every coroutine using the given parameters
  local function runStep(...)
    --number of running coroutines remaining after execution
    --(needed to update the list of running coroutines in place)
    local nAlive = 0
    for i = 1, #running do
      local current = running[i]
      local ok, err = coroutine.resume(current, ...)
      if not ok then
        error(err, 0)
      end
      antiTimeout()
      if coroutine.status(current) == "suspended" then
        nAlive = nAlive + 1
        running[nAlive] = current
      end
    end
    --deleting old entries at the end of the table
    for i = nAlive + 1, #running do
      running[i] = nil
    end
    return (nAlive > 0)
  end
  
  --instantiate module coroutines
  for i = 1, #loadedModules do
    running[i] = coroutine.create(wrap(loadedModules[i].run))
  end
  
  --run modules for the first time (parameters used for initialization)
  if runStep(context, options) then
    --some parts yielded: finish execution
    while runStep() do end
  end
  --do cleanup in reversed order
  for i = #cleanupModules, 1, -1 do
    cleanupModules[i].cleanup(context, options)
    antiTimeout()
  end
end

local function main()
  --opening file streams
  local inputFile = shell.resolve(files[1])
  verbose("Input file: %s", inputFile)
  local inputStream, err = io.open(inputFile, "rb")
  if inputStream == nil then
    error(("%s: %s"):format(inputFile, err or "Could not read file!"), 0)
  end

  local outputFile = files[2] and shell.resolve(files[2]) or addInfix(inputFile, ".cr")
  verbose("Output file: %s", outputFile)
  local outputStream, err = io.open(outputFile, "wb")
  if outputStream == nil then
    error(("%s: %s"):format(outputFile, err or "Could not write to file!"), 0)
  end
  --creating context table
  local context = {
    inputFile = inputFile,
    inputStream = inputStream,
    outputFile = outputFile,
    outputStream = outputStream,
    onError = onError,
    verbose = verbose,
    createScope = createScope,
    createTreeProcessor = createTreeProcessor,
    traverseTree = traverseTree,
    isIdentifier = isIdentifier,
    blacklisted_names = blacklisted_names,
    numberToName = numberToName,
  }
  --executing compression modules
  loadModules()
  runModules(context, options)
  
  --verbose only: printing output details
  local inSize  = inputStream:seek()
  local outSize = outputStream:seek()
  verbose("Old size: %u bytes", inSize)
  verbose("New size: %u bytes", outSize)
  verbose("New/Old: %.1f%%", 100 * outSize / inSize)
  --closing file streams
  inputStream:close()
  outputStream:close()
end

local ok, err = xpcall(main, options.debug and debug.traceback or function(msg) return msg end)
if not ok then
  io.stderr:write(err.msg or err)
end
