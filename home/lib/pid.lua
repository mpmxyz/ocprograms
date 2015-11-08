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
local protectedRegistry = libarmor.protect(registry)
--obj -> id
local reverseRegistry = {}

--removes the directory part from the given file path
local function stripDir(file)
  return string.gsub(file,"^.*%/","")
end


--[[
  pid.new(controller:table, [id, enable:boolean, stopPrevious:boolean]) -> controller:table, previous:table, previousIsRunning:boolean
  Creates a pid controller by adding methods to the given controller table.
  For convenience it is also automaticly started unless enable is false. (default is true)
  Controllers can be registered globally using the id parameter. (or field; but the parameter takes priority)
  There can only be one controller with the same id. Existing controllers will be replaced. (and stopped if stopPrevious is true)
  
  Here is a list of controller methods:
  name                            description
   start()                         starts the controller
   isRunning() -> boolean          returns true if it is running
   stop()                          stops the controller
   isValid()   -> boolean, string  returns true if the controller is valid, false and an error message if not
  
  This is the format the data table is expected to use.
  "value" types can either be a number or a getter function returning one.
  controller={
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
    controlMin=number,      --lower limit of control output
    controlMax=number,      --upper limit of control output
    rawP=p*currentError,        --p component of sum
    rawI=old offset+i*dt*error, --i component of sum
    rawD=d*derror,              --d component of sum
    rawSum=rawP+rawI+rawD,  --sum of PID components (limits not applied)
    
    doffset=i*dt*error or 0,--change in offset (this cycle); can be forced to 0 when output value is on the limit
    offset=number,          --new offset, after adding doffset
    
    derror=(error-lastError) / dt,   --rate of change of error since last cycle
    output=p*error+d*derror+offset,  --rawSum with output limits applied
  }
]]
function pid.new(controller, id, enable, stopPrevious)
  local lastError
  local offset
  --controller:doStep(dt:number)
  --runs the controller calculation for the given time interval
  function controller:doStep(dt)
    checkArg(1, dt, "number")
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
    info.value      = value
    info.target     = target
    info.error      = currentError
    info.lastError  = lastError
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
      info.rawP   = valueP
      info.rawI   = valueI
      info.rawD   = valueD
      info.rawSum = output
      
      --now clamp it within range and decide if it is safe to do the integration
      local doIntegration = true
      local doffset = i * dt * currentError
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
      --initialize (2/2): calculating an offset to reflect the current state
      --output = p * currentError + offset + d * 0
      --offset = output - p * currentError
      offset = (output - p * currentError)
      
      
      --more info values
      info.rawP    = p * currentError
      info.rawI    = offset
      info.rawD    = 0
      info.rawSum  = output
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
  
  --controller:forceOffset(newOffset:number)
  --changes the internal offset of the controller (in case you feel the need for a manual override...)
  function controller:forceOffset(newOffset)
    checkArg(1, newOffset, "number")
    offset = newOffset
  end
  
  ---managing controller execution (start/stop etc.)
  local function callback()
    --remove controller from running list
    running[controller] = nil
    --calculate new delta t in seconds
    local dt = 1.0 / values.get(controller.frequency)
    --calculate output
    controller:doStep(dt)
    --initiate next step; this part is never reached if controller execution failed
    running[controller] = event.timer(dt, callback)
  end
  --controller:start()
  --starts the controller
  function controller:start()
    --avoid multiple timers running for one pid controller
    self:stop()
    --avoid run time errors by doing a small check before starting
    --The controller remains stopped if this fails. 
    self:assertValid()
    --run controller
    callback()
  end
  --controller:isRunning() -> boolean
  --returns true if the controller is already running
  function controller:isRunning()
    return running[self] ~= nil
  end
  --controller:stop()
  --stops the controller
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
  --controller:isValid() -> true or false, errorText:string
  --returns true if the controller seems to be valid
  --returns false and an error message if the controller is invalid
  function controller:isValid()
    return pcall(self.assertValid, self)
  end
  --controller:assertValid()
  --errors if the controller is not valid
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
  --controller:getID() -> id
  --see pid.getID
  controller.getID    = pid.getID
  --controller:register([stopPrevious:boolean, id]) -> old pid:table, wasRunning:boolean
  --see pid.register
  controller.register = pid.register
  --controller:remove([stop:boolean]) -> wasRunning:boolean
  --see pid.remove
  controller.remove   = pid.remove
  
  ---initialization
  local previous, previousIsRunning
  if id or controller.id then
    previous, previousIsRunning = controller:register(stopPrevious, id)
  end
  if enable then
    controller:start()
  end
  return controller, previous, previousIsRunning
