-----------------------------------------------------
--name       : lib/parser/main.lua
--description: parsing library featuring a regex based lexer and an EBNF configured LR parser
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--**load libraries**--
local cache  = require("mpm.cache").wrap
local sets   = require("mpm.sets")
local setset = require("mpm.setset")
local regex  = require("parser.regex")
local automaton = require("parser.automaton")
local merge  = automaton.merge

local parser = {}

--used to unescape strings
--via s:gsub("\\(.)", parser.unescape)
parser.unescape = cache(function(charAfterSlash)
  assert(#charAfterSlash == 1, "Only the character after the slash is allowed!")
  return load("return '\\"..charAfterSlash.."'")
end, nil, "parser.unescape")

--onMatch(output(type, source, from, to[, extractedSource]), patterns, source, from, to) -> output(type, source, from, to[, extractedSource]), patterns, newFrom, newTo

--[[
  use patterns
  take longest match
  apply special pattern until finished
  
  
  definition = {
    --step by step (allows reusing)
    ["pattern"] = function(output, patterns, source, from, to)
      return output, patterns, from, to
    end,
    --match if nothing matched (-> only if valid)
    [""] = function(output, patterns, source, from, to)
      return output, patterns, from, to
    end,
  }
]]


--associates automatons with actions
--state[""] will return the given action if it is a valid state
--else it will return false.
local associateAction
associateAction = cache(function(action)
  return cache(function(state)
    if state == false then
      return false
    end
    local association = cache(function(char)
      if char == "" then
        return state[""] and action
      else
        return associateAction[action][state[char]]
      end
    end, nil, "association3")
--      getmetatable(association).__tostring = function()
--        return tostring(state)
--      end
    return association
  end, "k", "association2")
end, "k", "association1")

--****LEXER****--

--loads Lua code from the given loader
--(either a source string or a function returning parts on each call)
--'patterns' is a table with regex pattern keys and action values:
--patterns['regex-pattern'] = (function(output, patterns, source, from, to) -> nextOutput, nextPatterns, nextFrom, nextCurrent)
--'output' is a function used by the actions to output tokens:
--You can define it's format however you like as long as it matches the the format expected by the pattern actions.
--As an example, that's the format used by the Lua parser:
--output(type, source, from, to[, extractedSource])
function parser.lexer(loader, patterns, output)
  --the beginning of the token
  local fromIndex = 1
  --the currently read character
  local currentIndex = 1
  --used for more accurate error information
  local lastDoneIndex = 0
  --keeps the current lexer state
  --(several action associated regex automatons merged to one state)
  local currentState
  --remembers the last valid state action and its position
  local lastAction, lastToIndex
  --count number of lines for better debug info
  local currentLine = 1
  --stores the currently loaded source
  local source = ""
  if type(loader) == "string" then
    source = loader
    loader = nil
  end
  --formatting debug messages
  local function onError(msg)
    if type(msg) == "string" then
      return {
        error     = msg,
        line      = currentLine,
        traceback = debug.traceback(msg, 2),
      }
    else
      return msg
    end
  end
  --creates the initial state from all pattern states (+actions)
  local function initState()
    --starting with an empty/invalid state
    currentState = false
    for pattern, action in pairs(patterns) do
      --and adding all initial states
      local patternState = associateAction[action][regex.compile[pattern]]
      currentState = merge[currentState][patternState]
    end
    --test for an empty string/eof action
    local action = currentState[""]
    if action then
      lastAction = action
      lastToIndex = currentIndex - 1
    end
  end
  initState()
  
  --used to avoid counting "\r\n" as two newlines
  local lastWasCarriageReturn = false
  
  --is called to process the return values of the pattern actions
  --The following table shows the values used when an action returns nil:
  --name          what it is                   default (returned value == nil)
  --output        output function              keeps old value
  --patterns      patterns -> handlers         keeps old value
  --fromIndex     beginning of the next token  ending of last token + 1
  --currentIndex  index of the next read char  fromIndex (using its new value)
  local function afterAction(newOutput, newPatterns, newFromIndex, newCurrentIndex)
    local oldFromIndex = fromIndex
    output    = newOutput or output
    patterns  = newPatterns or patterns
    fromIndex = newFromIndex or lastToIndex + 1
    currentIndex = newCurrentIndex or fromIndex
    --recalculate line number
    for i = oldFromIndex, fromIndex - 1 do
      local char = source:byte(i, i)
      if char == 13 then
        currentLine = currentLine + 1
        lastWasCarriageReturn = true
      elseif char == 10 and not lastWasCarriageReturn then
        currentLine = currentLine + 1
      else
        lastWasCarriageReturn = false
      end
    end
    --reset state
    lastAction = nil
    lastToIndex = nil
    initState()
  end
  --reads the source at the given position, proceeds to the next state and
  --changes the last valid action if applicable
  --returns true when current state is empty / invalid
  local function doChar(charIndex)
    lastDoneIndex = charIndex
    --take character
    local char = source:byte(charIndex, charIndex)
    --state change
    currentState = currentState[char]
    --check if we reached a dead end
    if currentState then
      --no: check if it is a valid state
      local action = currentState[""]
      if action then
        lastAction = action
        lastToIndex = charIndex
      end
      --continue reading
      return false
    else
      --yes: finished reading
      return true
    end
  end
  --runs the last valid action
  --uses its return values to prepare the next initial state
  local function runAction()
    if lastAction == nil then
      error(("No matching pattern found for: %q"):format(source:sub(fromIndex, lastDoneIndex):sub(1, 1000)), 0)
    end
    afterAction(lastAction(output, patterns, source, fromIndex, lastToIndex, currentLine))
  end
  --tries loading the next part of the source
  --is executed when the lexer reaches the ending of the known source
  local function tryLoader()
    --runs the loader
    local loaded = loader and loader()
    if loaded and #loaded > 0 then
      --appends the loader's value, while removing the part that has already been processed
      source = source:sub(fromIndex, -1) .. loaded
      --adjusting indices (due to the removed part)
      currentIndex = currentIndex - fromIndex + 1
      lastDoneIndex = lastDoneIndex - fromIndex + 1
      if lastToIndex then
        lastToIndex = lastToIndex - fromIndex + 1
      end
      fromIndex = 1
      return true
    end
    --remove loader after ending
    loader = nil
    return false
  end
  
  --go through the source until reaching the end
  while fromIndex <= #source or tryLoader() do
    --get maximum match with it's associated action
    while currentIndex <= #source or tryLoader() do
      if doChar(currentIndex) then
        break
      end
      currentIndex = currentIndex + 1
    end
    --run it's action or fail if there was no fitting action
    local ok, err = xpcall(runAction, onError)
    if not ok then
      return false, err
    end
  end
  --finish with executing an eof action
  --(required to be able to throw errors for unfinished strings)
  if lastAction == nil then
    return false, onError("Unexpected end of file! (no eof action)")
  end
  local ok, err = xpcall(runAction, onError)
  if not ok then
    return false, err
  end
  return true
end

--****FULL PARSING****--
--adds grammar rules for the given list of operators
--(from highest precedence to lowest precedence)
--Each rule's name consists of the prefix 'prefix' and a following number.
--
function parser.operators(grammar, operators, prefix, primitiveName)
  for levelIndex, level in ipairs(operators) do
    local associativity = level.associativity
    local rule = primitiveName
    local thisGroup = prefix .. levelIndex
    --create chained rules using a format like:
    --<this>=<previous>|<this> op <previous>
    for _, op in ipairs(level) do
      local part
      if associativity == "r" then
        part = primitiveName .. " " .. op .. " " .. thisGroup 
      elseif associativity == "l" then
        part = thisGroup .. " " .. op .. " " .. primitiveName
      elseif associativity == "ur" then
        part = op .. " " .. thisGroup
      elseif associativity == "ul" then
        part = thisGroup .. " " .. op
      else
        error("Unknown associativity '"..associativity.."'!")
      end
      rule = rule .. "|" .. part
    end
    primitiveName = thisGroup
    grammar[thisGroup] = rule
  end
  return primitiveName, grammar
end

--reassembles pattern trees in a human readable format
local debugFormatter = function(before, sep, after, ignoreLast)
  return function(t)
    local tmp = {}
    for i, v in ipairs(t) do
      if ignoreLast and not t[i+1] then
        break
      end
      tmp[i] = tostring(v)
    end
    return before..table.concat(tmp, sep)..after
  end
end

--loads an EBNF like string and returns its tree representation
--The syntax has a few differences to EBNF:
--1. Whitespace is counted as a concatenation operator. (You can use commas instead if you want to.)
--2. There is no explicit differentiation between terminals and non terminals.
--("word" and word both mean a terminal or a non terminal with type "word")
parser.loadRule = cache(function(source)
  local rule
  local currentAlternative
  local stack = {}
  --stores __tostring metamethods for debug output
  local nextMeta
  if parser.debug then
    nextMeta = {rule=debugFormatter("","|",""), alt = debugFormatter(""," ","")}
  end
  --adds a new alternative to the current subrule
  local function addAlternative()
    if parser.debug then
      currentAlternative = setmetatable({},{
        __tostring = getmetatable(rule).alt,
      })
    else
      currentAlternative = {}
    end
    rule[#rule + 1] = currentAlternative
  end
  --adds a token to the current alternative
  local function addToken(value)
    if rule then
      table.insert(currentAlternative, value)
    end
    return value
  end
  --adds a new subrule and pushes the closing symbol type on the stack
  local function push(typ)
    if parser.debug then
      rule = addToken(setmetatable({parent = rule},{
        __tostring = nextMeta.rule, alt = nextMeta.alt,
      }))
    else
      rule = addToken{parent = rule}
    end
    table.insert(stack, typ)
    addAlternative()
  end
  --moves to the parent rule
  --Throws an error if the given symbol type does not match the one on top of the stack.
  --(It is removed from the stack after checking.)
  --returns the subrule which was active before calling
  local function pop(typ)
    local top = table.remove(stack)
    assert(top == typ, "Expected '"..top.."' got '"..typ.."'!")
    local oldRule = rule
    rule = rule.parent
    if rule then
      currentAlternative = rule[#rule]
    end
    return oldRule
  end
  push("eof")
  
  local lexerRules = {
    --ignore whitespace
    ["%s+"] = function() end,
    --remove quotes and unescape quoted text
    ["\"([^\\\"]*(\\.)?)*\"|'([^\\']*(\\.)?)*'"] = function(output, patterns, source, from, to)
      addToken(source:sub(from + 1, to - 1):gsub("\\(.)", parser.unescape))
    end,
    --take text without modifications
    ["[^%[%]%{%}%|%'%\"%s]+"] = function(output, patterns, source, from, to)
      addToken(source:sub(from, to))
    end,
    --special characters
    ["%|"] = function()
      addAlternative()
    end,
    ["%["] = function()
      if parser.debug then
        nextMeta = {rule=debugFormatter("[","|","]", true),alt = debugFormatter(""," ","")}
      end
      push("]")
      if parser.debug then
        nextMeta = {rule=debugFormatter("","|",""),alt = debugFormatter(""," ","")}
      end
    end,
    ["%]"] = function()
      --add empty variant
      addAlternative()
      pop("]")
    end,
    ["%{"] = function()
      if parser.debug then
        nextMeta = {rule=debugFormatter("{","|","}", true),alt = debugFormatter(""," ","", true)}
      end
      push("}")
      if parser.debug then
        nextMeta = {rule=debugFormatter("","|",""),alt = debugFormatter(""," ","")}
      end
    end,
    ["%}"] = function()
      --modify variants to include this rule
      for i, variant in ipairs(rule) do
        variant[#variant + 1] = rule
      end
      --add empty variant to stop recursion
      addAlternative()
      pop("}")
    end,
    ["%("] = function()
      if parser.debug then
        nextMeta = {rule=debugFormatter("(","|",")"),alt = debugFormatter(""," ","")}
      end
      push(")")
      if parser.debug then
        nextMeta = {rule=debugFormatter("","|",""),alt = debugFormatter(""," ","")}
      end
    end,
    ["%)"] = function()
      pop(")")
    end,
    --ignored to remain somewhat compatible to unmodified EBNF
    --(I didn't like using the comma as the concatenation operator.)
    ["%,"] = function() end,
    --eof: accepted
    [""] = function(source, from)
      if from <= #source then 
        error(("Invalid char '%s'!"):format(source:sub(from, from)))
      end
    end,
  }
  --running the lexer... output function isn't needed because the complete parser is within the rules.
  parser.lexer(source, lexerRules)
  --return raw rule table
  return pop("eof")
end, "k", "parser.loadRule")

--creates a n-dimensional structure that reports
--that it received new entries via properties.changed == true
local function createBuildMap()
  local buildTable = {}
  local properties = {changed = true}
  local function onChange (t,k,v)
    properties.changed = true
    rawset(t,k,v)
  end
  local subMeta = {
    __newindex = onChange,
  }
  local topMeta = {
    __newindex = onChange,
    __index = function(t,k)
      t[k] = setmetatable({}, subMeta)
      return t[k]
    end,
  }    
  return setmetatable(buildTable, topMeta), properties
end



--key for LR0 states
local LR0 = {}

--creates and returns the parsing table for a given language
--language format (excerpts affecting LR table creation):
--name          function                                   default when nil
--grammar       non terminal -> EBNF code                  (required)
--eof           eof symbol                                 "eof"
--priorities    NT -> (NT -> boolean or nil) or nil        {empty table}
--              manually resolves reduce/reduce conflicts
--              needs a true value at either priorities[A][B]
--              or priorities[B][A] to resolve "A vs. B"
--              A wins if priorities[A][B]
--lrMode        how the table should be generated          "LR1"
--              value    what it does
--              "LR0"    simplest variant
--                       (does not use any kind of lookahead set)
--              "SLR1"   like "LR0" but a bit more powerful
--                       (generates lookahead set approximations when writing the table)
--              "LR1"    most powerful but biggest output tables
--                       (LR0 state + lookahead -> LR1 state)
--              "LALR1"  like "LR1" but a bit less powerful for greatly reduced output size
--                       (combines states which only differ in the lookahead set when writing)
parser.loadLanguage = function(language)
  local patternList = assert(language.grammar, "grammar required to build")
  local root --is created to allow more complex language roots
  local eof        = language.eof or "eof"
  local priorities = language.priorities or {}
  local lrMode     = language.lrMode or "LR1"
  assert(lrMode == "LR0" or lrMode == "SLR1" or lrMode == "LR1" or lrMode == "LALR1", "lrModes LR0, SLR1, LR1 and LALR1 are supported!")
  --the set of all non terminals
  local allTokens = {}
  local terminals = {}
  local nonTerminals = {}
  do
    --the set of all user defined non terminals
    local mainNonTerminals = {}
    --extracts all sub rules from the given loaded EBNF pattern
    local function loadSubNonTerminals(pattern)
      --extract sub rules (e.g. for repetitions via "{}")
      --that way every non terminal is known
      if nonTerminals[pattern] then --don't work through the same objects twice
        return
      end
      if type(pattern) ~= "table" then --terminal or the name of another main non terminal
        terminals[pattern] = pattern
        return
      end
      --add non terminal to set, don't add main terminals again though
      if not mainNonTerminals[pattern] then
        nonTerminals[pattern] = pattern
      end
      --add sub patterns
      for _, variant in ipairs(pattern) do
        for _, subPattern in ipairs(variant) do
          loadSubNonTerminals(subPattern)
        end
      end
    end
    --load all rules and extract their sub rules (repetition / optional entries)
    for key, pattern in pairs(patternList) do
      local nonTerminal = parser.loadRule[pattern]
      nonTerminals[key] = nonTerminal
      mainNonTerminals[nonTerminal] = key
      loadSubNonTerminals(nonTerminal)
    end
    --add hidden root rule
    root = {{language.root, eof}}
    nonTerminals[root] = root
    terminals[eof] = eof
    --finish lists
    for name, _ in pairs(nonTerminals) do
      terminals[name] = nil
      allTokens[name] = name
    end
    for name, _ in pairs(terminals) do
      allTokens[name] = name
    end
  end
  
  --it was originally implemented here, became a whole library
  local mergeInsert = sets.mergeInsert
  local manageSet = setset.manager("k", "manager")
  
  --*FIRST()*--
  local function buildFirst(obj, buildMap, touched)
    --avoid infinite recursion, shortcut for final objects
    if touched[obj] or not getmetatable(buildMap[obj]) then
      return buildMap[obj]
    end
    touched[obj] = true
    --get list of terminals (is persistent between build iterations to monitor changes)
    local terminals = buildMap[obj]
    --try every variant
    for key, variant in ipairs(obj) do
      local index = 1
      local candidate = variant[index]
      while candidate do
        local nonTerminal = nonTerminals[candidate]
        if nonTerminal then
          --non terminal: check it's first terminals, merge
          local subTerminals = buildFirst(nonTerminal, buildMap, touched)
          if subTerminals[""] then
            --contains empty word, add next (non)terminal before adding an empty word
            mergeInsert(terminals, subTerminals, "")
          else
            --no empty word: add words to outout, we're done here
            mergeInsert(terminals, subTerminals)
            break
          end
        else
          assert(type(candidate)~="table")
          --terminal: add it to the list, don't check next word
          terminals[candidate] = candidate
          break
        end
        index = index + 1
        candidate = variant[index]
      end
      if not candidate then
        terminals[""] = ""
      end
    end
    return terminals
  end
  local firstBuildMap, firstBuildProperties = createBuildMap()
  
  local first = cache(function(objectName)
    local nonTerminal = nonTerminals[objectName]
    if nonTerminal == nil then
      --terminal: returns self
      return manageSet{[objectName] = objectName}
    end
    
    repeat
      firstBuildProperties.changed = false
      --building...
      buildFirst(nonTerminal, firstBuildMap, {})
    until not firstBuildProperties.changed
    --it is now safe to remove the metatables for all built objects
    --That also increases speed.
    for _, terminals in pairs(firstBuildMap) do
      setmetatable(terminals, nil)
    end
    --return result
    return manageSet(firstBuildMap[nonTerminal])
  end, nil, "first")
  --used to implement first(prefix suffix) as mergeFirst(first(prefix), first(suffix))
  --that should be the fastest way
  local mergeFirst = cache(function(prefix)
    if prefix[""] then
      return cache(function(suffix)
        local outputSet = {}
        mergeInsert(outputSet, prefix, "")
        mergeInsert(outputSet, suffix)
        return manageSet(outputSet)
      end, nil, "mergeFirst.suffix1")
    else
      return cache(function()
        return prefix
      end, nil, "mergeFirst.suffix2")
    end
  end, nil, "mergeFirst.prefix")
  
  --*FOLLOW()*--
  local function buildFollow(thisName, buildMap, touched)
    --avoid infinite recursion, shortcut for final objects
    if touched[thisName] or not getmetatable(buildMap[thisName]) then
      return buildMap[thisName]
    end
    touched[thisName] = true
    
    --get list of terminals (is persistent between build iterations to monitor changes)
    local terminals = buildMap[thisName]
    --search for occurences
    for name, nonTerminal in pairs(nonTerminals) do
      for _, variant in ipairs(nonTerminal) do
        for i, token in ipairs(variant) do
          if token == thisName then
            --get the following token
            local nextToken = variant[i + 1]
            local containsEmptyWord = true
            if nextToken then
              --get the first terminal from the next token
              local nextFirst = first(nextToken)
              containsEmptyWord = (nextFirst[""] ~= nil)
              mergeInsert(terminals, nextFirst, "")
            end
            if containsEmptyWord then
              --some recursion in case there is no next token (or if it's empty)
              mergeInsert(terminals, buildFollow(name, buildMap, touched))
            end
          end
        end
      end
    end
    return terminals
  end
  
  local followBuildMap, followBuildProperties = createBuildMap()
  local follow = cache(function(objectName)
    assert(nonTerminals[objectName])
    repeat
      followBuildProperties.changed = false
      --building...
      buildFollow(objectName, followBuildMap, {})
    until not followBuildProperties.changed
    --it is now safe to remove the metatables for all built objects
    --That also increases speed.
    for _, terminals in pairs(followBuildMap) do
      setmetatable(terminals, nil)
    end
    --return result
    return manageSet(followBuildMap[objectName])
  end, nil, "follow")
  
  --*BUILD STATES*--
  --state[non terminal name][variantIndex][progress=0..#variant][lookahead] -> {variant, name = non terminal name, variantIndex = variantIndex, progress = progress, lookahead = lookahead}
  --'progress' indicates how many characters of this rule are already on the stack
  local states = {}
  for name, nonTerminal in pairs(nonTerminals) do
    local variants = {}
    states[name] = variants
    for variantIndex, variant in ipairs(nonTerminal) do
      local progressList = {}
      variants[variantIndex] = progressList
      for progress = 0, #variant do
        progressList[progress] = cache(function(lookahead)
          local state
          state = state or {
            variant = variant,
            name = name,
            variantIndex = variantIndex,
            progress = progress,
            lookahead = lookahead,
          }
          if lookahead ~= LR0 then
            state.LR0 = states[name][variantIndex][progress][LR0]
          end
          return state
        end, nil, "lookahead")
      end
    end
  end

  --The following functions receive a set of states and output a set of states.
  --The input sets should be filtered by manageSet to increase efficiency.
  --(The functions expect their input to be filtered by manageSet.)
  --*CLOSURE()*--
  local closureState = cache(function(state)
    local output = {[state] = state}
    local newOutput = {[state] = state}
    repeat
      local finished = true
      local oldNewOutput = newOutput
      newOutput = {}
      for _, newState in pairs(oldNewOutput) do
        finished = false
        --collect some data
        local variant = newState.variant
        local progress = newState.progress
        local nextToken = variant[progress + 1]
        local nextNonTerminal = nextToken and nonTerminals[nextToken]
        local lookahead = newState.lookahead
        --prepare new states
        if nextNonTerminal then
          ---calculate new lookahead
          local newLookahead
          if lookahead == LR0 then
            --LR(0) and SLR(1) don't have a lookahead table.
            newLookahead = LR0
          else
            newLookahead = first[""]
            for i = progress + 2, #variant do
              --applying first to the part following nextToken
              --(pre first) concatenation is replaced by a
              --(post first) merge operation to improve usage of caching
              --(A long sequence of tokens causes more misses than the combination of 2 first sets.)
              newLookahead = mergeFirst(newLookahead, first[variant[i]])
              if newLookahead[""] == nil then
                break
              end
            end
            --no need to apply firstOfSet to lookahead since it is a set of terminals
            newLookahead = mergeFirst(newLookahead, lookahead)
          end
          ---add new states
          for variantIndex, variant in ipairs(nextNonTerminal) do
            --add state[nextToken][variantIndex][0] if it is new
            local newNewState = states[nextToken][variantIndex][0][newLookahead]
            if not output[newNewState] then
              output[newNewState] = newNewState
              newOutput[newNewState] = newNewState
            end
          end
        end
      end
    until finished
    return output
  end, nil, "closureState")
  local closure = cache(function(stateSet)
    local newStates = {}
    for _, state in pairs(stateSet) do
      mergeInsert(newStates, closureState[state])
    end
    --clean/managed output
    return manageSet(newStates)
  end, nil, "closure")
  --*GOTO()*--
  --When we are at the current set of states and have finished the reading terminal or non terminal:
  --What's our next state?
  local getGoto = cache(function(nextToken)
    return cache(function(stateSet)
      local validNextStatesSet = {}
      for _, state in pairs(stateSet) do
        local variant = state.variant
        local name = state.name
        local variantIndex = state.variantIndex
        local progress = state.progress
        local lookahead = state.lookahead
        --take every unfinished state
        if nextToken == variant[progress + 1] then
          --then take its following state
          local nextState = states[name][variantIndex][progress + 1][lookahead]
          --and remember it
          validNextStatesSet[nextState] = nextState
        end
      end
      return closure(manageSet(validNextStatesSet))
    end, nil, "goto.stateSet")
  end, nil, "goto.nextToken")
  
  getKernel = cache(function(set)
    local kernelSet = {}
    for _, state in pairs(set) do
      local lr0State = state.LR0
      if lr0State == nil then
        --set already is LR0
        return set
      end
      kernelSet[lr0State] = lr0State
    end
    return manageSet(kernelSet)
  end, nil, "getKernel")
  
  
  --*STATE TRANSITIONS*--
  --[terminal/non terminal][stateIndex] -> action
  --action -> i >= 1 -> go to state i
  --action -> {reduce=0, 1, ..., push = "non terminal"} -> reduce by i, push non terminal on the stack
  local function createLRTable(originalStateSet)
    local errorLog = {}
    
    local visitedStateSets = {[originalStateSet] = originalStateSet}
    local newStatesSets = {[originalStateSet] = originalStateSet}
    --generates number symbols for non string symbols
    --> easier export
    local nSymbols = 0
    local primitiveSymbol = cache(function(symbol)
      if type(symbol) == "string" then
        return symbol
      else
        nSymbols = nSymbols + 1
        return nSymbols
      end
    end, nil, "lr.primitiveSymbol")
    
    --the output; creates tables for every possible non-/terminal
    local lrTable = {}
    for _, token in pairs(allTokens) do
      lrTable[primitiveSymbol[token]] = {}
    end
    
    --We don't need the complex states anymore.
    --Replace them by simple numbers.
    local lastIndex = 0
    local indices
    indices = cache(function(set)
      if lrMode == "LALR1" then
        --LALR1: states with same kernel are merged -> make index dependent on kernel and they are merged automaticly
        local kernel = getKernel(set)
        if kernel ~= set then
          return indices[kernel]
        end
      end
      lastIndex = lastIndex + 1
      return lastIndex
    end, nil, "lr.indices")
    
    --cached reduce tables
    local reduce = cache(function(amount)
      return cache(function(push)
        return setmetatable({reduce = amount, push = primitiveSymbol[push]},
        {__tostring=function()
          return "reduce "..tostring(amount).." -> "..tostring(push)
        end})
      end, nil, "lr.reduce.push")
    end, nil, "lr.reduce.amount")
    
    
    local function writeLRTable(symbol, stateIndex, action, state)
      symbol = primitiveSymbol[symbol]
      local previousAction = lrTable[symbol][stateIndex]
      if previousAction ~= nil and previousAction ~= action then
        --conflict
        if type(previousAction) == "table" and type(action) == "table" then
          --reduce/reduce conflict try manual resolution
          if priorities[previousAction.push] then
            if priorities[previousAction.push][action.push] then
              --previous action has priority, don't change
              return
            end
          end
          if priorities[action.push] then
            if priorities[action.push][previousAction.push] then
              --new action has priority, disable error by setting previousAction
              previousAction = action
            end
          end
        end
        --no resolution applied: error
        if previousAction ~= action then
          errorLog[#errorLog + 1] = "Tried to replace '".. tostring(previousAction) .. "' with '" .. tostring(action).."'!"
          errorLog[#errorLog + 1] = "current state: " .. tostring(state.name) .. " = " .. tostring(state.variant) .. " ["..state.progress.."/"..#state.variant.."]"
          errorLog[#errorLog + 1] = "symbol: " .. tostring(symbol) .. ",action: " .. tostring(action)
          return
        end
      end
      lrTable[symbol][stateIndex] = action
    end
    
    --generate states
    repeat
      local finished = true
      local oldNewStatesSets = newStatesSets
      newStatesSets = {}
      for _, stateSet in pairs(oldNewStatesSets) do
        finished = false
        --force index generation (initial state = 1)
        local stateIndex = indices[stateSet]
        for _, state in pairs(stateSet) do
          local variant   = state.variant
          local progress  = state.progress
          local nextToken = variant[progress + 1]
          if nextToken then
            --rule still in progress
            if nextToken ~= eof then
              --add connections to next states
              local gotoStates = getGoto[nextToken][stateSet]
              assert(next(gotoStates)~=nil)
              if not visitedStateSets[gotoStates] then
                visitedStateSets[gotoStates] = gotoStates
                newStatesSets[gotoStates]    = gotoStates
              end
            end
          end
        end
      end
    until finished
    --build table
    for _, stateSet in pairs(visitedStateSets) do
      local stateIndex = indices[stateSet]
      for _, state in pairs(stateSet) do
        local name      = state.name
        local variant   = state.variant
        local progress  = state.progress
        local lookahead = state.lookahead
        local nextToken = variant[progress + 1]
        if nextToken then
          --rule still in progress
          if nextToken == eof then
            --The input is in a valid state: eof would be accepted now.
            writeLRTable(eof, stateIndex, "accepted", state)
          else
            --add connections to next states
            local gotoStates = getGoto[nextToken][stateSet]
            writeLRTable(nextToken, stateIndex, indices[gotoStates], state)
          end
        else
          --rule finished, add 'reduce' step
          if lookahead == LR0 then
            if lrMode == "LR0" then
              --LR(0): too simple, SLR1 is better in most cases
              for _, terminal in pairs(terminals) do
                writeLRTable(terminal, stateIndex, reduce[progress][name], state)
              end
            elseif lrMode == "SLR1" then
              --SLR(1): very simple, but effective...
              for _, terminal in pairs(follow(name)) do
                writeLRTable(terminal, stateIndex, reduce[progress][name], state)
              end
            end
          else
            --canonical LR(1) / LALR(1): not as simple but a lot more powerful
            for _, terminal in pairs(lookahead) do
              writeLRTable(terminal, stateIndex, reduce[progress][name], state)
            end
          end
        end
      end
    end
    if #errorLog > 0 then
      error(table.concat(errorLog, "\n"), 0)
    end
    return lrTable
  end
  --get initial lookahead set or use LR0 if no lookahead set is used
  local initialLookahead = (lrMode == "LR1" or lrMode == "LALR1") and manageSet{eof} or LR0
  --create LR parsing table (lrTable[symbol][state] = action table or state number)
  local lrTable = createLRTable(closure(manageSet{states[root][1][0][initialLookahead]}))
  --and return
  return lrTable
end

--saves the parsing table to the given file
--"dofile(file)" would load the table again.
function parser.saveLRTable(lrTable, file)
  --use usage counter for compression
  local usageCount = {}
  for symbol, states in pairs(lrTable) do
    usageCount[symbol] = (usageCount[symbol] or 0) + 1
    for stateNumber, action in pairs(states) do
      if usageCount[action] == nil and type(action) == "table" then
        local pushedSymbol = action.push
        usageCount[pushedSymbol] = (usageCount[pushedSymbol] or 0) + 1
      end
      usageCount[action] = (usageCount[action] or 0) + 1
    end
  end
  --contains content -> identifier association
  local map  = {}
  --a list of strings that are defined in the string array
  local strings = {n = 0}
  --a list of actions that are defined in the action array
  local actions = {n = 0}
  --create string mapping
  for obj, count in pairs(usageCount) do
    if type(obj) == "string" then
      local mapped = ("%q"):format(obj)
      if (count) * (3+#tostring(strings.n + 1)) + #mapped + 1 < count * #mapped then
        local n = strings.n + 1
        strings.n = n
        strings[n] = mapped
        map[obj] = ("s[%u]"):format(n)
      else
        map[obj] = mapped
      end
    elseif type(obj) == "number" then
      map[obj] = ("%u"):format(obj)
    end
  end
  --create action mappings
  for obj, count in pairs(usageCount) do
    if type(obj) == "table" then
      local mapped = ("{reduce=%u,push=%s}"):format(obj.reduce, map[obj.push])
      if count > 1 then
        local n = actions.n + 1
        actions.n = n
        actions[n] = mapped
        map[obj] = ("t[%u]"):format(n)
      else
        map[obj] = mapped
      end
    end
  end
  --open output file
  local stream = io.open(file, "w")
  --write string array
  stream:write("local s={")
  for _,string in ipairs(strings) do
    stream:write(string)
    stream:write(",")
  end
  --write table array
  stream:write("}\nlocal t={")
  for _,action in ipairs(actions) do
    stream:write(action)
    stream:write(",")
  end
  --write LR table
  stream:write("}\nreturn{")
  for symbol, states in pairs(lrTable) do
    --define symbol table
    stream:write(("[%s]={"):format(map[symbol]))
    for stateNumber, action in pairs(states) do
      --define action for (symbol, state) pair
      stream:write(("[%u]=%s,"):format(stateNumber, map[action]))
    end
    stream:write("},\n")
  end
  stream:write("}")
  --close file
  stream:close()
end

--prints contents of a parsing table for debugging
function parser.printLRTable(lrTable, showContent)
  local state = 0
  local nActions = 0
  --iterates states (displayed as rows)
  repeat
    local finished = true
    local line = {}
    --iterate symbols (displayed as columns)
    for name, _ in pairs(lrTable) do
      --use symbol names for table header
      local value = state==0 and name or lrTable[name][state]
      if value then
        nActions = nActions + 1
        finished = false
      else
        value = ""
      end
      value = tostring(value)
      table.insert(line, (" "):rep(20-#value) .. value:sub(-20,-1))
    end
    if showContent ~= false then
      --print state number and table row
      print(finished and "" or state, table.concat(line))
    end
    state = state + 1
  until finished
  local nTokens = 0
  for _,_ in pairs(lrTable) do
    nTokens = nTokens + 1
  end
  --print statistics
  print(state - 1, "states")
  print(nTokens, "non-/terminals")
  print(nActions, "actions")  
end

--prints out a syntax tree
function parser.printTree(tree, indent)
  indent = indent or ""
  print(indent .. tostring(tree.typ))
  for i, v in ipairs(tree) do
    if type(v) == "table" then
      --recursion, adds indentation
      parser.printTree(v, indent .. "  ")
    else
      print(indent .. "  "..tostring(v))
    end
  end
end

--takes a loader (as in parser.lexer) and a language, returns a syntax tree
--language format (excerpts affecting LR table creation):
--name          function                                    default when nil
--ignored[]     (non-)terminal -> true to ignore            {empty table}
--onToken()     type, source, from, to, extracted -> token  function returning {typ=type, extracted or source:sub(from, to)}
--onReduce()    stack, type, source, from, to, extracted    noop function
--lrTable[]     nextToken.typ, state -> action              parser.loadLanguage(language)
--lexer[]       pattern -> onMatch                          (required)
--              (like 'patterns' in parser.lexer)
function parser.parse(loader, language)
  ---language config
  --get set of ignored token types (->treated as whitespace)
  local ignored   = language.ignored   or {}
  --get the function that is called whenever a token is processed
  --It has to return a table with a "typ" field or a string
  local onToken   = language.onToken   or
    function(typ, source, from, to, extracted)
      return {typ = typ, extracted or source:sub(from, to)}
    end
  --get the function that is called whenever
  --an ignored / whitespace token is processed
  local onIgnored = language.onIgnored or function() end
  --get the function that is called when a rule is applied
  local onReduce  = language.onReduce  or
    function(pushedSymbol, oldSymbols)
      oldSymbols.typ = pushedSymbol
      return oldSymbols
    end
  local lrTable   = language.lrTable   or parser.loadLanguage(language)
  --throw an error when reading tokens after the eof token
  local finished = false
  --prepare stack
  local stack = {1}
  local function top()
    return stack[#stack]
  end
  local function push(obj)
    stack[#stack + 1] = obj
  end
  local function pop(n)
    --pops 2*n states, returns a list of removed tokens
    local oldSymbols = {}
    for i = #stack - n * 2 + 1, #stack - 1, 2 do
      oldSymbols[#oldSymbols + 1] = stack[i]
      stack[i] = nil
      stack[i + 1] = nil
    end
    return oldSymbols
  end
  
  --basic LR parser operations
  local function shift(nextToken, action)
    --change state
    push(nextToken)
    push(action)
  end
  local function reduce(n, pushedSymbol)
    --combines n tokens to one new token
    local oldSymbols = pop(n)
    local state = top()
    push(onReduce(pushedSymbol, oldSymbols) or pushedSymbol)
    push(lrTable[pushedSymbol][state])
  end
  local function readToken(token)
    local nextTyp = type(token) == "string" and token or token.typ
    while true do
      local state = stack[#stack]
      local action = lrTable[nextTyp][state]
      if type(action) == "number" then
        --shift
        shift(token, action)
        return
      elseif type(action) == "table" then
        --reduce
        reduce(action.reduce, action.push)
      elseif action == "accepted" then
        finished = true
        return
      else
        ---no rule found: get error information
        --expected tokens
        local expected = {}
        for k,v in pairs(lrTable) do
          if v[state] then
            expected[#expected + 1] = "'"..k.."'"
          end
        end
        if #expected == 1 then
          expected = expected[1]
        elseif #expected > 1 then
          expected = "one of: " .. table.concat(expected, " ")
        else
          expected = "nothing (already in final state)"
        end
        --received token
        local errorToken = (token ~= nextTyp and token[1] and nextTyp ~= token[1]) and (nextTyp .. " '"..token[1].."'") or nextTyp
        --throw error
        error(("Syntax error: got %s, expected %s"):format(errorToken, expected), 0)
      end
    end
  end
  local function lexerOutput(typ, ...)
    if finished then
      error("Got token after eof token!", 0)
    end
    if not ignored[typ] then
      --create an object {typ = typ, ... (other data)}
      local token = onToken(typ, ...)
      if token then
        --apply rules until next shift command
        return readToken(token)
      end
    end
    return onIgnored and onIgnored(stack[#stack - 1], typ, ...)
  end
  
  local ok, err = parser.lexer(loader, language.lexer, lexerOutput)
  if not ok then
    return false, err
  end
  --finish parsing by reading <eof> token
  ok, err = xpcall(
    readToken,
    function(err)
      return {
        error = err,
        line  = "eof",
        traceback = debug.traceback(err, 2),
      }
    end,
    {typ = language.eof or "eof"}
  )
  if not ok then
    return false, err
  end
  if stack[2].typ ~= language.root then
    return false, {
      error = "Stack is not empty!",
      line = "eof",
      traceback = debug.traceback("Stack is not empty!"),
    }
  end
  return stack[2]
end

return parser
