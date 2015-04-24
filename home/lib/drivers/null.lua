
--This driver creates /dev/null, the digital black hole.

--loading libraries
local driver = require("devfs.driver")
--setting up node
driver.setNode("", "null", {
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
      function stream:read()
        return nil
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
