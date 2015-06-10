-----------------------------------------------------
--name       : lib/devfs/stringfile.lua
--description: implements files that can be getters/setters for string values
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--TODO: documentation
--creates a file table that can be used by the driver library

--library table
local stringfile = {}

--returns a string
--If the parameter is a string it is just returned.
--Else it is executed as a getter function.
local function getString(getter)
  if type(getter) == "string" then
    return getter
  else
    local value = getter()
    assert(type(value) == "string", "Getter did not return a string!")
    return value
  end
end

--This function replaces the stream methods after calling stream:close().
local function alreadyClosed()
  return nil, "Stream closed!"
end

local function closer(self)
  --cleanup #1: replace methods
  self.seek  = alreadyClosed
  self.read  = alreadyClosed
  self.write = alreadyClosed
  self.close = alreadyClosed
  if self.onClose then
    local ok, msg = pcall(self.onClose, self.buffer)
    if not ok then
      return nil, msg
    end
  end
  --cleanup #2: properties
  self.buffer  = nil
  self.onClose = nil
  self.offset  = nil
  self.onWrite = nil
end
local function seeker(self, whence, offset)
  --set default values
  whence = whence or "cur"
  offset = offset or 0
  --determine new offset
  if whence == "cur" then
    self.offset = self.offset + offset
  elseif whence == "set" then
    self.offset = offset
  elseif whence == "end" then
    self.offset = #self.buffer + offset
  else
    return nil, "Unknown 'whence' value!"
  end
  --clip offset to available space
  self.offset = math.max(math.min(self.offset,#self.buffer),0)
  --return new offset
  return self.offset
end

--opens a string file in the given mode while using the given getter and setter functions
--The setter is called on each write operation with the new file content as its argument unless 'setOnClose' is true.
--In that case it is only called once when closing the file.
function stringfile.open(getter, setter, setOnClose, mode)
  --extract mode
  mode = mode or "r"
  mode = mode:match("^([rwa])b?")
  if mode == nil then
    return nil, "Unsupported mode!"
  end
  --create stream object
  local stream = {
    close  = closer,
    seek   = seeker,
    buffer = "",
    offset = 0,
  }
  if mode == "r" or mode == "a" then
    local ok, value = pcall(getString, getter)
    if ok then
      stream.buffer = value
    else
      return nil, value
    end
  end
  if mode == "a" then
    stream.offset = #stream.buffer
  end
  
  if mode == "r" then
    --open file in reading mode
    if getter == nil then
      return nil, "Unable to read!"
    end
    --define a read function
    function stream:read(count)
      local value = self.buffer:sub(self.offset + 1, self.offset + count)
      if #value == 0 and count > 0 then
        --return nil on end of file
        return nil
      end
      self.offset = self.offset + #value
      return value
    end
  elseif mode == "w" or mode == "a" then
    --open file in a writing mode
    if setter == nil then
      return nil, "Unable to write!"
    end
    --set setter callback
    if setOnClose then
      stream.onClose = setter
    else
      stream.onWrite = setter
    end
    --define a write function
    function stream:write(value)
      --TODO: optimize number of strings thrown around
      self.buffer = self.buffer:sub(1, self.offset) .. value .. self.buffer:sub(self.offset + #value + 1, -1)
      self.offset = self.offset + #value
      if self.onWrite then
        -->setter is called on each write call
        local ok, msg = pcall(self.onWrite, self.buffer)
        if not ok then
          return nil, msg
        end
      end
      return true
    end
  end
  return stream
end
--return the size of the given file
function stringfile.size(getter)
  local ok, value = pcall(getString, getter)
  if ok then
    return #value
  else
    return nil, value
  end
end

--returns a driver compatible file table
function stringfile.new(getter, setter, setOnClose)
  return {
    open = function(path, mode)
      return stringfile.open(getter, setter, setOnClose, mode)
    end,
    size = function(path)
      return stringfile.size(getter)
    end,
  }
end

--return library
return stringfile
