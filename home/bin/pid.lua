
--loading libraries
local pid=require("pid")
local shell=require("shell")

--removes the directory part from the given file path
local function stripDir(file)
  return string.gsub(file,"^.*%/","")
end

--loads a controller from a given source file
--The file is loaded with a custom environment which combines the normal environment with a controller table.
--Writing access is always redirected to the controller table.
--Reading access is first redirected to the controller and, if the value is nil, it's redirected to the normal environment.
local function loadFile(file, loadOnly)
  local controller={}
  --custom environment
  --reading: 1. controller, 2. _ENV
  --writing: controller only
  local env=setmetatable({},{
    __index=function(_,k)
      local value=controller[k]
      if value~=nil then
        return value
      end
      return _ENV[k]
    end,
    __newindex=controller,
  })
  --load and execute the file
  assert(loadfile(file,"t",env))()
  --initialize the controller
  return pid.new(controller, controller.id or stripDir(file), loadOnly == nil)
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
      end
    end
    --screen updates 4 times a second
    os.sleep(0.25)
  end
end


--main function
local function main(parameters, options)
  if #parameters == 0 then
    print([[
Usage: pid [option] files or ids...
  option     what it does
  [none]       loads the given files as controllers and starts them
  --load       loads the given files as controllers but doesn't start them
  --start      (re-)starts the controllers with the given ids
  --stop       stops the controllers with the given ids
  --debug      displays debug info of the controllers with the given ids
]])
    return
  end
  if options.target then
    assert(#parameters >= 1, "Usage: pid --target id [value]")
    local id = parameters[1]
    local newTarget = tonumber(parameters[2])
    local controller = pid.get(id) or pid.get(stripDir(id))
    assert(controller, "Controller not found!")
    if newTarget then
      controller.target = newTarget
    else
      print("Current Target:", controller.target)
    end
    return
  end
  
  --get list of running controllers
  local loadedControllers={}
  local loadedIDs = {}
  for _,name in ipairs(parameters) do
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
  
  if options.stop then
    --operation "stop" stops all given controllers
    for _,controller in ipairs(loadedControllers) do
      controller:stop()
    end
  elseif options.start then
    --operation "start" (re-)starts all given controllers
    for _, controller in ipairs(loadedControllers) do
      controller:start()
    end
  elseif options.unload then
    --stops and removes all given controllers
    for _, controller in ipairs(loadedControllers) do
      pid.remove(controller.id)
    end
  elseif options.debug then
    --operation "debug" displays the given controllers
    runMonitor(loadedControllers, loadedIDs)
  else
    --no operation loads the given files
    local loaded = {}
    for _,file in ipairs(parameters) do
      loaded[#loaded + 1] = loadFile(shell.resolve(file), options.load)
    end
    return loaded
  end
end

--parseing parameters and executing main function
local parameters, options = shell.parse(...)
return main(parameters, options)
