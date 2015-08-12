-----------------------------------------------------
--name       : lib/crunch/25_writer.lua
--description: crunch module, writes all tokens to the output file
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

return {
  run = function(context, options)
    --write header
    if context.header then
      context.verbose("Writing header...")
      for _, text in ipairs(context.header) do
        context.outputStream:write(text)
      end
    end
    --write code
    context.verbose("Writing main code...")
    local processor
    processor = {
      default = function(token)
        if type(token) == "string" then
          context.outputStream:write(token)
        else
          return context.traverseTree(token, processor)
        end
      end,
    }
    context.traverseTree(context.tokens, processor)
  end,
}
