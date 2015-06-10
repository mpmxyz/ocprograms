-----------------------------------------------------
--name       : bin/tar.lua
--description: creating, viewing and extracting tar archives on disk and tape
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/421-tar-for-opencomputers/
-----------------------------------------------------
--[[
  tar archiver for OpenComputers
  for further information check the usage text or man page
  
  TODO: support non primary tape drives
  TODO: detect symbolic link cycles (-> remember already visited, resolved paths)
]]
local shell     = require 'shell'
local fs        = require 'filesystem'
local component = require 'component'

local BLOCK_SIZE = 512
local NULL_BLOCK = ("\0"):rep(BLOCK_SIZE)
local WORKING_DIRECTORY = fs.canonical(shell.getWorkingDirectory()):gsub("/$","")

--load auto_progress library if possible
local auto_progress
if true then
  local ok
  ok, auto_progress = pcall(require, "mpm.auto_progress")
  if not ok then
    auto_progress = {}
    function auto_progress.new()
      --library not available, create stub
      return {
        update = function() end,
        finish = function() end,
      }
    end
  end
end

--error information
local USAGE_TEXT = [[
Usage:
tar <function letter> [other options] FILES...
function letter    description
-c --create         creates a new archive
-r --append         appends to existing archive
-t --list           lists contents from archive
-x --extract --get  extracts from archive
other options      description
-f --file FILE      first FILE is archive, else:
                    uses primary tape drive
-h --dereference    follows symlinks
--exclude=FILE;...  excludes FILE from archive
-v --verbose        lists processed files, also
                    shows progress for large files
]]
local function addUsage(text)
  return text .. "\n" .. USAGE_TEXT
end
local ERRORS = {
  missingAction   = addUsage("Error: Missing function letter!"),
  multipleActions = addUsage("Error: Multiple function letters!"),
  missingFiles    = addUsage("Error: Missing file names!"),
  invalidChecksum = "Error: Invalid checksum!",
  noHeaderName    = "Error: No file name in header!",
  invalidTarget   = "Error: Invalid target!",
}


