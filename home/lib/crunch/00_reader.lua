-----------------------------------------------------
--name       : lib/crunch/00_reader.lua
--description: crunch module, reading a file and outputting tokens
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------
local parser    = require("parser.main")
local luaparser = require("parser.lua")

return {
  run = function(context, options)
    context.verbose("Reading input file...")
    if options.tree then
      --normal tree parsing; output is stored in context.tokens
      local tree, err = parser.parse(context.inputStream:lines(512), luaparser)
      if not tree then
        context.onError(err, context.inputFile)
      end
      context.tokens = tree
    else
      --creating the metatable for the list of tokens
      local meta = {}
      
      if _VERSION <= "Lua 5.2" then
        --Lua 5.2 and earlier: ipairs ignores __index metamethod
        --->create an __ipairs metamethod
        function meta.__ipairs(t)
          local i = 0
          return function()
            i = i + 1
            local obj = t[i]
            if obj then
              return i, obj
            end
          end
        end
      end
      --The index of the currently loaded token.
      local currentIndex = 0
      --an __index metamethod that is yielding to allow processing one token at a time
      --It requires a strictly sequential access to the list of tokens. (repeated access to the same index is allowed)
      function meta.__index(t, i)
        if i == currentIndex then
          --> signaling the ending - again (only executed on the second reading access)
          return nil
        end
        if i == currentIndex + 1 then
          --> wait for updated value
          coroutine.yield()
          --check currentIndex has been updated
          if i == currentIndex then
            --return updated value
            return rawget(t, i)
          end
        end
        error("Sequential access expected, tried to access index "..i.."(current: "..currentIndex..")")
      end
      --creating the list of tokens using the metatable
      --It is created this way to avoid duplicate code for tree and non-tree processing.
      local tokens = setmetatable({typ = "notree"}, meta)
      context.tokens = tokens
      
      --creating the tokens (same code as in the parser.parse function)
      local onToken = luaparser.onToken or
        function(typ, source, from, to, extracted)
          return {typ = typ, extracted or source:sub(from, to)}
        end
      
      --lexer output function
      local function output(typ, ...)
        if not luaparser.ignored[typ] then
          --delete old token
          tokens[currentIndex] = nil
          --advance index
          currentIndex = currentIndex + 1
          --create new token
          tokens[currentIndex] = onToken(typ, ...)
          --yield to continue processing in other threads
          coroutine.yield()
        end
      end
      --just running the normal lexer: all the magic is within the output function
      local ok, err = parser.lexer(context.inputStream:lines(512), luaparser.lexer, output)
      if not ok then
        context.onError(err, context.inputFile)
      end
      --advance index a last time to make it point to a nil value
      currentIndex = currentIndex + 1
    end
  end,
}
