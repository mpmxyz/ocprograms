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
  TODO: string/number optimization
  TODO: general name optimization for everything using ".name"
        (needs black-/whitelist e.g. for table.concat)
  TODO: marking constant expressions -> constant folding
  TODO: dependency tree -> "local" concatenation
]]

--**load libraries**--
local parser    = require("parser.main")
local luaparser = require("parser.lua")
local lz77      = require("parser.lz77")
local cache     = require("mpm.cache").wrap

--pcall require for compatibility with lua standalone
local ok, shell = pcall(require, "shell")
if not ok then
  --minimal implementation
  shell = {
    resolve = function(path)
      return path
    end,
    parse = function(...)
      return {...}, {tree=true}
    end,
  }
end

--**parse arguments**--
local files, options = shell.parse(...)
options.infix = (options.infix or ".cr")
if options.tree == nil then
  --default: use tree if available
  options.tree = (luaparser.lrTable ~= nil)
end
if options.output then
  local output = {}
  for file in options.output:gmatch("[^%,%;]+") do
    output[#output + 1] = file
  end
  if #output > 0 then
    options.output = output
  else
    options.output = nil
  end
end
if options.lz77 then
  if options.lz77 == true then
    options.lz77 = 80
  else
    options.lz77 = math.max(10, math.min(230, tonumber(options.lz77)))
  end
end

--checking arguments
local USAGE_TEXT = [[
Usage:
crunch [options] FILES...
option             description
--infix=INFIX       chars added to the file name
                    (default: ".cr")
--output=FILE,FILE2 overrides output file names
--blacklist=a,b...  does not touch given globals
--blacklist=*       does not touch globals
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
local blacklisted_locals  = {_ENV = true, self = true}
local blacklisted_globals = {_ENV = true, self = true}
local blacklisted_outputs = {_ENV = true, self = true}

--blacklist keywords to prevent them being used as a replacement name
for _, keyword in pairs(luaparser.keywords) do
  blacklisted_outputs[keyword] = true
end

--blacklist custom names, applies to globals and replacement names
if type(options.blacklist) == "string" then
  for name in options.blacklist:gmatch(luaparser.patterns.name) do
    blacklisted_globals[name] = true
    blacklisted_outputs[name] = true
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
    for _, token in ipairs(node) do
      local typ = type(token) == "table" and token.typ or ""
      local action = actions[typ]
      if action == nil then
        action = actions.default
      end
      if action ~= nil then
        action(token)
      end
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
    forked[0] = rawget(parent,0) or 0
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
local function getTreeProcessor(callbacks)
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
    local original = compressor.scope:top()
    local forked = compressor.scope:fork()
    local second = token[2]
    local third  = token[3]
    local fourth = token[4]
    if second == "function" then
      --local function abc <funcbody>
      compressor.scope:setTop(forked)
      compressor.scope:newLocal(third[1])
      actions.default(second)
      actions.access(third)
      actions.funcbody(fourth)
    elseif second.typ == "namelist" then
      --local a,b,c
      compressor.scope:setTop(forked)
      for i = 1, #second, 2 do
        compressor.scope:newLocal(second[i][1])
      end
      actions.namelist(second)
      if third then
        --=d,e,f
        compressor.scope:setTop(original)
        actions.default(third)
        actions.default(fourth)
        compressor.scope:setTop(forked)
      end
    else
      error()
    end
  end
  local function onDo(token)
    --do <block> end
    compressor.scope:push()
    traverseTree(token, actions)
    compressor.scope:pop()
  end
  local function onRepeat(token)
    --repeat <block> until <exp>
    compressor.scope:push()
    traverseTree(token, actions)
    compressor.scope:pop()
  end
  local function onFor(token)
    actions.default(token[1])
    local original = compressor.scope:top()
    local forked = compressor.scope:fork()
    local second = token[2]
    
    compressor.scope:setTop(forked)
    if second.typ == "name" then
      --for name = <exp>,<exp>[,<exp>] do <block> end
      compressor.scope:newLocal(second[1])
      actions.access(second)
    elseif second.typ == "namelist" then
      --for name in <explist> do <block> end
      for i = 1, #second, 2 do
        compressor.scope:newLocal(second[i][1])
      end
      actions.namelist(second)
    else
      error()
    end
    local i = 3
    compressor.scope:setTop(original)
    while token[i] ~= "do" do
      actions.default(token[i])
      i = i + 1
    end
    compressor.scope:setTop(forked)
    while token[i] do
      actions.default(token[i])
      i = i + 1
    end
    compressor.scope:setTop(original)
  end
  local function onIf(token)
    --if exp then block
    actions.default(token[1])
    actions.default(token[2])
    actions.default(token[3])
    compressor.scope:push()
    actions.default(token[4])
    compressor.scope:pop()
    local i = 5
    while token[i] == "elseif" do
      --elseif exp then block
      actions.default(token[i+0])
      actions.default(token[i+1])
      actions.default(token[i+2])
      compressor.scope:push()
      actions.default(token[i+3])
      compressor.scope:pop()
      i = i + 4
    end
    if token[i] == "else" then
      --else block
      actions.default(token[i+0])
      compressor.scope:push()
      actions.default(token[i+1])
      compressor.scope:pop()
    end
    --end
    actions.default(token[#token])
  end
  local function onWhile(token)
    --while exp do block end
    actions.default(token[1])
    actions.default(token[2])
    actions.default(token[3])
    compressor.scope:push()
    actions.default(token[4])
    compressor.scope:pop()
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
      actions.access(token[1])
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
      actions.access(token[i])
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
    compressor.scope:push()
    traverseTree(token, actions)
    compressor.scope:pop()
  end
  local function onParlist(token)
    --[name[,name]*[,...]|...]
    for i = 1, #token, 2 do
      if i > 1 then
        actions.default(token[i-1])
      end
      local arg = token[i]
      if arg ~= "..." then
        compressor.scope:newLocal(arg[1])
        actions.access(arg)
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
    actions.default(table.concat(token))
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
  }
  --add callbacks
  for key, action in pairs(actions) do
    local callback = callbacks[key] or callbacks.default
    if callback then
      actions[key] = function(token)
        --execute callback before action
        callback(token)
        return action(token)
      end
    end
  end
  return actions
end

--takes a stream and returns a wrapper function
--This function takes a string argument to be written and writes it to the stream.
--Appends a newline in front of the string if necessary for separation. (But only then!)
local function newWriter(stream)
  local lastWritten
  return function(text)
    if text ~= "" then
      --detect if space is necessary
      if lastWritten ~= nil and text:find("^[%w_]") and lastWritten:find("[%w_]$") then
        stream:write("\n"..text)
      else
        stream:write(text)
      end
      lastWritten = text
    end
  end
end

--value types can be safely localized (in most cases)
local isValueType = {
  string = true,
  number = true,
  ["nil"] = true,
  ["true"] = true,
  ["false"] = true,
}

--overwrites the compressor variable with a new compressor table
local function initCompressor()
  
  compressor = {
    scope = createScope(),
    uses = {},
    stringArgs = {},
    --used to differentiate between global variable accesses and values
    knownVariables = {},
  }
  
  if options.tree and not options.notree then
    --use full parser; more memory consumption but also a lot more possibilities
    function compressor:analyze(inputStream)
      --simple version: create usage statistics for given names
      --advanced version: create usage statistics for given variables
      --(-> 2 different local variables with same name could be treated differently.)
      --(-> Global variable access could be detected, listed and blacklisted.)
      --(-> 2 different variables could be unified if they do not interfere with each other)
      --1st: load tree
      local tree, err = parser.parse(inputStream:lines(512), luaparser)
      if err then
        error(err.error)
      end
      --TODO: compress strings
      --2nd: traverse tree, remember top level names
      local function onAccess(id)
        self.uses[id] = (self.uses[id] or 0) + 1
      end
      local function onVariable(token)
        --variable access
        local name = token[1]
        self.knownVariables[name] = true
        local id = self.scope:get(name)
        onAccess(id)
      end
      local function onDefault(token)
        --string, number, boolean
        if type(token) == "string" then
          if isValueType[token] then
            onAccess(self.scope:get(token))
          end
        else
          if isValueType[token.typ] then
            onAccess(self.scope:get(table.concat(token)))
          elseif token.typ == "args" then
            --replacing 'func"param"' by 'func(a)' and not by 'func a'
            if #token == 1 then
              local first = token[1]
              if first.typ == "string" then
                local content = table.concat(first)
                local id = self.scope:get(content)
                self.stringArgs[id] = (self.stringArgs[id] or 0) + 1
              end
            end
          end
        end
      end
      
      self.scope:push()
      traverseTree(tree, getTreeProcessor{
        access = onVariable,
        default = onDefault,
      })
      self.scope:pop()
      self.tree = tree
    end
    --creates a dictionary table that is used to replace variables, constants, etc.
    function compressor:buildTranslator()
      --simple version:
      --add blacklisted names
      --sort other names
      --get short version of non blacklisted names
      
      self.dictionary = {}
      local sortedAccessList = {}
      --combine all local variables with the same stack index
      --the 'merged' name is a name that represents all variables with the same stack index
      local function getMergedName(id)
        local name = self.scope.names[id]
        local stackIndex = self.scope.stackIndices[id]
        if stackIndex then
          if blacklisted_locals[name] then
            return
          end
        else
          if blacklisted_globals[name] or (options.blacklist=="*" and self.knownVariables[name]) then
            return
          end
        end
        return stackIndex or name
      end
      --counts the numer of uses of the merged name
      local mergedUses = {}
      --counts the number of times a string is used as a function argument without brackets
      local mergedStringArgs = {}
      for id in ipairs(self.uses) do
        local mergedName = getMergedName(id)
        if mergedName then
          sortedAccessList[#sortedAccessList + 1] = mergedName
          mergedUses[mergedName] = (mergedUses[mergedName] or 0) + self.uses[id]
          --add an additional use for globals (local definition)
          if type(mergedName) == "string" then
            mergedUses[mergedName] = mergedUses[mergedName] + 1
          end
          --remember f"arg" -> f(arg) overhead for string substitution
          mergedStringArgs[mergedName] = (mergedStringArgs[mergedName] or 0) + (self.stringArgs[id] or 0)
        end
      end
      --sort list of names
      table.sort(sortedAccessList, function(a, b)
        local usesA, usesB = mergedUses[a], mergedUses[b]
        if usesA == usesB then
          --prioritize local optimization to global optimization if usage counter is equal
          -->removes local declaration overhead in some cases
          return type(a) == "number" and type(b) ~= "number"
        end
        return usesA > usesB
      end)
      
      --an additional blacklist to avoid generating names that are used for globals
      local blacklisted_due_collision = {}
      local function iterateNames(onName)
        local ranking = 1
        for _, mergedName in ipairs(sortedAccessList) do
          local newName
          repeat
            newName = numberToName(ranking)
            ranking = ranking + 1
            --skip invalid names
          until not blacklisted_outputs[newName] and not blacklisted_due_collision[newName]
          if onName(mergedName, newName) then
            --renaming rejected
            ranking = ranking - 1
          end
        end
      end
      --check how many bytes would be saved by global-localization
      --don't localize where it would not make sense
      do
        --1st filter: don't change globals that aren't used often enough
        local filteredAccessList
        --used to generate local definition
        local localizedGlobals
        --used to limit the number of locals
        local localizationSavings
        local totalSavedBytes
        repeat
          local finished = true
          filteredAccessList  = {}
          localizedGlobals    = {}
          localizationSavings = {}
          totalSavedBytes     = -5 --"local"
          iterateNames(function(mergedName, newName)
            if type(mergedName) == "string" then
              --global
              local overhead = #mergedName + #newName + 2 --2x(" "/"=" or ",")
              local usageSavings
              if #newName + 2 < #mergedName then
                --replacing string arguments without brackets
                usageSavings = (#mergedName - #newName) * (mergedUses[mergedName] - 1) - 2 * mergedStringArgs[mergedName]
              else
                --not replacing string arguments
                usageSavings = (#mergedName - #newName) * (mergedUses[mergedName] - 1 - mergedStringArgs[mergedName])
              end
              local savedBytes = usageSavings - overhead
              if savedBytes <= 0 then
                --prevent generating a variable with the same name
                if not blacklisted_due_collision[mergedName] then
                  --TODO: avoid repetition if the name hasn't been generated yet
                  finished = false
                end
                blacklisted_due_collision[mergedName] = true
                return true
              end
              totalSavedBytes = totalSavedBytes + savedBytes
              localizationSavings[mergedName] = savedBytes
              localizedGlobals[#localizedGlobals + 1] = self.scope:get(mergedName)
            end
            filteredAccessList[#filteredAccessList + 1] = mergedName
          end)
        until finished
        sortedAccessList = filteredAccessList
        if totalSavedBytes > 0 then
          --We saved some bytes: go ahead
          self.localizedGlobals = localizedGlobals
          self.localizationSavings = localizationSavings
        else
          --Overhead is too big.
          filteredAccessList = {}
          iterateNames(function(mergedName, newName)
            if type(mergedName) == "string" then
              --too much localization overhead: ignore globals; blacklist their names
              blacklisted_due_collision[mergedName] = true
              return true
            end
            filteredAccessList[#filteredAccessList + 1] = mergedName
          end)
          --TODO: what about 
          sortedAccessList = filteredAccessList
        end
        --2nd filter: limit number of local variables by removing the least significant localizations
        --TODO
      end
      --give them replacement names
      local mergedDictionary = {}
      iterateNames(function(mergedName, newName)
        mergedDictionary[mergedName] = newName
      end)
      --assign replacement names to the individual ids
      for id in ipairs(self.uses) do
        local mergedName = getMergedName(id)
        if mergedName then
          self.dictionary[id] = mergedDictionary[mergedName]
        end
      end
    end
    --outputs compressed code to the given file
    function compressor:compress(outputStream)
      local write = newWriter(outputStream)
      
      --2nd: traverse tree, remember top level names
      local function getReplacement(id)
        return self.dictionary[id]
      end
      --shorten variable names
      local function onVariable(token)
        local id = self.scope:get(token[1])
        local replacement = getReplacement(id)
        if replacement then
          token[1] = replacement
        end
      end
      local function onDefault(token)
        if type(token) == "string" then
          --replace true, false and nil
          if isValueType[token] then
            local replacement = getReplacement(self.scope:get(token))
            if replacement then
              token = replacement
            end
          end
          write(token)
        else
          if isValueType[token.typ] then
            --replace strings and numbers
            local content = table.concat(token)
            local id = self.scope:get(content)
            local replacement = not token.locked and getReplacement(id) or content
            
            token[1] = replacement
            for i = 2, #token do
              token[i] = nil
            end
          elseif token.typ == "args" then
            --replacing 'func"param"' by 'func(a)' and not by 'func a'
            if #token == 1 then
              local first = token[1]
              if first.typ == "string" then
                local content = table.concat(first)
                local id = self.scope:get(content)
                local replacement = getReplacement(id)
                if replacement and #replacement + 2 < #content then
                  --add brackets if the string is replaced
                  token[1] = "("
                  token[2] = first
                  token[3] = ")"
                else
                  first.locked = true
                end
              end
            end
          end
        end
      end
      
      if self.localizedGlobals then
        --rewrite long global names to locals
        write("local ")
        for i, id in ipairs(self.localizedGlobals) do
          if i > 1 then
            write(",")
          end
          write(self.dictionary[id])
        end
        write("=")
        for i, id in ipairs(self.localizedGlobals) do
          if i > 1 then
            write(",")
          end
          write(self.scope.names[id])
        end
      end
      
      --init scope
      self.scope = createScope()
      self.scope:push()
      --iterate tree
      traverseTree(self.tree, getTreeProcessor{
        access = onVariable,
        default = onDefault,
      })
      self.scope:pop()
    end
  else
    --lexer only; just removes unnecessary whitespace and comments
    function compressor:analyze(inputStream)
      --remember input stream
      self.inputStream = inputStream
    end
    function compressor:buildTranslator()
      --do nothing
    end
    function compressor:compress(outputStream)
      --read and write at once
      --TODO: Does that also work when input==output?
      local write = newWriter(outputStream)
      local function output(typ, source, from, to, extractedToken)
        if not luaparser.ignored[typ] then
          write(extractedToken or source:sub(from, to))
        end
      end
      parser.lexer(self.inputStream:lines(512), luaparser.lexer, output)
    end
  end
end

--**main**--
--compress all given files separately
for i, file in ipairs(files) do
  local inputFile = shell.resolve(file)
  local inputStream = io.open(inputFile, "rb")
  
  local outputFile = options.output and options.output[i] or addInfix(inputFile, options.infix)
  local outputStream = assert(io.open(outputFile, "wb"))
  local originalStream = outputStream
  
  if options.lz77 then
    --LZ77 SXF option
    local function lz77output(value)
      originalStream:write(value)
    end
    --create and init a compressor coroutine
    local lz77yieldedCompress = coroutine.create(lz77.compress)
    assert(coroutine.resume(lz77yieldedCompress, coroutine.yield, options.lz77, lz77output, true))
    
    outputStream = {
      lz77yieldedCompress = lz77yieldedCompress,
      write = function(self, value)
        return assert(coroutine.resume(lz77yieldedCompress, value))
      end,
      close = function()
        return originalStream:close()
      end,
    }
    
    originalStream:write("local i=[[\n")
  end
  initCompressor()
  compressor:analyze(inputStream)
  compressor:buildTranslator()
  compressor:compress(outputStream)
  if options.lz77 then
    --finish lz77 compression
    while coroutine.status(outputStream.lz77yieldedCompress) == "suspended" do
      assert(coroutine.resume(outputStream.lz77yieldedCompress, nil))
    end
    originalStream:write("]]")
    --append decompression code
    originalStream:write(lz77.getSXF("i", "o", options.lz77))
    --append launcher
    originalStream:write("\nreturn assert(load(o))(...)")
  end
  
  inputStream:close()
  outputStream:close()
end
