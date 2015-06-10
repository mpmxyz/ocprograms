-----------------------------------------------------
--name       : lib/devfs/driver.lua
--description: organizes devfs drivers and files
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--drivers[device type] -> driver -> one or multiple file systems or files
--Drivers should be separate files.
--listen to component_added/removed events...

--load libraries
local filesystem = require("filesystem")
local component = require("component")
local event = require("event")
--library table
local driver = {}

local PRIMARY_NAME = "primary"

--drivers[component type] -> {init() -> path, cleanup(), addComponent(address, typ)->{file system}, removeComponent(typ->address)}
local drivers = {}
--contexts[component type] -> context; might be used to instantiate some kind of "default drivers"
local contexts = {}
--primaries[component type] -> (files[name] -> file)
local primaries = {}
--directory structure
local root = {
  files = {},
  --has been made weak in an attempt to avoid out of memory errors
  --When the real error source is found it might be removed.
  opened = setmetatable({}, {__mode = "kv"}),
}
--gets the device fs node for the given path
--When the optional argument createMIssing is true, it creates missing nodes as directories.
function driver.getNode(path, createMissing)
  local node = root
  for _, part in ipairs(filesystem.segments(path)) do
    --Nodes without 'files' field aren't directories.
    if node.files == nil then
      return nil, "Device not found! (not a directory)"
    end
    --get subnode
    local subNode = node.files[part]
    if subNode == nil then
      --node not found
      if createMissing then
        --create a subdirectory
        subNode = {
          files = {},
        }
        node.files[part] = subNode
      else
        --return error
        return nil, "Device not found! (non existent file)"
      end
    end
    node = subNode
  end
  --return final node
  return node
end
--sets the device fs node for the path (parentPath.."/"..key) to the new 'value'
--It also creates all missing directories if the optional argument 'createMissing' is true.
function driver.setNode(parentPath, key, value, createMissing)
  local parentNode, msg = driver.getNode(parentPath, createMissing)
  if parentNode == nil then
    return nil, msg
  end
  if parentNode.files == nil then
    return nil, "Parent isn't a directory!"
  end
  parentNode.files[key] = value
end


--definition of device fs
driver.filesystem = {}
--fs.open opens a file and returns a handle.
--uses node.open(path, mode) to get a stream object
function driver.filesystem.open(path, mode)
  local node, msg = driver.getNode(path)
  if node == nil then
    return nil, msg
  end
  --error message for directories that can't be opened
  if node.open == nil then
    return nil, "Tried to open a directory!"
  end
  --try opening file
  local stream, error = node.open(path, mode)
  if stream then
    --get a new handle: It was an integer handle but has been changed to the object itself in an attempt to avoid out of memory bugs.
    --The handle -> object table is kept until it is clear that no code expects to receive an integer handle.
    --(makes reverting easier)
    local handle = stream
    root.opened[handle] = stream
    return handle
  else
    return nil, error
  end
end
--fs.seek seeks to a given position.
--uses stream:seek(whence, offset) -> newPosition
function driver.filesystem.seek(handle, whence, offset)
  local stream = root.opened[handle]
  if stream then
    return stream:seek(whence, offset)
  else
    return nil, "Stream already closed!"
  end
end
--fs.read reads the given number of bytes.
--uses stream:read(count) -> data
function driver.filesystem.read(handle, count)
  local stream = root.opened[handle]
  if stream then
    if stream.read then
      return stream:read(count)
    else
      return nil, "Opened in write mode!"
    end
  else
    return nil, "Stream already closed!"
  end
end
--fs.write writes the given data.
--uses stream:write(data)
function driver.filesystem.write(handle, value)
  local stream = root.opened[handle]
  if stream then
    if stream.write then
      return stream:write(value)
    else
      return nil, "Opened in read mode!"
    end
  else
    return nil, "Stream already closed!"
  end
end
--fs.close closes an opened stream.
--uses stream:close()
function driver.filesystem.close(handle)
  local stream = root.opened[handle]
  if stream then
    root.opened[handle] = nil
    return stream:close()
  else
    return nil, "Stream already closed!"
  end
end
--fs.size returns the size of the given file.
--uses node.size(path) to get the file size
function driver.filesystem.size(path)
  local node, msg = driver.getNode(path)
  if node == nil then
    return nil, msg
  end
  return node.size and node.size(path) or 0
end
--fs.exists returns true if the given path exists.
function driver.filesystem.exists(path)
  return (driver.getNode(path) ~= nil)
