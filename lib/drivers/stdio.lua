-----------------------------------------------------
--name       : lib/drivers/stdio.lua
--description: adds /dev/stdin, /dev/stdout and /dev/stderr
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--loading libraries
local driver = require("devfs.driver")
local buffer = require("buffer")
--io.stdXYZ wrapper
local function wrap(name)
  return {
    read  = function(self, ...)
      local stdin = io[name]
      if stdin.read == buffer.read and stdin.stream then
        --"double layer" buffering caused some problems.
        --(The outer layer requested a specific number of bytes
        -- which caused the inner layer to get multiple inputs.)
        stdin = stdin.stream
      end
      return stdin:read(...)
    end,
    write = function(self, ...)
      return io[name]:write(...)
    end,
    seek  = function(self, ...)
      return io[name]:seek(...)
    end,
    close = function(self, ...)
      return io[name]:close(...)
    end,
  }
end
--stream data
local stdStreams = {
  stdout = wrap("stdout"),
  stdin  = wrap("stdin"),
  stderr = wrap("stderr"),
}
local stdModes = {
  stdout = "wa",
  stdin  = "r",
  stderr = "wa",
}

--setting up nodes
for name, stream in pairs(stdStreams) do
  local modes = "^(["..stdModes[name].."])b?"
  driver.setNode("", name, {
    open = function(path, mode)
      mode = mode or "r"
      mode = mode:match(modes)
      if mode == nil then
        return nil, "Unsupported mode!"
      end
      return stream
    end,
    size = function()
      return 0
    end,
  })
end
return "loaded"
