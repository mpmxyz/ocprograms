-----------------------------------------------------
--name       : lib/devfs/numberfile.lua
--description: implements files that can be getters/setters for number values
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--TODO: documentation
--creates a file table that can be used by the driver library

--load libraries
local stringfile = require("devfs.stringfile")
--library table
local numberfile = {}

--returns a number
--If the parameter is a number it is just returned.
--Else it is executed as a getter function.
local function getNumberString(getter, binary)
  --TODO: add binary data support
  if type(getter) == "number" then
    return tostring(getter)
  else
    local number = getter()
    assert(type(number) == "number", "Getter did not return a number!")
    return tostring(number)
  end
end

--opens a number file in the given mode while using the given getter and setter functions
--The setter is called when closing the stream.
function numberfile.open(getter, setter, binary, mode)
  --It's actually just a stringfile with modified getters and setters.
  return stringfile.open(
    getter and function()
      return getNumberString(getter, binary)
    end,
    setter and function(value)
      --TODO: add binary data support
      value = tonumber(value)
      if value then
        setter(value)
      else
        error("Could not extract number from data!")
      end
    end,
    true,
    mode
  )
end
--returns the size of the given file
function numberfile.size(getter, binary)
  return stringfile.size(function()
    return getNumberString(getter, binary)
  end)
end

--returns a driver compatible file table
function numberfile.new(getter, setter, binary)
  return {
    open = function(path, mode)
      return numberfile.open(getter, setter, binary, mode)
    end,
    size = function(path)
      return numberfile.size(getter, binary)
    end,
  }
end


--return library
return numberfile
