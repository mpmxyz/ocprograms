-----------------------------------------------------
--name       : lib/crunch/11_value_normalizer.lua
--description: crunch module, transforms strings and numbers to the shortest representation with the same value
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------
local cache     = require("mpm.cache")

return {
  run = function(context, options)
    context.verbose("Value compression...")
    
    local numberToString = cache.wrap(function(value)
      --check different representations, choose the smallest
      local formats = {"%i", "0x%x", "%.*e", "%.*f", "%.*a"}
      local best = nil
      for _, form in ipairs(formats) do
        local pMin, pMax = 0, string.find(form, "%*") and 31 or 0
        while pMax >= pMin do
          local pMid = math.floor(0.5 * (pMin + pMax))
          local ok, text = pcall(string.format, form:gsub("%*", tostring(pMid)), value)
          if not ok then
            --no integer representation
            break
          end
          if tonumber(text) == value then
            --check lower precisions
            pMax = pMid -1
            --check if this is the smallest representation
            if (best == nil) or #text < #best then
              best = text
            end
          else
            --check higher precisions
            pMin = pMid + 1
          end
        end
      end
      return best
    end)
    local function parseString(quote, code)
      --quick and dirty:
      return assert(load("return" .. quote .. code .. quote:gsub("%[", "]")))()
      --[[
      if quote == "\'" or quote == "\"" then
        ---short string
        --TODO: find first escape sequence, replace it, repeat until done
        --TODO: string is built via table.concat
      else
        ---long string
        --remove first newline if there is no preceding character
        code = code:gsub("^\r?\n?", "")
        --correct newline interpretation
        code = code:gsub("\r\n?","\n")
        return code
      end
      ]]
    end
    local function stringToQuote(value)
      local shortReplacements = {
        ["\\"] = "\\\\",
        ["\r"] = "\\r",
        ["\n"] = "\\n",
      }
      local formats = {
        function(text)
          text = text:gsub("[\\\r\n]", shortReplacements):gsub("\"","\\\"")
          return "\"", text, "\""
        end,
        function(text)
          text = text:gsub("[\\\r\n]", shortReplacements):gsub("\'","\\\'")
          return "\'", text, "\'"
        end,
        function(text)
          --\r can't be encoded in long strings
          if text:find("\r") then
            return nil, nil, nil
          end
          --problem: a newline at the beginning of the string is removed
          --solution: add an additional newline
          text = text:gsub("^\n", "\n\n")
          --determine size of opening and closing tags
          local forbiddenEquals = {}
          for equalSigns, nextIndex in text:gmatch("%](=*)()") do
            local nextChar = text:sub(nextIndex, nextIndex)
            if nextChar == "]" or nextChar == "" then
              forbiddenEquals[#equalSigns] = true
            end
          end
          local usedEquals = 0
          while forbiddenEquals[usedEqals] do
            usedEquals = usedEquals + 1
          end
          --return string
          return "["..("="):rep(usedEquals).."[", text, "]"..("="):rep(usedEquals).."]"
        end,
      }
      local bestOpening, bestContent, bestClosing
      local bestLength
      for _, form in ipairs(formats) do
        local opening, content, closing = form(value)
        if opening then
          local length = #opening + #content + #closing
          if bestLength == nil or bestLength > length then
            bestOpening, bestContent, bestClosing = opening, content, closing
            bestLength = length
          end
        end
      end
      
      return bestOpening, bestContent, bestClosing
    end
    
    local function cloner(original)
      return cache.wrap(function(replacementModifier)
        return setmetatable({
          --replacementModifier tells the program the cost of replacing the string by a variable
          --      It comes from the fact that it could also be replaced by .name/name=.
          --      replacementModifier for .name vs. ["name"]     3
          --      replacementModifier for name= vs. ["name"]=    4
          --      (If the benefit of replacing the string by a variable is less or equal to the replacementModifier it is not replaced.)
          replacementModifier = replacementModifier,
          nused = 0,
          unlocked = false,
          unlock = function(self)
            if self.unlocked then
              return
            end
            self.unlocked = true
            --adjusting the nused number of the original token
            --(unlocked clones are not considered to be related to the original token anymore)
            original:removeUsage(self.nused)
            --separating clone from changes to the original
            --part 1: copying every value from the original to the clone
            for k, v in pairs(original) do
              if rawget(self, k) == nil then
                self[k] = v
              end
            end
            --part 2: prevent further references to original token 
            setmetatable(self, nil)
          end,
        },{
          __index = original,
        })
      end)
    end
    local NIL = {}
    local valueRegistry = cache.wrap(function(value)
      local token
      if type(value) == "string" then
        token = {
          typ = "string",
          value = value,
          stringToQuote(value),
        }
      elseif type(value) == "number" then
        token = {
          typ = "number",
          value = value,
          numberToString[value],
        }
      elseif type(value) == "boolean" then
        token = {
          typ = "boolean",
          value = value,
          tostring(value),
        }
      elseif value == NIL then
        token = {
          typ = "nil",
          value = nil,
          "nil",
        }
      end
      token.nused = 0
      token.replacementModifierClones = cloner(token)
      function token:addUsage(amount)
        amount = amount or 1
        self.nused = self.nused + amount
      end
      function token:removeUsage(amount)
        amount = amount or 1
        self.nused = self.nused - amount
      end
      
      return token
    end)
    
    local isBoolOrNil = {
      ["true"]  = true,
      ["false"] = false,
      ["nil"]   = NIL,
    }
    
    local processor
    processor = {
      number = function(token)
        --replacing duplicate number tokens by shared tokens
        local value = tonumber(token[1])
        local token = valueRegistry[value]
        token:addUsage()
        return token
      end,
      string = function(token)
        --replacing duplicate string tokens by shared tokens
        local value = parseString(token[1], token[2])
        local token = valueRegistry[value]
        token:addUsage()
        return token
      end,
      default = function(token)
        if type(token) == "string" then
          --replacing duplicate boolean and nil tokens by shared tokens
          local value = isBoolOrNil[token[1]]
          if value ~= nil then
            local token = valueRegistry[value]
            token:addUsage()
            return token
          end
        else
          context.traverseTree(token, processor)
        end
      end,
    }
    context.traverseTree(context.tokens, processor)
    
    context.valueRegistry = valueRegistry
    context.NIL = NIL
  end,
}
