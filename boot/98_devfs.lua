-----------------------------------------------------
--name       : boot/98_devfs.lua
--description: loader for devfs project
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local event = require("event")
local filesystem = require("filesystem")
local computer = require("computer")
local driver = require("devfs.driver")

--the name of the driver subdirectory within the libary paths
--(e.g. "drivers" -> "/lib/drivers/"
local DRIVER_SUBDIR = "drivers"

--loads all modules found for a given part of package.path
local function loadPath(path)
  local dir, prefix, ext = path:match("^(.-)([^/]*)%?([^/]*)$")
  --don't search working dir
  if dir and prefix and ext and dir ~= "./" and dir ~= "" then
    for file in filesystem.list(dir .. DRIVER_SUBDIR) do
      --don't require directories
      if file:sub(-1, -1) ~= "/" then
        --extract library name
        local libname = DRIVER_SUBDIR .. "." .. file:gsub(ext.."$", ""):gsub("^"..prefix,"")
        --try loading driver
        local ok, err = pcall(require, libname)
        if not ok then
          event.onError(err)
        end
      end
    end
  end
end

event.listen("init",function()
  --mount file system
  filesystem.mount(driver.filesystem, "/dev")

  --add event listeners
  event.listen("component_added", driver.onComponentAdded)
  event.listen("component_removed", driver.onComponentRemoved)
  event.listen("component_available", driver.onComponentAvailable)
  event.listen("component_unavailable", driver.onComponentUnavailable)
  
  --load drivers
  for path in package.path:gmatch("[^;]+") do
    loadPath(path)
  end
  --ignore further inits
  return false
end)
