-----------------------------------------------------
--name       : lib/drivers/tape.lua
--description: adds a devfs driver for tape drives
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--This driver creates a file for each tape drive.

--loading libraries
local driver = require("devfs.driver")
local tapefile = require("devfs.tapefile")
local component = require("component")

--create the driver table
--all files are created at /dev/tape/
local tape_driver = {
  path = "tape"
}
local function noop()
end

tape_driver.init = noop

--This function is called whenever a new component is added.
--(only when the driver is registered for its type)
function tape_driver.addComponent(address)
  --return a single device file
  return {
    files = {
      continue    = tapefile.new(address, false),
      rewind      = tapefile.new(address, true ),
    }
  }
end
tape_driver.removeComponent = noop
tape_driver.cleanup = noop

--registering the driver
driver.add("tape_drive", tape_driver)

--returning taoe driver API
return "loaded"
