-----------------------------------------------------
--name       : lib/drivers/zero.lua
--description: adds /dev/zero
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--loading libraries
local driver = require("devfs.driver")
--setting up node
driver.setNode("", "zero", {
  open = function(path, mode)
    mode = mode or "r"
    mode = mode:match("^([rwa])b?")
    if mode == nil then
      return nil, "Unsupported mode!"
    end
    --common functions
    local stream = {
      close = function() end,
      seek = function()
        return 0
      end,
    }
    --mode specific functions
    if mode == "r" then
      function stream:read(count)
        return ("\0"):rep(count)
      end
    else
      function stream:write()
        return true
      end
    end
    --returning finished stream
    return stream
  end,
  size = function()
    return 0
  end,
})
return "loaded"
