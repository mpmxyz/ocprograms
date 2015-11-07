-----------------------------------------------------
--name       : lib/mpm/lib.lua
--description: allows iteration of all files for a given library path
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------
local filesystem
do
  local ok
  ok, filesystem = pcall(require, "filesystem")
  if not ok then
    --compatibility as a standalone script without OpenComputers: requires Lua File System
    local lfs = require("lfs")
    filesystem = {
      list = lfs.dir,
      exists = function(path)
        return lfs.attributes(path) ~= nil
      end,
      isDirectory = function(path)
        local attributes = lfs.attributes(path)
        return attributes and (attributes.mode == "directory") or false
      end,
      concat = function(a, b)
        return a .. "/" .. b
      end,
    }
  end
end

return {
  list = function(path, includeWorkingDir, includeDuplicates)
    if checkArg then
      checkArg(1, path,              "string",  "nil")
      checkArg(2, includeWorkingDir, "boolean", "nil")
      checkArg(3, includeDuplicates, "boolean", "nil")
    end
    path = path or package.path
    
    local knownLibs = {}
    
    local function findLibs(path, dir, prefix, ext, subPath, libPrefix)
      if path then
        dir, prefix, ext, subPath = path:match("^(.-)([^/]*)%?([^/]*)(.-)$")
        libPrefix = ""
        if (dir:sub(1, 2) ~= "./" and dir ~= "") and not (filesystem.exists(dir) and filesystem.isDirectory(dir)) then
          return
        end
      end
      --don't search working dir
      if dir and prefix and ext and ((dir:sub(1, 2) ~= "./" and dir ~= "") or includeWorkingDir) then
        for file in filesystem.list(dir) do
          if file:sub(1, #prefix) == prefix then
            if file:sub(-#ext, -1) == ext then
              local libname = libPrefix .. file:sub(#prefix + 1, -#ext - 1)
              local absolutePath = dir .. file .. subPath:sub(2, -1)
              if absolutePath:sub(1, 1) ~= "/" then
                absolutePath = filesystem.concat(os.getenv("PWD") or "", absolutePath)
              end
              if filesystem.exists(absolutePath) and not filesystem.isDirectory(absolutePath) then
                if not knownLibs[libname] then
                  if not includeDuplicates then
                    knownLibs[libname] = true
                  end
                  coroutine.yield(libname, absolutePath)
                end
              end
            end
          end
          if file:sub(-1, -1) == "/" then
            --directory: recursion
            --(expects "dir" to end with a slash if it isn't empty
            findLibs(nil, dir .. file, prefix, ext, subPath, libPrefix .. file:sub(1, -2) .. ".")
          end
        end
      end
    end
    
    return coroutine.wrap(function()
      for path in path:gmatch("[^;]+") do
        findLibs(path)
      end
      coroutine.yield()
    end)
  end,
}
