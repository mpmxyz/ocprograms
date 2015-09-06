-----------------------------------------------------
--name       : lib/drivers/eeprom.lua
--description: eeprom devfs driver
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--This driver creates a directory containing the files "bios", "data" and "label" for each EEPROM.

--loading libraries
local driver = require("devfs.driver")
local stringfile = require("devfs.stringfile")
local component = require("component")

--create the driver table
--all files are created at /dev/eeprom/
local eeprom_driver = {
  path = "eeprom"
}

--This function is called whenever the driver is registered to a new device type
function eeprom_driver.init()
  --do nothing
end
--This function is called whenever a new component is added.
--(only when the driver is registered for its type)
function eeprom_driver.addComponent(address)
  --get component proxy to refer to its getters and setters
  local proxy = component.proxy(address)
  --return a directory...
  return {
    --containing the files "bios", "data" and "label"
    files = {
      bios  = stringfile.new(proxy.get     , proxy.set),
      data  = stringfile.new(proxy.getData , proxy.setData),
      label = stringfile.new(proxy.getLabel, proxy.setLabel),
    }
  }
end
--This function is called whenever a component is removed.
--(only when the driver is registered for its type)
function eeprom_driver.removeComponent(address, typ)
  --do nothing
end
--This function is called whenever a driver is unregistered.
function eeprom_driver.cleanup()
  --do nothing
end

--registering the driver
driver.add("eeprom", eeprom_driver)

--returning eeprom driver API
return "loaded"
