-----------------------------------------------------
--name       : lib/crunch/12_variable_counter.lua
--description: collects information about variable usage to make better decisions about replacements
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------
local cache     = require("mpm.cache")

return {
  run = function(context, options)
    
    --This code only works if you know how the code is structured.
    if options.tree then
      context.verbose("Counting variable usage...")
      local variableRegistry = cache.wrap(function(id)
        local token = {
          typ = "name",
          id = id,
          isLocal = (type(id) == "number"),
          --temporary name...
          type(id) == "string" and id or ("loc_" .. id),
        }
        token.nused = 0
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
      
      local scope = context.createScope()
      
      local callbacks
      callbacks = {
        access = function(token)
          local name = token[1]
          if not context.blacklisted_names[name] then
            local id = scope:stackIndex(name) or name
            token = variableRegistry[id]
            token:addUsage()
            return token
          end
        end,
      }
      scope:push()
      context.traverseTree(context.tokens, context.createTreeProcessor(callbacks, scope))
      scope:pop()
      
      context.variableRegistry = variableRegistry
    end
  end,
}
