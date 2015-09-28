-----------------------------------------------------
--name       : lib/pid.lua
--description: a library for PID controllers that run in the background
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/558-pid-pid-controllers-for-your-reactor-library-included/
-----------------------------------------------------

--loading libraries
local event = require("event")
local libarmor = require("mpm.libarmor")
local values = require("mpm.values")

--the library table
local pid = {}
--obj -> timer
local running = {}
--id -> obj
local registry = {}
local reverseRegistry = {} --TODO: implement reverse registry
local protectedRegistry = libarmor.protect(registry)

--removes the directory part from the given file path
local function stripDir(file)
  return string.gsub(file,"^.*%/","")
end




--**TYPES AND VALIDATION**--

--[[
  pid.new(data, id, enable) -> controller
  Creates a pid controller using the given data table and returns a controller table.
  The controller table is connected to the data table via a __index metamethod.
  That allows for updates via a shared data object and local overrides by writing to individual controllers.
  For convenience it is also automaticly started unless enable is false. (default is true)
  Controllers can be registered globally using the id parameter. (or field; but the parameter takes priority)
  There can only be one controller with the same id. Existing controllers will be replaced.
  
  Here is a list of controller methods:
  name                            description
   start()                         starts the controller
   isRunning() -> boolean          returns true if it is running
   stop()                          stops the controller
   isValid()   -> boolean, string  returns true if the controller is valid, false and an error message if not
  
  This is the format the data table is expected to use.
  "value" types can either be a number or a getter function returning one.
  data={
    sensor=value,               --a function returning the value being controlled
    target=value,               --the value that the controlled value should reach
    actuator={                  --The actuator is the thing that is 'working' on your system.
      set=function(number),     --It is 'actuated' using this setter function.
      get=value or nil,         --For better jump starting capabilities it is recommended to also add a getter function.
      min=value or nil,         --Minimum and maximum values can also be set to define the range of control inputs to the actuator.
      max=value or nil,         --The limit can also be one sided. (e.g. from 0 to infinity)
      initial=value or nil,     --can be used as an alternative to the "get" field
    },
    factors={                   --These are the factors that define the behaviour of the PID controller. It has even got its name from them.
     p=value,                   --P: proportional, factor applied to the error (current value - target value)        is added directly          acts like a spring, increases tendency to return to target, but might leave some residual error
     i=value,                   --I: integral,     factor applied to the error before adding it to the offset value  the offset value is added  increases tendency to return to target and reduces residual error, but also adds some kind of inertia -> more prone to oscillations
     d=value,                   --D: derivative,   factor applied to the change of error per second                  is added directly          can be used to dampen instabilities caused by the other factors (needs smooth input values to work properly)
    },                          --The sum of all parts is the controller output.
    frequency=number,           --the update frequency in updates per second
    id = optional,              --the id used to register the controller
  }
  
  When the controller is active, it is also updating a debug info table:
  controller.info = {
    p=number,               --currently used P factor
    i=number,               --currently used I factor
    d=number,               --currently used D factor
    dt=number,              --current time interval between update cycles
    value=number,           --current sensor output
    target=number,          --current setpoint
    error=target-value,     --current error (defined as the given difference)
    lastError=number,       --error of last cycle (used to calculate D term)
    offset=number,          --current offset, the value of the I term 
    doffset=i * error * dt, --change in offset (this cycle)
    
    derror=(error-lastError) / dt,   --change in error since last cycle
    output=p*error+d*derror+offset,  --current output, sum of P, I and D terms
  }
]]
function pid.new(data, id, enable, stopPrevious)
  local controller = setmetatable({}, {__index = data})
  local lastError
  local offset
  local dt
  ---default controller
  function controller:doStep()
    --the info table can be used for monitoring and debugging of a system
    local info = {}
    --get constants
    local p = values.get(self.factors.p) or 0
    local i = values.get(self.factors.i) or 0
    local d = values.get(self.factors.d) or 0
    
    --get some information...
    local value        = values.get(self.sensor)
    local target       = values.get(self.target)
    --error(t)
    local currentError = target - value
    
    --access some actuator values
    local actuator   = self.actuator
    local controlMax = values.get(actuator.max)
    local controlMin = values.get(actuator.min)
    
    --some info values
    info.p  = p
    info.i  = i
    info.d  = d
    info.dt = dt
    info.value     = value
    info.target    = target
    info.error     = currentError
    info.lastError = lastError
    info.controlMin = controlMin
    info.controlMax = controlMax
    
    local output
    if lastError then
      --calculate error'(t)
      local derror = (currentError - lastError) / dt
      --calculate output value
      local valueP = p * currentError
      local valueI = offset + i * dt * currentError
      local valueD = d * derror
      output = valueP + valueI + valueD
      --save raw values
      info.rawP = valueP
      info.rawI = valueI
      info.rawD = valueD
      info.rawSum = output
      
      --now clamp it within range and decide if it is safe to do the integration
      local doIntegration = true
      local doffset = i * currentError * dt
      if controlMin and output < controlMin then
        output = controlMin
        doIntegration  = (doffset > 0)
      elseif controlMax and output > controlMax then
        output = controlMax
        doIntegration  = (doffset < 0)
      end
      if doIntegration then
        --integrate
        offset = offset + doffset
      else
        --don't integrate: reset doffset for correct info table values
        doffset = 0
      end
      --more info values
      info.doffset = doffset
      info.derror  = derror
    else
      --initialize (1/2): determining an initial output
      local defaultControl
      if controlMin then
        defaultControl = controlMax and ((controlMin+controlMax)/2) or controlMin
      else
        defaultControl = controlMax or 0
      end
      output = values.get(actuator.get or actuator.initial or defaultControl)
      --initialize (2/2): calculating a good offset to reflect the current state
      --output = p * currentError + offset + d * 0
      --offset = output - p * currentError
      offset = (output - p * currentError)
      
      --more info values
      info.doffset = 0
      info.derror  = 0
    end
    
    --'return' output value
    actuator.set(output)
    
    --remember last error to calculate error'
    lastError = currentError
    
    --more info values
    info.output = output
    info.offset = offset
    --save info table
    self.info = info
  end
  
  ---managing controller execution (start/stop etc.)
  local function callback()
    --remove controller from running list
    running[controller] = nil
    --calculate new delta t in seconds
    dt = 1.0 / values.get(controller.frequency)
    --calculate output
    controller:doStep()
    --initiate next step; this part is never reached if controller execution failed
    running[controller] = event.timer(dt, callback)
  end
  function controller:start()
    --avoid multiple timers running for one pid controller
    self:stop()
    --avoid run time errors by doing a small check before starting
    --The controller remains stopped if this fails. 
    self:assertValid()
    --run controller
    callback()
  end
  function controller:isRunning()
    return running[self] ~= nil
  end
  function controller:stop()
    local timerID = running[self]
    if timerID then
      --timer is running
      --stopping...
      event.cancel(timerID)
      running[self] = nil
    end
  end
  
  ---validation
  function controller:isValid()
    return pcall(self.assertValid, self)
  end
  function controller:assertValid()
    --checking controller contents (errors during execution are hidden in event.log)
    values.checkTable(self.actuator,        "actuator")
    values.checkCallable(self.actuator.set, "actuator.set")
    values.checkNumber(self.actuator.get,   "actuator.get", true)
    values.checkNumber(self.actuator.min,   "actuator.min", true)
    values.checkNumber(self.actuator.max,   "actuator.max", true)
    values.checkTable(self.factors,         "factors")
    values.checkNumber(self.factors.p,      "factors.p",    true)
    values.checkNumber(self.factors.i,      "factors.i",    true)
    values.checkNumber(self.factors.d,      "factors.d",    true)
    --The library wouldn't have trouble without those factors.
    --But it wouldn't make sense to use it that way.
    assert((self.factors.p or self.factors.i or self.factors.d) ~= nil, "All pid factors are nil")
    values.checkNumber(self.target,    "target")
    values.checkNumber(self.sensor,    "sensor")
    values.checkNumber(self.frequency, "frequency")
  end
  ---controller registry
  controller.register = pid.register
  
  ---initialization
  local previous, previousIsRunning
  if id or controller.id then
    previous, previousIsRunning = controller:register(stopPrevious, id)
  end
  if enable then
    controller:start()
  end
  return controller