end
--fs.list returns an unordered list of subnodes within the given path.
function driver.filesystem.list(path)
  local node, msg = driver.getNode(path)
  if node == nil then
    return nil, msg
  end
  local list = {}
  if node.files then
    --Nodes that aren't directories just return an empty list.
    for file, subNode in pairs(node.files) do
      if subNode.files then
        list[#list + 1] = file .. "/"
      else
        list[#list + 1] = file
      end
    end
  end
  return list
end
--fs.lastModified is not supported.
--returns 0
function driver.filesystem.lastModified()
  return 0
end
--fs.spaceUsed is not supported.
--returns 0
function driver.filesystem.spaceUsed()
  return 0
end
--fs.spaceTotal is not supported.
--returns 0
function driver.filesystem.spaceTotal()
  return 0
end
--fs.isDirectory returns if the node contains subnodes.
--(checks if it has the field 'files')
function driver.filesystem.isDirectory(path)
  local node, msg = driver.getNode(path)
  if node == nil then
    return false
  end
  return (node.files ~= nil)
end
--fs.isReadOnly returns false to keep programs from avoiding write operations.
function driver.filesystem.isReadOnly()
  return false
end
--fs.getLabel is fixed to return "devices".
function driver.filesystem.getLabel()
  return "devices"
end
--fs.setLabel is not supported.
function driver.filesystem.setLabel()
  return nil, "Cannot modify device structure!"
end
--fs.makeDirectory is not supported.
function driver.filesystem.makeDirectory()
  return nil, "Cannot modify device structure!"
end
--fs.rename is not supported.
function driver.filesystem.rename()
  return nil, "Cannot modify device structure!"
end
--fs.remove is not supported.
function driver.filesystem.remove()
  return nil, "Cannot modify device structure!"
end


--is called whenever a new component has been added
function driver.onComponentAdded(event, address, typ)
  --get driver
  local currentDriver = drivers[typ]
  if currentDriver then
    --add device; receive file table for /dev/<type>
    local file = currentDriver.addComponent(address, typ, contexts[typ])
    if file then
      --add file(s) to type subdirectory
      driver.setNode(currentDriver.path, address, file)
    end
  end
end
--is called whenever a component has been removed
function driver.onComponentRemoved(event, address, typ)
  --get driver
  local currentDriver = drivers[typ]
  if currentDriver then
    --remove device file
    driver.setNode(currentDriver.path, address, nil)
    --call cleanup method
    currentDriver.removeComponent(address, typ, contexts[typ])
  end
end
--is called whenever a new primary component is available
function driver.onComponentAvailable(event, typ)
  --get driver
  local currentDriver = drivers[typ]
  if currentDriver == nil then
    return
  end
  --get driver directory node
  local node = driver.getNode(currentDriver.path)
  if node == nil then
    return
  end
  --ignore outdated/incorrect events
  --TODO: throw errors instead?
  if not component.isAvailable(typ) then
    return
  end
  if primaries[typ] then
    --remove previous primary
    driver.onComponentUnavailable(nil, typ)
  end
  --get primary component address
  local proxy = component.getPrimary(typ)
  local address = proxy.address
  --get the device file of the current component
  local sourceNode = node.files[address]
  if sourceNode == nil then
    --no device files associated
    return
  end
  --use primaries[typ] to be able to undo changes to the driver directory
  primaries[typ] = {}
  if sourceNode.files then
    --Device "file" is a directory containing multiple files:
    --copy all files to the driver directory
    for name, file in pairs(sourceNode.files) do
      assert(node.files[name] == nil, "Error: attempted to overwrite existing device file!")
      node.files[name] = file
      primaries[typ][name] = file
    end
  else
    --Device file is a file:
    --create a "primary" file
    assert(node.files[PRIMARY_NAME] == nil, "Error: attempted to overwrite existing device file!")
    node.files[PRIMARY_NAME] = sourceNode
    primaries[typ][PRIMARY_NAME] = sourceNode
  end
end
--is called whenever a primary component is removed
function driver.onComponentUnavailable(event, typ)
  --get driver
  local currentDriver = drivers[typ]
  if currentDriver == nil then
    return
  end
  --get driver directory node
  local node = driver.getNode(currentDriver.path)
  if node == nil then
    return
  end
  --get primary files
  local primaryFiles = primaries[typ]
  if primaryFiles == nil then
    return
  end
  --remove primary files from driver directory
  primaries[typ] = nil
  for name, file in pairs(primaryFiles) do
    assert(node.files[name] == file, "Error: primary device file has been modified! (internal stuff)")
    node.files[name] = nil
  end
end

--This function sets the driver for the given component type.
--An already existing driver is replaced.
function driver.add(typ, newDriver)
  if drivers[typ] then
    --remember known devices to init them after driver change
    driver.remove(typ)
  end
  --get directory path
  newDriver.path = newDriver.path or typ
  --clear file system
  driver.setNode("", newDriver.path, {
    files = {},
  })
  --init driver
  drivers[typ]  = newDriver
  contexts[typ] = newDriver.init()
  --init components
  for address in component.list(typ, true) do
    driver.onComponentAdded(nil, address, typ)
  end
  driver.onComponentAvailable(nil, typ)
end
--This function removes the driver from the given component type.
function driver.remove(typ)
  local oldDriver = drivers[typ]
  if oldDriver then
    local oldDevices = devices[typ]
    --removing components
    driver.onComponentUnavailable(nil, typ)
    for address in component.list(typ, true) do
      driver.onComponentRemoved(nil, address, typ)
    end
    --driver cleanup
    oldDriver.cleanup(contexts[typ])
    drivers[typ]  = nil
    contexts[typ] = nil
    driver.setNode("", oldDriver.path, nil)
  end
end
--lists all drivers in a (component type -> driver) table
function driver.list()
  local t = {}
  for k, v in pairs(drivers) do
    t[k] = v
  end
  return t
end

--return library
return driver
