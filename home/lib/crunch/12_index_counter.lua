-----------------------------------------------------
--name       : lib/crunch/12_index_counter.lua
--description: collects information about indexing operations to make better decisions about replacements
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------
local cache     = require("mpm.cache")

return {
  run = function(context, options)
    --This code only works if you know how the code is structured.
    if options.tree then
      context.verbose("Counting string usage...")
      local processor
      processor = {
        var = function(token)
          --var = [[name | prefixexp '[' exp ']' | prefixexp '.' name ]]
          --exp = [[value | etc.]] with transparent replacement value = [[string | etc.]]
          local first = token[1]
          if first.typ == "prefixexp" then
            if token[2] == "[" then
              --It's a prefixexp indexed by an expression.
              local exp = token[3]
              if exp[1].typ == "string" then
                --found: prefixexp with string index; can be replaced by .name if the string is a valid identifier
                local name = exp[1].value
                if context.isIdentifier(name) then
                  --3 characters would be saved if written as .name= instead of ["name"]=
                  local clone = exp[1].replacementModifierClones[3]
                  clone:addUsage(1)
                  exp[1] = clone
                end
              end
            end
            context.traverseTree(token, processor)
          end
        end,
        field = function(token)
          --field = [['[' exp ']' '=' exp | name '=' exp | exp ]]
          if token[1] == "[" then
            --It's a field indexed by an expression.
            local exp1  = token[2]
            if exp1[1].typ == "string" then
              --found: field with string index; can be replaced by name= if the string is a valid identifier
              local name = exp1[1].value
              if context.isIdentifier(name) then
                --4 characters would be saved if written as name= instead of ["name"]=
                local clone = exp1[1].replacementModifierClones[4]
                clone:addUsage(1)
                exp1[1] = clone
              end
            end
          end
          context.traverseTree(token, processor)
        end,
        args = function(token)
          --args = [['(' [explist] ')' | tableconstructor | string  ]]
          --explist = [[exp {',' exp} ]]
          if token[1] == "(" then
            local explist = token[2]
            if explist.typ == "explist" and #explist == 1 then
              --only one argument
              local exp = explist[1]
              if exp[1].typ == "string" then
                --found: function call with single string argument
                --2 characters can be saved when the string is not replaced by removing the parenthesis.
                local clone = exp[1].replacementModifierClones[2]
                clone:addUsage(1)
                exp[1] = clone
              end
            end
          end
          context.traverseTree(token, processor)
        end,
        default = function(token)
          return context.traverseTree(token, processor)
        end,
      }
      context.traverseTree(context.tokens, processor)
    end
  end,
}
