-----------------------------------------------------
--name       : lib/drivers/sign.lua
--description: adds a devfs driver for sign upgrades
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--This driver creates a file for each sign upgrade.

--loading libraries
local driver = require("devfs.driver")
local stringfile = require("devfs.stringfile")
local component = require("component")

--create the driver table
--all files are created at /dev/sign/
local sign_driver = {
  path = "sign"
}

--This function is called whenever the driver is registered to a new device type
function sign_driver.init()
  --do nothing
end
--This function is called whenever a new component is added.
--(only when the driver is registered for its type)
function sign_driver.addComponent(address)
  --get component proxy to refer to its getters and setters
  local proxy = component.proxy(address)
  --return a single device file
  return stringfile.new(proxy.getValue, proxy.setValue)
end
--This function is called whenever a component is removed.
--(only when the driver is registered for its type)
function sign_driver.removeComponent(address, typ)
  --do nothing
end
--This function is called whenever a driver is unregistered.
function sign_driver.cleanup()
  --do nothing
end

--registering the driver
driver.add("sign", sign_driver)

--returning sign driver API
return "loaded"