end

--loads a controller from a given source file
--The file is loaded with a custom environment which combines the normal environment with a controller table.
--Writing access is always redirected to the controller table.
--Reading access is first redirected to the controller and, if the value is nil, it's redirected to the normal environment.
function pid.loadFile(file, enable, ...)
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
  assert(loadfile(file,"t",env))(...)
  data.id = data.id or stripDir(file)
  data._ENV = data
  --initializes the controller but doesn't start it if loadOnly is true
  --the previous controller with the same id is stopped
  return pid.new(data, nil, enable, true), data.id
end


---controller registry
--gets the PID controller for the given id
function pid.get(id)
  return registry[id]
end
--registers a controller
--TODO: description
function pid.register(self, stopPrevious, id)
  if id == nil and self ~= nil then
    id = self.id
  end
  assert(id ~= nil, "Unable to register: id is nil")
  --add controller to registry
  local previous = registry[id]
  registry[id]   = self
  --stop previous controller if wanted
  local previousIsRunning = previous and previous:isRunning() or false
  if previous and stopPrevious and previousIsRunning then
    previous:stop()
  end
  return previous, previousIsRunning
end
--
function pid.remove(id, stop)
  return pid.register(nil, stop, id)
end
--TODO: description
--returns a read only table
function pid.registry()
  return protectedRegistry
end

return pid