--formats numbers and stringvalues to comply to the tar format
local function formatValue(text, length, maxDigits)
  if type(text) == "number" then
    maxDigits = maxDigits or (length - 1) --that is default
    text = ("%0"..maxDigits.."o"):format(text):sub(-maxDigits, -1)
  elseif text == nil then
    text = ""
  end
  return (text .. ("\0"):rep(length - #text)):sub(-length, -1)
end

--a utility to make accessing the header easier
--Only one header is accessed at a time: no need to throw tables around.
local header = {}
--loads a header, uses table.concat on tables, strings are taken directly
function header:init(block)
  if type(block) == "table" then
    --combine tokens to form one 512 byte long header
    block = table.concat(block, "")
  elseif block == nil then
    --make this header a null header
    block = NULL_BLOCK
  end
  if #block < BLOCK_SIZE then
    --add "\0"s to reach 512 bytes
    block = block .. ("\0"):rep(BLOCK_SIZE - #block)
  end
  --remember the current block
  self.block = block
end
--takes the given data and creates a header from it
--the resulting block can be retrieved via header:getBytes()
function header:assemble(data)
  if #data.name > 100 then
    local longName = data.name
    --split at slash
    local minPrefixLength = #longName - 101 --(100x suffix + 1x slash)
    local splittingSlashIndex = longName:find("/", minPrefixLength + 1, true)
    if splittingSlashIndex then
      --can split path in 2 parts separated by a slash
      data.filePrefix = longName:sub(1, splittingSlashIndex - 1)
      data.name       = longName:sub(splittingSlashIndex + 1, -1)
    else
      --unable to split path; try to put path to the file prefix
      data.filePrefix = longName
      data.name       = ""
    end
    --checking for maximum file prefix length
    assert(#data.filePrefix <= 155, "File name '"..longName.."' is too long; unable to apply ustar splitting!")
    --force ustar format
    data.ustarIndicator = "ustar"
    data.ustarVersion = "00"
  end
  local tokens = {
    formatValue(data.name,          100), --1
    formatValue(data.mode,            8), --2
    formatValue(data.owner,           8), --3
    formatValue(data.group,           8), --4
    formatValue(data.size,           12), --5
    formatValue(data.lastModified,   12), --6
    "        ",--8 spaces                 --7
    formatValue(data.typeFlag,        1), --8
    formatValue(data.linkName,      100), --9
  }
  --ustar extension?
  if data.ustarIndicator then
    table.insert(tokens, formatValue(data.ustarindicator,      6))
    table.insert(tokens, formatValue(data.ustarversion,        2))
    table.insert(tokens, formatValue(data.ownerUser,          32))
    table.insert(tokens, formatValue(data.ownerGroup,         32))
    table.insert(tokens, formatValue(data.deviceMajor,         8))
    table.insert(tokens, formatValue(data.deviceMinor,         8))
    table.insert(tokens, formatValue(data.filePrefix,        155))
  end
  --temporarily assemble header for checksum calculation
  header:init(tokens)
  --calculating checksum
  tokens[7] = ("%06o\0\0"):format(header:checksum(0, BLOCK_SIZE))
  --assemble final header  
  header:init(tokens)
end
--extracts the information from the given header
function header:read()
  local data = {}
  data.name           = self:extract      (0  , 100)
  data.mode           = self:extract      (100, 8)
  data.owner          = self:extractNumber(108, 8)
  data.group          = self:extractNumber(116, 8)
  data.size           = self:extractNumber(124, 12)
  data.lastModified   = self:extractNumber(136, 12)
  data.checksum       = self:extractNumber(148, 8)
  data.typeFlag       = self:extract      (156, 1) or "0"
  data.linkName       = self:extract      (157, 100)
  data.ustarIndicator = self:extract      (257, 6)
  
  --There is an old format using "ustar  \0" instead of "ustar\0".."00"?
  if data.ustarIndicator and data.ustarIndicator:sub(1,5) == "ustar" then
    data.ustarVersion = self:extractNumber(263, 2)
    data.ownerUser    = self:extract      (265, 32)
    data.ownerGroup   = self:extract      (297, 32)
    data.deviceMajor  = self:extractNumber(329, 8)
    data.deviceMinor  = self:extractNumber(337, 8)
    data.filePrefix   = self:extract      (345, 155)
  end
  
  assert(self:verify(data.checksum), ERRORS.invalidChecksum)
  --assemble raw file name, normally relative to working dir
  if data.filePrefix then
    data.name = data.filePrefix .. "/" .. data.name
    data.filePrefix = nil
  end
  assert(data.name, ERRORS.noHeaderName)
  return data
end
--returns the whole 512 bytes of the header
function header:getBytes()
  return header.block
end
--returns if the header is a null header
function header:isNull()
  return self.block == NULL_BLOCK
end
--extracts a 0 terminated string from the given area
function header:extract(offset, size)
  --extract size bytes from the given offset, strips every NULL character
  --returns a string
  return self.block:sub(1 + offset, size + offset):match("[^\0]+")
end
--extracts an octal number from the given area
function header:extractNumber(offset, size)
  --extract size bytes from the given offset
  --returns the first series of octal digits converted to a number
  return tonumber(self.block:sub(1 + offset, size + offset):match("[0-7]+") or "", 8)
end
--calculates the checksum for the given area
function header:checksum(offset, size, signed)
  --calculates the checksum of a given range
  local sum = 0
  --summarize byte for byte
  for index = 1 + offset, size + offset do
    if signed then
      --interpretation of a signed byte: compatibility for bugged implementations
      sum = sum + (self.block:byte(index) + 128) % 256 - 128
    else
      sum = sum + self.block:byte(index)
    end
  end
  --modulo to take care of negative sums
  --The whole reason for the signed addition is that some implementations
  --used signed bytes instead of unsigned ones and therefore computed 'wrong' checksums.
  return sum % 0x40000
end
--checks if the given checksum is valid for the loaded header
function header:verify(checksum)
  local checkedSums = {
    [self:checksum(0, 148, false) + 256 + self:checksum(156, 356, false)] = true,
    [self:checksum(0, 148, true ) + 256 + self:checksum(156, 356, true )] = true,
  }
  return checkedSums[checksum] or false
end


local function makeRelative(path, reference)
  --The path and the reference directory must have a common reference. (e.g. root)
  --The default reference is the current working directory.
  reference = reference or WORKING_DIRECTORY
  --1st: split paths into segments
  local returnDirectory = path:sub(-1,-1) == "/" --?
  path = fs.segments(path)
  reference = fs.segments(reference)
  --2nd: remove common directories
  while path[1] and reference[1] and path[1] == reference[1] do
    table.remove(path, 1)
    table.remove(reference, 1)
  end
  --3rd: add ".."s to leave that what's left of the working directory
  local path = ("../"):rep(#reference) .. table.concat(path, "/")
  --4th: If there is nothing remaining, we are at the current directory.
  if path == "" then
    path = "."
  end
  return path
end


local function tarFiles(files, options, mode, ignoredObjects, isDirectoryContent)
  --combines files[2], files[3], ... into files[1]
  --prepare output stream
  local target, closeAtExit
  if type(files[1]) == "string" then
    --mode = append -> overwrite trailing NULL headers
    local targetFile = shell.resolve(files[1]):gsub("/$","")
    ignoredObjects[targetFile] = ignoredObjects[targetFile] or true
    target = assert(io.open(targetFile, mode))
    closeAtExit = true
  else
    target = files[1]
    closeAtExit = false
    assert(target.write, ERRORS.invalidTarget)
  end
  if mode == "rb+" then --append: not working with files because io.read does not support mode "rb+"
    --start from beginning of file
    assert(target:seek("set", 0))
    --loop over every block
    --This loop implies that it is okay if there is nothing (!) after the last file block.
    --It also ensures that trailing null blocks are overwritten.
    for block in target:lines(BLOCK_SIZE) do
      if #block < BLOCK_SIZE then
        --reached end of file before block was finished
        error("Missing "..(BLOCK_SIZE-#block).." bytes to finish block.")
      end
      --load header
      header:init(block)
      if header:isNull() then
        --go back to the beginning of the block
        assert(target:seek("cur", -BLOCK_SIZE))
        --found null header -> finished with skipping
        break
      end
      --extract size information from header
      local data = header.read(header)
      if data.size and data.size > 0 then
        --skip file content
        local skippedBytes = math.ceil(data.size / BLOCK_SIZE) * BLOCK_SIZE
        assert(target:seek("cur", skippedBytes))
      end
    end
    if options.verbose then
      print("End of archive detected; appending...")
    end
  end
  for i = 2, #files do
    --prepare data
    --remove trailing slashes that might come from fs.list
    local file = shell.resolve(files[i]):gsub("/$","")
    --determine object type, that determines how the object is handled
    local isALink, linkTarget = fs.isLink(file)
    local objectType
    if isALink and not options.dereference then
      objectType = "link" --It's a symbolic link.
    else
      if fs.isDirectory(file) then
        objectType = "dir" --It's a directory.
      else
        objectType = "file" --It's a normal file.
      end
    end
    --add directory contents before the directory
    --(It makes sense if you consider that you could change the directories file permissions to be read only.)
    if objectType == "dir" and ignoredObjects[file] ~= "strict" then
      local list = {target}
      local i = 2
      for containedFile in fs.list(file) do
        list[i] = fs.concat(file, containedFile)
        i = i + 1
      end
      tarFiles(list, options, nil, ignoredObjects, true)
    end
    --Ignored objects are not added to the tar.
    if not ignoredObjects[file] then
      local data = {}
      --get relative path to current directory
      data.name = makeRelative(file)
      --add object specific data
      if objectType == "link" then
        --It's a symbolic link.
        data.typeFlag = "2"
        data.linkName = makeRelative(linkTarget, fs.path(file)):gsub("/$","") --force relative links
      else
        data.lastModified = math.floor(fs.lastModified(file) / 1000) --Java returns milliseconds...
        if objectType == "dir" then
          --It's a directory.
          data.typeFlag = "5"
          data.mode = 448 --> 700 in octal -> rwx------
        elseif objectType == "file" then
          --It's a normal file.
          data.typeFlag = "0"
          data.size = fs.size(file)
          data.mode = 384 --> 600 in octal -> rw-------
        end
      end
    
      --tell user what is going on
      if options.verbose then
        print("Adding:", data.name)
      end
      --assemble header
      header:assemble(data)
      --write header
      assert(target:write(header:getBytes()))
      --copy file contents
      if objectType == "file" then
        --open source file
        local source = assert(io.open(file, "rb"))
        --keep track of what has to be copied
        local bytesToCopy = data.size
        --init progress bar
        local progressBar = auto_progress.new(bytesToCopy)
        --copy file contents
        for block in source:lines(BLOCK_SIZE) do
          assert(target:write(block))
          bytesToCopy = bytesToCopy - #block
          assert(bytesToCopy >= 0, "Error: File grew while copying! Is it the output file?")
          if options.verbose then
            --update progress bar
            progressBar.update(#block)
          end
          if #block < BLOCK_SIZE then
            assert(target:write(("\0"):rep(BLOCK_SIZE - #block)))
            break
          end
        end
        --close source file
        source:close()
        if options.verbose then
          --draw full progress bar
          progressBar.finish()
        end
        assert(bytesToCopy <= 0, "Error: Could not copy file!")
      end
    end
  end
  if not isDirectoryContent then
    assert(target:write(NULL_BLOCK)) --Why wasting 0.5 KiB if you can waste a full KiB? xD
    assert(target:write(NULL_BLOCK)) --(But that's the standard!)
  end
  if closeAtExit then
    target:close()
  end
end



local extractingExtractors = {
  ["0"] = function(data, options) --file
    --creates a file at data.file and fills it with data.size bytes
    --ensure that the directory is existing
    local dir = fs.path(data.file)
    if not fs.exists(dir) then
      fs.makeDirectory(dir)
    end
    --don't overwrite the file if true
    local skip = false
    --check for existing file
    if fs.exists(data.file) then
      if options.verbose then
        print("File already exists!")
      end
      --check for options specifying what to do now...
      if options["keep-old-files"] then
        error("Error: Attempting to overwrite: '"..data.file.."'!")
      elseif options["skip-old-files"] then
        --don't overwrite
        skip = true
      elseif options["keep-newer-files"] and data.lastModified then
        --don't overwrite when file on storage is newer
        local lastModifiedOnDrive = math.floor(fs.lastModified(data.file) / 1000)
        if lastModifiedOnDrive > data.lastModified then
          skip = true
        end
      else
        --default: overwrite
      end
      if options.verbose and not skip then
        --verbose: tell user that we are overwriting
        print("Overwriting...")
      end
    end
    if skip then
      --go to next header
      return data.size
    end
    
    --open target file
    local target = assert(io.open(data.file, "wb"))
    --set file length
    local bytesToCopy = data.size
    --init progress bar
    local progressBar = auto_progress.new(bytesToCopy)
    --create extractor function, writes min(bytesToCopy, #block) bytes to target
    local function extractor(block)
      --shortcut for abortion
      if block == nil then
        target:close()
        return nil
      end
      --adjust block size to missing number of bytes
      if #block > bytesToCopy then
        block = block:sub(1, bytesToCopy)
      end
      --write up to BLOCK_SIZE bytes
      assert(target:write(block))
      --subtract copied amount of bytes from bytesToCopy
      bytesToCopy = bytesToCopy - #block
      if bytesToCopy <= 0 then
        --close target stream when done
        target:close()
        if options.verbose then
          --draw full progress bar
          progressBar.finish()
        end
        --return nil to finish
        return nil
      else
        if options.verbose then
          --update progress bar
          progressBar.update(#block)
        end
        --continue
        return extractor
      end
    end
    if bytesToCopy > 0 then
      return extractor
    else
      target:close()
    end
  end,
  ["2"] = function(data, options) --symlink
    --ensure that the directory is existing
    local dir = fs.path(data.file)
    if not fs.exists(dir) then
      fs.makeDirectory(dir)
    end
    --check for existing file
    if fs.exists(data.file) then
      if options.verbose then
        print("File already exists!")
      end
      if options["keep-old-files"] then
        error("Error: Attempting to overwrite: '"..data.file.."'!")
      elseif options["skip-old-files"] then
        return
      elseif options["keep-newer-files"] and data.lastModified then
        --don't overwrite when file on storage is newer
        local lastModifiedOnDrive = math.floor(fs.lastModified(data.file) / 1000)
        if lastModifiedOnDrive > data.lastModified then
          return
        end
      else
        --default: overwrite file
      end
      --delete original file
      if options.verbose then
        print("Overwriting...")
      end
      assert(fs.remove(data.file))
    end
    assert(fs.link(data.linkName, data.file))
  end,
  ["5"] = function(data, options) --directory
    if not fs.isDirectory(data.file) then
      assert(fs.makeDirectory(data.file))
    end
  end,
}
local listingExtractors = {
  ["0"] = function(data, options) --file
    --output info
    print("File:", data.name)
    print("Size:", data.size)
    --go to next header
    return data.size
  end,
  ["1"] = function(data, options) --hard link: unsupported, but reported
    print("Hard link (unsupported):", data.name)
    print("Target:", data.linkName)
  end,
  ["2"] = function(data, options) --symlink
    print("Symbolic link:", data.name)
    print("Target:", data.linkName)
  end,
  ["3"] = function(data, options) --device file: unsupported, but reported
    print("Device File (unsupported):", data.name)
  end,
  ["4"] = function(data, options) --device file: unsupported, but reported
    print("Device File (unsupported):", data.name)
  end,
  ["5"] = function(data, options) --directory
    print("Directory:", data.name)
  end,
}


local function untarFiles(files, options, extractorList)
  --extracts the contents of every tar file given
  for _,file in ipairs(files) do
    --prepare input stream
    local source, closeAtExit
    if type(file) == "string" then
      source = assert(io.open(shell.resolve(file), "rb"))
      closeAtExit = true
    else
      source = file
      closeAtExit = false
      assert(source.lines, "Unknown source type.")
    end
    local extractor = nil
    local hasDoubleNull = false
    for block in source:lines(BLOCK_SIZE) do
      if #block < BLOCK_SIZE then
        error("Error: Unfinished Block; missing "..(BLOCK_SIZE-#block).." bytes!")
      end
      if extractor == nil then
        --load header
        header:init(block)
        if header:isNull() then
          --check for second null block
          if source:read(BLOCK_SIZE) == NULL_BLOCK then
            hasDoubleNull = true
          end
          --exit/close file when there is a NULL header
          break
        else
          --read block as header
          local data = header:read()
          if options.verbose then
            --tell user what is going on
            print("Extracting:", data.name)
          end
          --enforcing relative paths
          data.file = shell.resolve(WORKING_DIRECTORY.."/"..data.name)
          --get extractor
          local extractorInit = extractorList[data.typeFlag]
          assert(extractorInit, "Unknown type flag \""..tostring(data.typeFlag).."\"")
          extractor = extractorInit(data, options)
        end
      else
        extractor = extractor(block)
      end
      if type(extractor) == "number" then
        if extractor > 0 then
          --adjust extractorInit to block size
          local bytesToSkip = math.ceil(extractor / BLOCK_SIZE) * BLOCK_SIZE
          --skip (extractorInit) bytes
          assert(source:seek("cur", bytesToSkip))
        end
        --expect next header
        extractor = nil
      end
    end
    assert(extractor == nil, "Error: Reached end of file but expecting more data!")
    if closeAtExit then
      source:close()
    end
    if not hasDoubleNull then
      print("Warning: Archive does not end with two Null blocks!")
    end
  end
end


--connect function parameters with actions
local actions = {
  c = function(files, options, ignoredObjects) --create
    tarFiles(files, options, "wb", ignoredObjects)
  end,
  r = function(files, options, ignoredObjects) --append
    tarFiles(files, options, "rb+", ignoredObjects)
  end,
  x = function(files, options, ignoredObjects) --extract
    untarFiles(files, options, extractingExtractors)
  end,
  t = function(files, options, ignoredObjects) --list
    untarFiles(files, options, listingExtractors)
  end,
}
--also add some aliases
actions["create"]  = actions.c
actions["append"]  = actions.r
actions["list"]    = actions.t
actions["extract"] = actions.x
actions["get"]     = actions.x

local debugEnabled = false

local function main(...)
  --variables containing the processed arguments
  local action, files
  --prepare arguments
  local params, options = shell.parse(...)
  --add stacktrace to output
  debugEnabled = options.debug
  --quick help
  if options.help then
    print(USAGE_TEXT)
    return
  end
  --determine executed function and options
  for option, value in pairs(options) do
    local isAction = actions[option]
    if isAction then
      assert(action == nil, ERRORS.multipleActions)
      action = isAction
      options[option] = nil
    end
  end
  assert(action ~= nil, ERRORS.missingAction)
  --prepare file names
  files = params
  --process options
  if options.v then
    options.verbose = true
  end
  if options.dir then
    assert(options.dir ~= true and options.dir ~= "", "Error: Invalid --dir value!")
    WORKING_DIRECTORY = shell.resolve(options.dir) or options.dir
    assert(WORKING_DIRECTORY ~= nil and WORKING_DIRECTORY ~= "", "Error: Invalid --dir value!")
  end
  if options.f or options.file then
    --use file for archiving
    --keep file names as they are
  else
    --use tape
    local tapeFile = {drive = component.tape_drive, pos = 0}
    do
      --check for Computronics bug
      local endInversionBug = false
      --step 1: move to the end of the tape
      local movedBy = assert(tapeFile.drive.seek(tapeFile.drive.getSize()))
      --step 2: check output of isEnd
      if tapeFile.drive.isEnd() ~= true then
        endInversionBug = true
      end
      --step 3: restore previous position
      assert(tapeFile.drive.seek(-movedBy) == -movedBy, "Error: Tape did not return to original position after checking for isEnd bug!")
      
      if endInversionBug then
        if options.verbose then
          print("tape_drive.isEnd() bug detected; adjusting...")
        end
        function tapeFile:isEnd()
          --This is a workaround for bugged versions of Computronics.
          return (not self.drive.isEnd()) or (not self.drive.isReady())
        end
      else
        function tapeFile:isEnd()
          --This does not work in bugged versions of Computronics.
          return self.drive.isEnd()
        end
      end
    end
    --create some kind of "tape stream" with limited buf sufficient functionality
    function tapeFile:lines(byteCount)
      return function()
        return self:read(byteCount)
      end
    end
    function tapeFile:read(byteCount)
      if self:isEnd() then
        return nil
      end
      local data = self.drive.read(byteCount)
      self.pos = self.pos + #data
      return data
    end
    function tapeFile:write(text)
      self.drive.write(text)
      self.pos = self.pos + #text
      if self:isEnd() then
        return nil, "Error: Reached end of tape!"
      else
        return self
      end
    end
    function tapeFile:seek(typ, pos)
      local toSeek
      if typ == "set" then
        toSeek = pos - self.pos
      elseif typ == "cur" then
        toSeek = pos
      end
      local movedBy = 0
      if toSeek ~= 0 then
        movedBy = self.drive.seek(toSeek)
        self.pos = self.pos + movedBy
      end
      if movedBy == toSeek then
        return self.pos
      else
        return nil, "Error: Unable to seek!"
      end
    end
    --add tape before first file
    table.insert(files, 1, tapeFile)
  end
  if options.h then
    options.dereference = true
  end
  
  --prepare list of ignored objects, default is the current directory and the target file if applicable
  local ignoredObjects = {}
  ignoredObjects[WORKING_DIRECTORY] = true
  if options.exclude then
    --";" is used as a separator
    for excluded in options.exclude:gmatch("[^%;]+") do
      ignoredObjects[shell.resolve(excluded) or excluded] = "strict"
    end
  end
  
  assert(#files > 0, ERRORS.missingFiles)
  --And action!
  action(files, options, ignoredObjects)
end

--adding stack trace when --debug is used
local function errorFormatter(msg)
  msg = msg:gsub("^[^%:]+%:[^%:]+%: ","")
  if debugEnabled then
    --add traceback when debugging
    return debug.traceback(msg, 3)
  end
  return msg
end

local ok, msg = xpcall(main, errorFormatter, ...)
if not ok then
  io.stdout:write(msg)
end
