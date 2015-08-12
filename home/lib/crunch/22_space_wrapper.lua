-----------------------------------------------------
--name       : lib/crunch/22_space_wrapper.lua
--description: wraps the outputstream to automaticly add space characters when needed (assumes that single tokens are NOT split in multiple :write calls)
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------


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

return {
  run = function(context, options)
    local originalStream = context.outputStream
    local writer = newWriter(originalStream)
    
    context.outputStream = {
      parent = originalStream,
      write = function(self, text)
        writer(text)
      end,
      close = function(self)
        return originalStream:close()
      end,
    }
  end,
  cleanup = function(context, options)
    context.outputStream = context.outputStream.parent
  end,
}
