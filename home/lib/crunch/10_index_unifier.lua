-----------------------------------------------------
--name       : lib/crunch/10_index_unifier.lua
--description: crunch module, converts '.name'/{'name'} to '["name"]' as an intermediate step to '[x]'
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------
return {
  run = function(context, options)
    --This code only works if you know how the code is structured.
    if options.tree then
      context.verbose("Index expansion...")
      local processor
      processor = {
        var = function(token)
          --var = [[name | prefixexp '[' exp ']' | prefixexp '.' name ]]
          --exp = [[value | etc.]] with transparent replacement value = [[string | etc.]]
          local first = token[1]
          if first.typ == "prefixexp" then
            local second = token[2]
            if second == "." then
              local name = token[3][1]
              token[2] = "["
              token[3] = {
                typ = "exp",
                {
                  typ = "string",
                  '"',
                  name,
                  '"',
                }
              }
              token[4] = "]"
              context.traverseTree(token, processor)
            end
          end
        end,
        field = function(token)
          --field = [['[' exp ']' '=' exp | name '=' exp | exp ]]
          local first = token[1]
          if first.typ == "name" then
            --get old content
            local name = first[1]
            local exp  = token[3]
            --create new content
            token[1] = "["
            token[2] = {
              typ = "exp",
              {
                typ = "string",
                '"',
                name,
                '"',
              },
            }
            token[3] = "]"
            token[4] = "="
            token[5] = exp
          end
          context.traverseTree(token, processor)
        end,
        args = function(token)
          --args = [['(' [explist] ')' | tableconstructor | string  ]]
          --explist = [[exp {',' exp} ]]
          local first = token[1]
          if first.typ == "string" then
            --single string argument; adding paranthesis for unification
            token[1] = "("
            token[2] = {
              typ = "explist",
              {
                typ = "exp",
                first,
              },
            }
            token[3] = ")"
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
