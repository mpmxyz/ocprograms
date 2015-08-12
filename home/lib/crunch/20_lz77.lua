-----------------------------------------------------
--name       : lib/crunch/20_lz77.lua
--description: crunch module, writes lz77 prefix, wraps the stream, adds decompression code on cleanup
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local lz77      = require("parser.lz77")


return {
  run = function(context, options)
    --LZ77 SXF option
    if options.lz77 then
      context.verbose("Adding LZ77 wrapper...")
      local originalStream = context.outputStream
      --an output function for the lz77 compression function
      local function lz77output(value)
        originalStream:write(value)
      end
      --create and init a compressor coroutine
      context.lz77yieldedCompress = coroutine.create(lz77.compress)
      assert(coroutine.resume(context.lz77yieldedCompress, coroutine.yield, options.lz77, lz77output, 1000))
      --replace the original stream
      context.outputStream = {
        parent = originalStream,
        write = function(self, value)
          return assert(coroutine.resume(context.lz77yieldedCompress, value))
        end,
        close = function()
          return originalStream:close()
        end,
        seek = function(self, ...)
          return originalStream:seek(...)
        end,
      }
      --lz77 header
      originalStream:write("local i=[[\n")
    end
  end,
  cleanup = function(context, options)
    if options.lz77 then
      context.verbose("Adding LZ77 decompressor...")
      --finish lz77 compression
      while coroutine.status(context.lz77yieldedCompress) == "suspended" do
        assert(coroutine.resume(context.lz77yieldedCompress, nil))
      end
      --restore original output stream
      context.outputStream = context.outputStream.parent
      
      ---finishing...
      context.outputStream:write("]]")
      --append decompression code
      context.outputStream:write(lz77.getSXF("i", "o", options.lz77))
      --append launcher
      context.outputStream:write("\nreturn assert(load(o))(...)")
    end
  end,
}
