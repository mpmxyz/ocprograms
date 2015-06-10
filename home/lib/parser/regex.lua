-----------------------------------------------------
--name       : lib/parser/regex.lua
--description: regular expression library
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local cache = require("mpm.cache").wrap
local merge = require("parser.automaton").merge

local regex = {}

--I was too lazy to write my own character classes. So: Why not using the built-in ones?
--match[single char pattern][single char string] -> isMatching
local match = cache(function(pattern)
  return cache(function(char)
    return string.find(string.char(char), pattern) ~= nil
  end, nil, "regex.single character matching 2")
end, nil, "regex.single character matching 1")

--summarizing the differences between the operations you can use to e.g. add repetitions.
local opProperties = {
  [""] = {
    loop = false,
    optional = false,
  },
  ["?"] = {
    loop = false,
    optional = true,
  },
  ["+"] = {
    loop = true,
    optional = false,
  },
  ["*"] = {
    loop = true,
    optional = true,
  },
}
--"-" currently does the same as "*". (would change when implementing captures)
opProperties["-"] = opProperties["*"]


--pattern -> state table
--caching might take a lot of space but it should increase the speed a lot...
--here is a list on how the regular expressions are defined:
--1. Each character stands for itself as long as it isn't used by another rule.
--2. "%" is used as an escape character as it is used in Lua patterns.
--3. "[]"s and "." work as in Lua patterns to define single character sets.
--4. "*", "-", "?" and "+" work as in Lua patterns
--This 4 rules should more or less just descibe aspects of Lua patterns.
--The following rules describe some differences:
--5. "()"s can be used to group parts of the pattern (No capturing at the moment.)
--6. When "*", "-", "?" or "+" follow a group, they are applied to the whole group and not just to the last character.
--7. "|" is used to separate multi character alternatives within a group.
regex.compile = cache(function(pattern)
  if pattern == "" then
    local finalState = cache(function(key)
      --[""] = true marks this as the final and valid state
      --the index "" can only be true or false; it never contains a new state
      --every other index can only be false or a table
      --(nil stands for 'not yet initialized')
      return key == ""
    end, nil, "regex.final state")
    return finalState
  end
  ---init pattern parser
  --top level of the parsing tree
  local tokens = {}
  --current level of the parsing tree
  local currentTokens = tokens
  --how many levels deep are we? (needs to be 0 at end of string
  local level = 0
  --beginning of the currently extracted token
  local firstChar = 1
  --read the next character without interpretation when true
  local escaped = false
  local function dontAdd(i)
    --don't add this character to the tokens
    firstChar = i + 1
  end
  --adds a quantifier to the last group
  local function quantifier(char)
    return function(i)
      local lastToken = currentTokens[#currentTokens]
      assert(lastToken ~= nil, "Invalid syntax near '"..char.."'!")
      if type(lastToken) == "string" then
        lastToken = {lastToken}
        currentTokens[#currentTokens] = lastToken
      end
      assert(lastToken.op == nil, "Invalid syntax near '"..char.."'!")
      lastToken.op = char
      dontAdd(i)
    end
  end
  --define two parsing tables
  local state_chargroup
  local state_initial = {
    ["%"] = function(i)
      escaped = true
    end,
    ["("] = function(i)
      local parent = currentTokens
      currentTokens = {parent = parent}
      parent[#parent + 1] = currentTokens
      dontAdd(i)
    end,
    [")"] = function(i)
      --end of group
      currentTokens = currentTokens.parent
      assert(currentTokens, "')' without matching '('!")
      dontAdd(i)
    end,
    ["["] = function(i)
      return state_chargroup
    end,
    ["|"] = function(i)
      local newgroup = {parent = currentTokens.parent}
      currentTokens.alternate = newgroup
      currentTokens = newgroup
      dontAdd(i)
    end,
    ["+"] = quantifier("+"),
    ["-"] = quantifier("-"),
    ["*"] = quantifier("*"),
    ["?"] = quantifier("?"),
    default = function(i)
      currentTokens[#currentTokens + 1] = pattern:sub(firstChar, i)
      firstChar = i + 1
      escaped = false
    end,
  }
  state_chargroup = {
    ["%"] = state_initial["%"],
    ["]"] = function(i)
      currentTokens[#currentTokens + 1] = pattern:sub(firstChar, i)
      firstChar = i + 1
      return state_initial
    end,
    default = function()
      escaped = false
    end,
  }
  
  --parsing: iterate through all characters
  local state = state_initial
  for i = 1, #pattern do
    state = ((not escaped) and state[pattern:sub(i,i)] or state.default)(i) or state
  end
  --error checking
  if escaped then
    error("'%' escape without following character!")
  elseif currentTokens.parent ~= nil then
    error("Missing ')'!")
  elseif state == state_chargroup then
    error("Missing ']'!")
  elseif firstChar < #pattern + 1 then
    error("?".. firstChar.. #pattern)
  end
  
  --compiles a token tree to the initial state of an automaton
  --'nextState' points to the state that should follow the compiled states
  local function compile(tokens, nextState)
    assert(tokens,"tokens")
    assert(nextState,"nextState")
    if type(tokens) == "table" then
      --composite part
      local firstStates = {}
      local lastAdders  = {}
      
      local op = tokens.op or ""
      local opProperty = opProperties[op]
      
      --iterate alternatives
      while tokens ~= nil do
        --initialize nextState
        local stateAfterToken = nextState
        --iterate tokens of alternative
        local firstState, lastAddNext
        for i = #tokens, 1, -1 do
          local token = tokens[i]
          local firstSubState, lastSubAddNext = compile(token, stateAfterToken)
          firstState  = firstSubState or firstState
          lastAddNext = lastAddNext or lastSubAddNext
          --prepare stateAfterToken for the previous token
          stateAfterToken  = firstSubState or stateAfterToken
        end
        firstStates[#firstStates + 1] = firstState
        lastAdders [#lastAdders  + 1] = lastAddNext
        tokens = tokens.alternate
      end
      --no content: ignored
      --TODO: make it match empty word instead?
      if #firstStates == 0 then
        return nil, nil
      end
      
      ---combine variants to form one deterministic automaton
      --merge beginning
      local mergedFirstState = firstStates[1]
      for i = 2, #firstStates do
        mergedFirstState = merge[mergedFirstState][firstStates[i]]
      end
      --add function to add connections after ending
      local function addNext(new)
        for i = 1, #lastAdders do
          lastAdders[i](new)
        end
      end
      --add operator dependent connections
      if opProperty.loop then
        --loop: add connection to the beginning
        --Notice that the 'merge' is hidden in addNext function!
        --That avoids - among other things - differentiating character states and combined states.
        addNext(mergedFirstState)
      end
      if opProperty.optional then
        --optional: add connection to skip all states
        mergedFirstState = merge[mergedFirstState][nextState]
      end
      return mergedFirstState, addNext
    else--type(tokens) == "string"
      --primitive part: matching exactly one character
      local charNextState = nextState
      local charState = cache(function(char)
        if match[tokens][char] then
          return charNextState
        else
          return false
        end
      end, nil, "regex.state")
      --does not match empty word
      charState[""] = false
      if regex.debug then
        --add debug info
        getmetatable(charState).__tostring = function()
          return tokens
        end
      end
      --adds a new state to the set of following states
      local function addNext(new)
        charNextState = merge[charNextState][new]
      end
      return charState, addNext
    end
  end
  
  --return output
  return compile(tokens, regex.compile[""]) or regex.compile[""]
end, "v", "regex.compile")

--basic pattern matching (mainly used by the other methods)
--tries to find the longest match that is starting from index init
--returns the beginning and ending of the longest match or nil if none is found
function regex.findHere(s, pattern, init)
  --get initial state
  local state = regex.compile[pattern]
  local lastMatch
  init = init or 1
  if state[""] then
    --already matching empty string
    lastMatch = init - 1
  end
  --iterate characters
  for i = init, #s do
    local char = s:byte(i,i)
    --check this character
    state = state[char]
    if state then
      if state[""] then
        --remember final state
        lastMatch = i
      end
    else
      break
    end
  end
  if lastMatch then
    return init, lastMatch
  end
end

--extracts anchors from the given pattern
--returning:
--1. the pattern without anchors
--2. true if the pattern is anchored at the beginning
--3. true if the pattern is anchored at the ending
local function getAnchor(pattern)
  local from, to = 1, #pattern
  local frontAnchor = (pattern:sub(1,1) == "^")
  local aftAnchor   = (pattern:sub(to,to) == "$")
  if frontAnchor then
    from = from + 1
  end
  if aftAnchor then
    to = to - 1
  end
  return pattern:sub(from, to), frontAnchor, aftAnchor
end

--works like string.find but with regex patterns
--(currently not supporting captures)
function regex.find(s, pattern, init)
  local frontAnchor, aftAnchor
  pattern, frontAnchor, aftAnchor = getAnchor(pattern)
  local from, to = init or 1, frontAnchor and 1 or #s
  --TODO: is there an easy way to add captures?
  for i = from, to do
    local from, to = regex.findHere(s, pattern, i)
    if from and (not aftAnchor or to == #s) then
      return from, to
    end
  end
end

--works like string.match but with regex patterns
--(currently not supporting captures)
function regex.match(s, pattern, init)
  local from, to = regex.find(s, pattern, init)
  if from then
    return s:sub(from, to)
  end
end

--works like string.gmatch but with regex patterns
--(currently not supporting captures)
function regex.gmatch(s, pattern)
  local init = 1
  return function()
    local from, to = regex.find(s, pattern, init)
    if from then
      init = to + 1
      return s:sub(from, to)
    end
  end
end

--works like string.gsub but with regex patterns
--(currently only plain string substition)
function regex.gsub(s, pattern, replacement)
  local init = 1
  local output = {}
  while init <= #s do
    local from, to = regex.find(s, pattern, init)
    if from == nil then
      from = #s + 1
      to = #s
    end
    if from > init then
      output[#output + 1] = s:sub(init, from - 1)
    end
    if from <= to then
      --TODO: replacement table/function
      output[#output + 1] = replacement--s:sub(from, to)
    end
    init = to + 1
  end
  return table.concat(output)
end

return regex
