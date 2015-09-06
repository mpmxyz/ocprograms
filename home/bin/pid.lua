-----------------------------------------------------
--name       : bin/pid.lua
--description: starting, debugging and stopping PID controllers
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/558-pid-pid-controllers-for-your-reactor-library-included/
-----------------------------------------------------

--loading libraries
local shell=require("shell")
local serialization=require("serialization")
local pid=require("pid")
local values = require("mpm.values")

--removes the directory part from the given file path
local function stripDir(file)
  return string.gsub(file,"^.*%/","")
end

local function printUsage()
  print([[
Usage: pid <action> [options] file or id [var=value or =var ...] [--args ...]
 action     what it does
   run        loads the given file as a controller and starts it
   load       loads the given file as a controller but doesn't start it
   update     updates the controller with the given id
   unload     stops and unregisters the controller with the given id
   start      (re-)starts the controllers with the given ids
   stop       stops the controllers with the given ids
   debug      displays debug info of the controllers with the given ids]])
end



--loads a controller from a given source file
--The file is loaded with a custom environment which combines the normal environment with a controller table.
--Writing access is always redirected to the controller table.
--Reading access is first redirected to the controller and, if the value is nil, it's redirected to the normal environment.
local function loadFile(file, start, subArgs)
  local data={}
  --custom environment
  --reading: 1. controller, 2. _ENV
  --writing: controller only
  local env=setmetatable({},{
    __index=function(_,k)
      local value=data[k]
      if value~=nil then
        return value
      end
      return _ENV[k]
    end,
    __newindex=data,
  })
  --load and execute the file
  assert(loadfile(file,"t",env))(table.unpack(subArgs, 1, subArgs.n)) --TODO: add parameters
  data.id = data.id or stripDir(file)
  data._ENV = data
  --initializes the controller but doesn't start it if loadOnly is true
  --the previous controller with the same id is stopped
  return pid.new(data, nil, start, true), data.id
end

