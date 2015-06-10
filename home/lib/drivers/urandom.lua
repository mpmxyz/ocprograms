-----------------------------------------------------
--name       : lib/drivers/urandom.lua
--description: adds /dev/urandom (and /dev/random until there is a true randomness source)
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--This driver creates the file /dev/urandom.
--It also creates a link from /dev/random to /dev/urandom until there is a special driver featuring a "real" randomness source.

--loading libraries
local driver = require("devfs.driver")

--setting up node
driver.setNode("", "urandom", {
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
        local chars = {}
        for i = 1, count do
          --create random characters
          chars[i] = string.char(math.random(0,255))
        end
        --combine them to a string
        return table.concat(chars)
      end
    else
      function stream:write()
        --TODO: seeding?
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
--unsafe reference until there is a real random source
driver.setNode("", "random", driver.getNode("urandom"))

return "loaded"
