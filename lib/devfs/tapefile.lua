-----------------------------------------------------
--name       : lib/devfs/tapefile.lua
--description: allows accessing tape drives as big files
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------



--TODO: documentation
--creates a file table that can be used by the driver library

local component = require("component")

--library table
local tapefile = {}


--This function replaces the stream methods after calling stream:close().
local function alreadyClosed()
  return nil, "Stream closed!"
end

local function closer(self)
  --replace methods
  self.seek  = alreadyClosed
  self.read  = alreadyClosed
  self.write = alreadyClosed
  self.close = alreadyClosed
end
local function seeker(self, whence, offset)
  --set default values
  whence = whence or "cur"
  offset = offset or 0
  --determine change in position
  local dpos
  if whence == "cur" then
    dpos = offset
  elseif whence == "set" then
    dpos = offset - self.pos
  elseif whence == "end" then
    dpos = self.size + offset - self.pos
  else
    return nil, "Unknown 'whence' value!"
  end
  --clip targeted position to available space
  dpos = math.max(math.min(dpos, self.size - self.pos), -self.pos)
  --try seeking
  dpos = self.drive.seek(dpos)
  --calculate position
  self.pos = self.pos + dpos
  --return new position
  return self.pos
end

function tapefile.open(address, rewinding, mode)
  --extract mode
  mode = mode or "r"
  mode = mode:match("^([rw])b?")
  if mode == nil then
    return nil, "Unsupported mode!"
  end
  --create stream object
  local stream = {
    close  = closer,
    seek   = seeker,
    drive  = component.proxy(address),
    pos    = 0,
    size   = tapefile.size(address, rewinding),
  }
  if stream.drive == nil then
    return nil, "Tape drive not found!"
  end
  if rewinding then
    stream.drive.seek(-stream.drive.getSize())
  end
  
  if mode == "r" then
    --open file in reading mode: define a read function
    function stream:read(count)
      local value = self.drive.read(count)
      self.pos = math.min(self.pos + #value, self.size)
      return value
    end
  elseif mode == "w" then
    --open file in a writing mode: define a write function
    function stream:write(value)
      local reachedEnd = (self.pos + #value > self.size)
      self.drive.write(value)
      self.pos = math.min(self.pos + #value, self.size)
      return not reachedEnd, reachedEnd and "eof" or nil
    end
  end
  if rewinding then
    stream.drive.seek(-stream.drive.getSize())
  end
  return stream
end
--return the size of the given file
function tapefile.size(address, rewinding)
  local tape_drive = component.proxy(address)
  if tape_drive == nil then
    return nil, "Tape drive not found!"
  end
  if rewinding then
    return tape_drive.getSize()
  else
    local totalBytes = tape_drive.getSize()
    if totalBytes == 0 then
      return 0
    end
    --get remaining size by seeking to the end
    local previousBytes = -tape_drive.seek(-totalBytes)
    --seek to original position
    tape_drive.seek(previousBytes)
    return totalBytes - previousBytes
  end
end

--returns a driver compatible file table
function tapefile.new(address, rewinding)
  return {
    open = function(path, mode)
      return tapefile.open(address, rewinding, mode)
    end,
    size = function(path)
      return tapefile.size(address, rewinding)
    end,
  }
end

--return library
return tapefile