--a quick and dirty PID debugger
local function runMonitor(controllers, loadedIDs)
  --load libraries
  local component = require("component")
  local term = require("term")
  --get screen size
  local width,height = component.gpu.getResolution()
  local maxControllers = math.floor(height / 5)
  --limitting the number of displayed controllers
  controllers[maxControllers + 1] = nil
  local init = "Initializing..."
  --drawing loop; exit via interrupt
  while true do
    term.setCursor(1,1)
    term.clear()
    for i, controller in ipairs(controllers) do
      --removing some boilerplate code by moving all line width adjustments here
      local function printf(fstring, ...)
        local text = string.format(fstring, ...)
        if #text < width then
          text=text..(" "):rep(width-1-#text)
        else
          text=text:sub(1, width)
        end
        print(text)
      end
      --display controller information
      local info = controller.info
      printf("ID:       %s", loadedIDs[i])
      if info then
        printf("Target:   %+d", info.target)
        printf("Current:  %+d", info.value)
        printf("Error:    %+d", info.error)
        printf("change/s: %s" , info.derror and ("%+d"):format(info.derror) or init)
        printf("PID parts:%+d %+d %+d", info.error * (info.p + info.i * info.dt), info.offset, info.derror and info.derror * info.d or 0)
        printf("Output:   %s" , info.output and ("%+d"):format(info.output) or init)
        print()
      else
        print(init)
        print()
        print()
        print()
        print()
        print()
        print()
      end
    end
    --screen updates 4 times a second
    os.sleep(0.25)
  end
end

local controllerGetters = {
  run     = function(file, subArgs
    return loadFile(shell.resolve(file), true,  subArgs)
  end,
  load    = function(file, subArgs)
    return loadFile(shell.resolve(file), false, subArgs)
  end,
  default = function(id)
    local controller = pid.get(id)
    if controller == nil then
      id = stripDir(id)
      controller = pid.get(id)
    end
    if controller == nil then
      error(("No controller %q found"):format(id), 0)
    end
    return controller, id
  end,
}

local proxyAccess = setmetatable({
  target    = {"target"},
  frequency = {"frequency"},
  p         = {"factors", "p"},
  i         = {"factors", "i"},
  d         = {"factors", "d"},
  min       = {"actuator", "min"},
  max       = {"actuator", "max"},
},{
  __index = function(_, k)
    if type(k) == "string" and k:sub(1, 1) == "." then
      k = k:sub(2, -1)
    end
    local t = {}
    for s in k:gmatch("[^%.]*") do
      if s ~= "" then
        t[#t + 1] = s
      end
    end
    return t
  end,
})
proxyAccess.tgt = proxyAccess.target
proxyAccess.t   = proxyAccess.target
proxyAccess.freq = proxyAccess.frequency
proxyAccess.f    = proxyAccess.frequency

local function getProxy(proxyName)
  local keys = proxyAccess[proxyName]
  if not keys then
    error(("No property %q"):format(tostring(proxyName)), 0)
  end
  return keys
end

local function accessor(obj, keys, value, writing, i)
  --index initialization for start of recursion
  i = i or 1
  --obj has to be a table
  if type(obj) ~= "table" then
    error(("Controller.%s is not a table"):format(table.concat(keys, ".", 1, i)), 0)
  end
  
  if keys[i + 1] then
    --continue recursively
    return accessor(obj[keys[i]], keys, value, writing, i + 1)
  else
    --reached target object
    if value == nil and not writing then
      --get value
      return obj[keys[i]]
    else
      --set value
      obj[keys[i]] = value
    end
  end
end

local function noop() end

local actions = {
  run    = noop,
  load   = noop,
  update = noop,
  unload = function(_, id)
    pid.remove(id, true)
  end,
  
  start  = function(controller)
    controller:start()
  end,
  stop   = function(controller)
    controller:stop()
  end,
}

--main function
local function main(parameters, options, subArgs)
  --check for minimum amount of parameters
  local actionName, fileOrID = parameters[1], parameters[2]
  if (not actionName) or (fileOrID == nil) then
    return printUsage()
  end
  if actionName == "debug" then
    --action "debug" displays the given controllers
    --get list of running controllers
    local loadedControllers={}
    local loadedIDs = {}
    for i, name in ipairs(parameters) do
      if i > 1 then
        --first id tried is the parameter itself, the second is the file part of the parameter
        local id = name
        local controller = pid.get(id)
        if controller == nil then
          id = stripDir(name)
          controller = pid.get(id)
        end
        if controller then
          loadedIDs[#loadedIDs + 1] = id
          loadedControllers[#loadedControllers + 1] = controller
        end
      end
    end
    --start display function
    runMonitor(loadedControllers, loadedIDs)
  else
    --get action
    local action = actions[actionName]
    if action == nil then
      print("Unknown action")
      return printUsage()
    end
    --get a controller
    local getter = controllerGetters[actionName] or controllerGetters.default
    local controller, id = getter(fileOrID, subArgs)
    --read or write values
    local i = 3
    while true do
      local param = parameters[i]
      if param == nil then
        break
      end
      --All extra parameters are expected to have the form "key=number" or "=key"
      local before, after = param:match("^(.-)%=(.*)$")
      if before == nil then
        --reading
        print(accessor(controller, getProxy(param)))        
      else
        --writing
        local value, msg = serialization.unserialize(after)
        if msg then
          error(msg, 0)
        end
        accessor(controller, getProxy(before), value, true)
      end
      --go to next parameter
      i = i + 1
    end
    
    action(controller, id)
  end
end

--parseing parameters and executing main function
local args = table.pack(...)
local usedArgs, subArgs = {n = 0}, {n = 0}
do
  local target = usedArgs
  for i = 1, args.n
    local arg = args[i]
    if (arg == "--args" or arg == "-a") and  then
      target = subArgs
    else
      target.n = target.n + 1
      target[target.n] = arg
    end
  end
end
local parameters, options = shell.parse(table.unpack(usedArgs, 1, usedArgs.n))
return main(parameters, options, subArgs)
