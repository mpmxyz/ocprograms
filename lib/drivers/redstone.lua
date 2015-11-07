-----------------------------------------------------
--name       : lib/drivers/redstone.lua
--description: adds a devfs driver for redstone components
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--This driver creates a file interface for redstone components.
--Each component has got the following file structure:
--  <side>
--    input:  vanilla redstone input  (read only)
--    output: vanilla redstone output (read/write)
--    bundled
--      <color>
--        input:  bundled redstone input  (read only)
--        output: bundled redstone output (read/write)
--  wireless
--    frequency: wireless redstone frequency (read/write)
--    input:     wireless redstone input     (read only)
--    output:    wireless redstone output    (read/write)

--loading libraries
local driver = require("devfs.driver")
local numberfile = require("devfs.numberfile")
local component = require("component")
local colors = require("colors")
local sides = require("sides")
local filesystem = require("filesystem")

--generating a (directory name -> side) table for later use
local NAME_TO_SIDE = {}
for sideNum, sideName in pairs(sides) do
  if type(sideNum) == "number" and sideName ~= "unknown" then
    --only use primary names
    NAME_TO_SIDE[tostring(sideNum)] = sideNum
    NAME_TO_SIDE[sideName] = sideNum
  end
end

--generating a (directory name -> color) table for later use
local NAME_TO_COLOR = {}
for colorNum, colorName in pairs(colors) do
  if type(colorNum) == "number" then
    --only use primary names
    NAME_TO_COLOR[tostring(colorNum)] = colorNum
    NAME_TO_COLOR[colorName] = colorNum
  end
end

--returns the side value of a path like "redstone/<side>/input"
local function getSide(path)
  local segments = filesystem.segments(path)
  return NAME_TO_SIDE[segments[#segments - 1]]
end

--returns the side and color values of a path like "redstone/<side>/bundled/<color>/input"
local function getSideColor(path)
  local segments = filesystem.segments(path)
  return NAME_TO_SIDE[segments[#segments - 3]], NAME_TO_COLOR[segments[#segments - 1]]
end


--create the driver table
--all files are created at /dev/redstone/
local redstone_driver = {
  path = "redstone"
}

--This function is called whenever the driver is registered to a new device type
function redstone_driver.init()
  --do nothing
end
--This function is called whenever a new component is added.
--(only when the driver is registered for its type)
function redstone_driver.addComponent(address)
  --get component proxy to refer to its getters and setters
  local proxy = component.proxy(address)
  
  --create a "bundled" directory if bundled redstone is available
  local bundledDirectory
  if proxy.getBundledInput then
    --a number file wrapper to supply side and color information to the getters and setters
    local function colorFile(getter, setter)
      return {
        open = function(path, mode)
          local side, color = getSideColor(path)
          return numberfile.open(
            function()
              return getter(side, color)
            end,
            setter and function(value)
              setter(side, color, value)
            end or nil,
            false,
            mode
          )
        end,
        size = function(path)
          return numberfile.size(function()
            getter(getSideColor(path))
          end)
        end
      }
    end
    --the directory representing a single color
    local colorDirectory = {
      files = {
        input  = colorFile(proxy.getBundledInput),
        output = colorFile(proxy.getBundledOutput, proxy.setBundledOutput),
      }
    }
    --the "bundled" directory
    bundledDirectory = {
      files = {
        --filled in the loop below
      }
    }
    for colorName in pairs(NAME_TO_COLOR) do
      bundledDirectory.files[colorName] = colorDirectory
    end
  end
  
  
  --a number file wrapper to supply side information to the getters and setters
  local function sideFile(getter, setter)
    return {
      open = function(path, mode)
        local side = getSide(path)
        return numberfile.open(
          function()
            return getter(side)
          end,
          setter and function(value)
            setter(side, value)
          end or nil,
          false,
          mode
        )
      end,
      size = function(path)
        return numberfile.size(function()
          return getter(getSide(path))
        end)
      end
    }
  end
  
  --the directory representing a single side
  local sideDirectory = {
    files = {
      input   = sideFile(proxy.getInput),
      output  = sideFile(proxy.getOutput, proxy.setOutput),
      bundled = bundledDirectory,
    }
  }
  
  --the main directory of a component
  local mainDirectory = {
    files = {
      --contains a "wireless" directory if wireless redstone is available
      wireless = proxy.getWirelessInput and {
        files = {
          frequency = numberfile.new(proxy.getWirelessFrequency, proxy.setWirelessFrequency),
          input     = numberfile.new(
            function()
              return proxy.getWirelessInput() and 15 or 0
            end
          ),
          output    = numberfile.new(
            function()
              return proxy.getWirelessOutput() and 15 or 0
            end,
            function(value)
              proxy.setWirelessOutput(value >= 0.5)
            end
          ),
        }
      } or nil
    }
  }
  --adding a directory for each side
  for sideName in pairs(NAME_TO_SIDE) do
    mainDirectory.files[sideName] = sideDirectory
  end
  
  --returning the main directory to add it to the /dev/redstone directory
  return mainDirectory
end
--This function is called whenever a component is removed.
--(only when the driver is registered for its type)
function redstone_driver.removeComponent(address, typ)
  --do nothing
end
--This function is called whenever a driver is unregistered.
function redstone_driver.cleanup()
  --do nothing
end

--registering the driver
driver.add("redstone", redstone_driver)

return "loaded"
