-----------------------------------------------------
--name       : lib/parser/lua.lua
--description: parsing configuration for lua code
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--requires parser.main for simple operator definitions
local parser = require 'parser.main'
--try loading a precalculated LR parsing table
local lrTableLoaded, lrTable = pcall(require, "parser.lualr")

local luaparser = {}
if lrTableLoaded and lrTable then
  luaparser.lrTable = lrTable
end

--helper to add inverse mapping
local function getInvertable(original)
  local copy = {}
  for k,v in pairs(original) do
    copy[k] = v
    copy[v] = k
  end
  return copy
end


--****PREPARATION****--
--a collection of all lua keywords
luaparser.keywords = getInvertable{
  "and", "break", "do", "else", "elseif", "end",
  "false", "for", "function", "goto", "if", "in",
  "local", "nil", "not", "or", "repeat", "return",
  "then", "true", "until", "while",
}
--a collection of all lua symbols
luaparser.symbols = getInvertable{
  "+", "-", "*", "/", "%", "^", "#",
  "==", "~=", "<=", ">=", "<", ">", "=",
  "(", ")", "{", "}", "[", "]",
  ";", ":", ",", ".", "..", "...",
}

--just a collection of general patterns
luaparser.patterns = {
  number = "(%d+%.%d*|%.%d+|%d+)([eE][%+%-]?%d+)?|0x(%x+%.%x*|%.%x+|%x+)([pP][%+%-]?%x+)?",
  --whitespace + newline
  whitespace = "%s+",
  --names
  name = "[%a_][%w_]*",
  --labels
  label = "%:%:[%a_][%w_]*%:%:",
  --keyword (not used for lexer because it would introduce ambiguities with the more general 'name')
  keyword = table.concat(luaparser.keywords, "|"),
  --symbol
  symbol = table.concat(luaparser.symbols, "|"):gsub("([^%|])","%%%1"),
  --quotes
  shortquote = "\"([^\\\"]*(\\.)?)*\"|'([^\\']*(\\.)?)*'",
  longquote = {
    open    = "%[%=*%[",
    content = "[^%]]+|%]",
    close   = "%]%=*%]",
  },
  --comments
  comment = {
    open  = "%-%-",
    --1st: starting with [=====, 2nd: not starting with [, 3rd: empty
    short = "(%[%=*([^%[%=\r\n][^\r\n]*)?|[^%[\r\n][^\r\n]*)?",
  },
}
--****LEXER****--
luaparser.lexer = {
  [luaparser.patterns.number]     = "number",
  [luaparser.patterns.whitespace] = "whitespace",
  [luaparser.patterns.name]       = function(output, patterns, source, from, to, currentLine)
    local name = source:sub(from, to)
    if luaparser.keywords[name] then
      output("keyword", source, from, to, currentLine, name)
    else
      output("name"   , source, from, to, currentLine, name)
    end
  end,
  [luaparser.patterns.symbol]     = "symbol",
  [luaparser.patterns.shortquote] = "string",
  [luaparser.patterns.longquote.open] = function(output, oldPatterns, source, from, to, currentLine)
    local endingLength = to - from + 1
    local contentLength = 0
    local newPatterns = {
      [luaparser.patterns.longquote.content] = function(output, patterns, source, from, to, currentLine)
        --ignore content for a while...
        contentLength = to - from + 1 - endingLength
        return output, patterns, from, to + 1
      end,
      [luaparser.patterns.longquote.close] = function(output, patterns, source, from, to, currentLine)
        if to - from + 1 == 2 * endingLength + contentLength then
          --found matching ending
          output("string", source, from, to, currentLine)
          --restoring original patterns
          return output, oldPatterns, to + 1, to + 1
        else
          --ignore all characters except the last...
          --It could be used as the beginning of the closing brackets.
          contentLength = to - from - endingLength
          return output, patterns, from, to
        end
      end,
      [""] = function(output, patterns, source, from, to, currentLine)
        error("Unfinished long string!", 0)
      end,
    }
    return output, newPatterns, from, to + 1
  end,
  [luaparser.patterns.comment.open]   = function(output, oldPatterns, source, from, to, currentLine)
    local newPatterns = {
      [luaparser.patterns.longquote.open] = function(output, patterns, source, from, to, currentLine)
        local endingLength = to - from - 1 --to - from + 1 - #('--')
        local contentLength = 0
        local newPatterns = {
          [luaparser.patterns.longquote.content] = function(output, patterns, source, from, to, currentLine)
            --ignore content for a while...
            contentLength = to - from - 1 - endingLength
            return output, patterns, from, to + 1
          end,
          [luaparser.patterns.longquote.close] = function(output, patterns, source, from, to, currentLine)
            if to - from + 1 == 2 + 2 * endingLength + contentLength then
              --found matching ending
              output("comment", source, from, to, currentLine)
              --restoring original patterns
              return output, oldPatterns, to + 1, to + 1
            else
              --ignore content for a while...
              contentLength = to - from - 1 - endingLength
              return output, patterns, from, to + 1
            end
          end,
          [""] = function(output, patterns, source, from, to, currentLine)
            error("Unfinished long comment!", 0)
          end,
        }
        return output, newPatterns, from, to + 1
      end,
      [luaparser.patterns.comment.short] = function(output, patterns, source, from, to, currentLine)
        --found single line comment
        output("comment", source, from, to, currentLine)
        --restoring original patterns
        return output, oldPatterns, to + 1, to + 1
      end,
    }
    return output, newPatterns, from, to + 1
  end,
  --accepted when end of file
  [""] = function(output, patterns, source, from, to, currentLine)
    if from <= #source then
      error(("No matching pattern found for: %q"):format(source:sub(from, from + 999)), 0)
    end
  end,
}
--generate actions for simple rules (match -> output without changes)
for pattern, action in pairs(luaparser.lexer) do
  if type(action) == "string" then
    luaparser.lexer[pattern] = function(output, patterns, source, from, to, currentLine)
      output(action, source, from, to, currentLine)
    end
  end
end

--****FULL PARSER****--
luaparser.lrMode = "LALR1"
luaparser.root = "chunk"
luaparser.eof  = "eof"

luaparser.grammar = {
  chunk = [[block]],
  --the beginning of a block is safe; this safe state is looped (stat3 at ending)
  --an unsafe transition before 'return' is possible
  block = [[
    [block_safe|block_unsafe|block_resistant] [retstat]
  ]],
  block_safe = [[
    stat3 [block_safe|block_resistant|block_unsafe]
  ]],
  block_resistant = [[
    stat2 [block_safe|block_resistant]
  ]],
  block_unsafe = [[
    stat1 [block_safe]
  ]],
  --beginning is problematic prefix expression + ending with expression
  stat1 = [[
     varlist_a '=' explist | 
     call_a
  ]],
  --ending with expression; causes trouble when stat1 is next
  stat2 = [[
     varlist_b '=' explist | 
     call_b | 
     local namelist '=' explist |
     repeat block until exp
  ]],
  --beginning/ending without expression; no danger at all
  stat3 = [[';' | 
     label | 
     break | 
     goto name | 
     do block end | 
     while exp do block end | 
     if exp then block {elseif exp then block} [else block] end | 
     for name '=' exp ',' exp [',' exp] do block end | 
     for namelist in explist do block end | 
     function funcname funcbody | 
     local function name funcbody | 
     local namelist
  ]],
  retstat = [[return [explist] [';'] ]],
  funcname = [[name {'.' name} [':' name] ]],
  varlist = [[var {',' var} ]],
  varlist_a = [[var_a {',' var} ]],
  varlist_b = [[var_b {',' var} ]],
  var = [[name | prefixexp '[' exp ']' | prefixexp '.' name ]],
  var_a = [[prefixexp_a '[' exp ']' | prefixexp_a '.' name ]],
  var_b = [[name | prefixexp_b '[' exp ']' | prefixexp_b '.' name ]],
  namelist = [[name | name ',' namelist ]],
  explist = [[exp {',' exp} ]],
  prefixexp = [[var | call | '(' exp ')' ]],
  prefixexp_a = [[var_a | call_a | '(' exp ')' ]],
  prefixexp_b = [[var_b | call_b ]],
  call = [[prefixexp args | prefixexp ':' name args ]],
  call_a = [[prefixexp_a args | prefixexp_a ':' name args ]],
  call_b = [[prefixexp_b args | prefixexp_b ':' name args ]],
  args = [['(' [explist] ')' | tableconstructor | string  ]],
  functiondef = [[function funcbody ]],
  funcbody = [['(' parlist ')' block end ]],
  parlist = [[ name ',' parlist | name | '...' | ]],
  tableconstructor = [['{' fieldlist '}' ]],
  fieldlist = [[field fieldsep fieldlist | field |]],
  field = [['[' exp ']' '=' exp | name '=' exp | exp ]],
  fieldsep = [[',' | ';' ]],
  value = [[nil | false | true | number | string | '...' | functiondef | prefixexp | tableconstructor]],
}

local operators = {
  {associativity = "r", "^"},
  {associativity = "ur", "not", "#", "-"},
  {associativity = "l", "*", "/", "%"},
  {associativity = "l", "+", "-"},
  {associativity = "r", ".."},
  {associativity = "l", "<", ">", "<=", ">=", "~=", "=="},
  {associativity = "l", "and"},
  {associativity = "l", "or"},
}
luaparser.grammar.exp = parser.operators(luaparser.grammar, operators, "op", "value")

--*onToken() callback*--

--extractors create token objects
luaparser.extractors = {
  string = function(typ, source, from, to, line)
    local prefix = source:sub(from,from)
    if prefix == "[" then
      prefix = source:match("%[%=*%[", from)
    end
    return {typ = "string", prefix, source:sub(from + #prefix, to - #prefix), source:sub(to - #prefix + 1, to)}, line
  end,
  keyword = function(typ, source, from, to, line, extractedToken)
    local token = extractedToken or source:sub(from, to)
    return token, line --simplified token + line
  end,
  symbol = function(typ, source, from, to, line, extractedToken)
    local token = extractedToken or source:sub(from, to)
    return token, line --simplified token + line
  end,
  default = function(typ, source, from, to, line, extractedToken)
    return {typ = typ, extractedToken or source:sub(from, to)}, line
  end,
}
--comments and whitespace are ignored
luaparser.ignored = {
  comment = true,
  whitespace = true,
}
  

luaparser.onToken = function(typ, ...)
  return (luaparser.extractors[typ] or luaparser.extractors.default)(typ, ...)
end

--*onIgnored() callback*--
--onIgnored is called when the parser couldn't create a token for the given data
--(i.e. to add comments to the source tree if you are creating a 'code beautifier')
--function luaparser.onIgnored(lastToken, typ, source, from, to, extractedToken)
luaparser.onIgnored = nil

--*onReduce() callback*--
--general renaming for better structure
local ruleToTokenNames = setmetatable({}, {
  __index = function(t, k)
    if type(k) == "number" then
      t[k] = "subrule"
      return "subrule"
    elseif type(k) == "string" then
      --take names from grammar defined rules
      t[k] = k
      return k
    else
      error("Expected a string / number type!")
    end
  end,
})

--renaming definitions
for i = 1, #operators do
  ruleToTokenNames["op"..tostring(i)] = "op"
end
ruleToTokenNames.stat1 = "stat"
ruleToTokenNames.stat2 = "stat"
ruleToTokenNames.stat3 = "stat"
ruleToTokenNames.block_safe = "subrule"
ruleToTokenNames.block_resistant = "subrule"
ruleToTokenNames.block_unsafe = "subrule"
ruleToTokenNames.varlist_a = "varlist"
ruleToTokenNames.varlist_b = "varlist"
ruleToTokenNames.var_a = "var"
ruleToTokenNames.var_b = "var"
ruleToTokenNames.prefixexp_a = "prefixexp"
ruleToTokenNames.prefixexp_b = "prefixexp"
ruleToTokenNames.call_a = "call"
ruleToTokenNames.call_b = "call"
  
--These lists have a recursive definition.
--This recursion is transformed to a single list of the same type.
local recursiveLists = {
  block     = true,
  namelist  = true,
  parlist   = true,
  fieldlist = true,
}
--These token types are only there to make writing the grammar easier.
--They are replaced by their content. (removing the indirection)
local transparentLists = {
  subrule = true,
  value = true,
  fieldsep = true,
}

local function isPasted(typ, content, recursive)
  if transparentLists[typ] then
    return true
  elseif recursive and recursiveLists[typ] then
    return true
  elseif typ == "op" then
    --special case: operations that just forward to the next level
    --They are replaced by their content.
    local nNonIgnored = 0
    for _, subObj in ipairs(content) do
      if not luaparser.ignored[subObj.typ] then
        nNonIgnored = nNonIgnored + 1
      end
      if nNonIgnored >= 2 then
        break
      end
    end
    return (nNonIgnored < 2)
  end
  return false
end

local function copyObject(target, source)
  for i = 1, #source do
    target[i] = source[i]
  end
end
local function rebuildTree(target, source, targetIndex)
  for _, obj in ipairs(source) do
    if isPasted(obj.typ, obj, target.typ == obj.typ) then
      --pasting is done implicitly by using a sub object as a source
      targetIndex = rebuildTree(target, obj, targetIndex)
    else
      local objTarget
      if recursiveLists[obj.typ] then
        --The whole tree structure that had the possibility to be pasted has to be traversed.
        --This part isn't pasted but might be a paste target. For simplicity a new table is created as a target.
        objTarget = {typ = obj.typ}
        rebuildTree(objTarget, obj, 1)
      else
        --This part isn't pasted and can't be a paste target. It is just referenced directly.
        objTarget = obj
      end
      target[targetIndex] = objTarget
      targetIndex = targetIndex + 1
    end
  end
  return targetIndex
end


--is called for every reduce step
--a return value of 'nil' pushes the ruleName instead
function luaparser.onReduce(ruleName, subTokens)
  --simplifies naming a bit
  ruleName = ruleToTokenNames[ruleName]
  local newToken = {typ = ruleName}
  --couldBePasted == true -> delay pasting until couldBePasted == false
  local parentIsPasted    = isPasted(ruleName, subTokens, true)
  if not parentIsPasted and not parentIsRecursive then
    --rebuild parts of the tree that might contain data that has to be pasted
    rebuildTree(newToken, subTokens, 1)
  else
    --pasted contents would be pasted again later -> defer pasting
    copyObject(newToken, subTokens)
  end
  return newToken
end

return luaparser