end

--pid.loadFile(file, enable, ...) -> pid:table, id
--loads a controller from a given source file
--The file is loaded with a custom environment which combines the normal environment with a controller table.
--Writing access is always redirected to the controller table.
--Reading access is first redirected to the controller and, if the value is nil, it's redirected to the normal environment.
--Additional parameters are forwarded when the main chunk of the file is called.
function pid.loadFile(file, enable, ...)
  checkArg(1, file, "string")
  checkArg(2, enable, "boolean", "nil")
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
  --initialize controller
  return pid.new(data, nil, enable, true), data.id
end


---controller registry
--pid.get(id) -> controller:table
--returns the controller registered with the given id
function pid.get(id)
  return registry[id]
end
--pid.getID(controller:table) -> id
--gets the id the given PID controller is registered with
function pid.getID(self)
  checkArg(1, self, "table")
  return reverseRegistry[self]
end
--pid.register(controller:table, [stopPrevious:boolean, id]) -> old pid:table, wasRunning:boolean
--registers a controller using either the id field as a key or the id parameter given to the function
--A controller can only be registered once and only one controller can be registered with a given id.
--If one tries to register a controller multiple times it is only registered with the last id.
--If one tries to register multiple controllers on the same id only the last controller stays.
--You can order the controller being previously registered with the same id to stop using the parameter "stop".
function pid.register(self, stopPrevious, id)
  checkArg(1, self, "table", "nil")
  checkArg(2, stopPrevious, "boolean", "nil")
  if id == nil and self ~= nil then
    id = self.id
  end
  assert(id ~= nil, "Unable to register: id is nil")
  --remove previous controller from reverse registry
  local previous = registry[id]
  if previous then
    reverseRegistry[previous] = nil
  end
  if self then
    --remove previous occurences of the new controller
    local previousID = reverseRegistry[self]
    if previousID ~= nil then
      registry[previousID] = nil
    end
    --register current controller in the reverse registry
    reverseRegistry[self] = id
  end
  --update registry
  registry[id]   = self
  
  --convenience: stop previous controller if wanted
  local previousIsRunning = previous and previous:isRunning() or false
  if previous and stopPrevious and previousIsRunning then
    previous:stop()
  end
  return previous, previousIsRunning
end

--pid.removeID(id, [stop:boolean]) -> old pid:table, wasRunning:boolean
--removes the controller with the given id from the registry
--You can also order the controller to stop using the parameter "stop".
function pid.removeID(id, stop)
  checkArg(2, stop, "boolean", "nil")
  return pid.register(nil, stop, id)
end

--pid.remove(controller:table, [stop:boolean]) -> wasRunning:boolean
--removes the given controller from the registry
--You can also order the controller to stop using the parameter "stop".
function pid.remove(self, stop)
  checkArg(1, self, "table")
  checkArg(2, stop, "boolean", "nil")
  local id = pid.getID(self)
  local crossCheck, wasRunning = pid.register(nil, stop, id)
  assert(crossCheck == self, "Cross check failed!")
  return wasRunning
end

--pid.registry() -> proxy:table
--returns a read only proxy of the registry
--Read only access ensures that the internal reverse registry stays updated.
function pid.registry()
  return protectedRegistry
end

return pid
