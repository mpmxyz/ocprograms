-----------------------------------------------------
--name       : lib/pid.lua
--description: a library for PID controllers that run in the background
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/558-pid-pid-controllers-for-your-reactor-library-included/
-----------------------------------------------------

--loading libraries
local event = require("event")
local values = require("mpm.values")

--the library table
local pid = {}
--obj -> timer
local running = {}
--id -> obj
local registry = {}

--**TYPES AND VALIDATION**--

--[[
  pid.new(controller, id, enable) -> controller
  Adds some methods to the given table to make it a full pid controller.
  It is also automaticly started unless enable is false. (default is true)
  For convenience it also returns the controller table given as the first parameter.
  Controllers can be registered globally using the id parameter. (or field; but the parameter takes priority)
  There can only be one controller with the same id. Existing controllers will be replaced.
  
  Here is a list of methods added:
  name                    description
   start()                 starts the controller
   isRunning() -> boolean  returns true if it is running
   stop()                  stops the controller
  
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
function pid.new(data, id, enable)
  local lastError
  local offset
  local dt
  
  local function callback()
    local info = {}
    --get constants
    local p = values.get(data.factors.p) or 0
    local i = values.get(data.factors.i) or 0
    local d = values.get(data.factors.d) or 0
    
    --get some information...
    local value        = values.get(data.sensor)
    local target       = values.get(data.target)
    --error(t)
    local currentError = target - value
    
    --some info values
    info.p  = p
    info.i  = i
    info.d  = d
    info.dt = dt
    info.value     = value
    info.target    = target
    info.error     = currentError
    info.lastError = lastError
    
    --access some actuator values
    local actuator   = data.actuator
    local controlMax = values.get(actuator.max)
    local controlMin = values.get(actuator.min)
    
    if lastError then
      --calculate error'(t)
      local errorDiff = (currentError - lastError) / dt
      --calculate output value
      local currentControl = (p + i * dt) * currentError + d * errorDiff + offset
      --now clamp it within range and decide if it is safe to do the integration
      local doIntegration = true
      local doffset = i * currentError * dt
      if controlMin and currentControl < controlMin then
        currentControl=controlMin
        doIntegration = (doffset > 0)
      elseif controlMax and currentControl > controlMax then
        currentControl=controlMax
        doIntegration = (doffset < 0)
      end
      if doIntegration then
        --integrate
        offset = offset + doffset
      end
      --'return' output value
      actuator.set(currentControl)
      
      --more info values
      info.doffset = doffset
      info.derror  = errorDiff
      info.output  = currentControl
    else
      --initialize: calculating a good offset to reflect the current state
      --currentControl = p * currentError + offset + d * 0
      --offset = currentControl - p * currentError
      local defaultControl
      if controlMin then
        defaultControl = controlMax and ((controlMin+controlMax)/2) or controlMin
      else
        defaultControl = controlMax or 0
      end
      local currentControl = values.get(actuator.get or actuator.initial or defaultControl)
      local currentControl = values.get(actuator.get or actuator.initial or defaultControl)
      offset = (currentControl - p * currentError)
    end
    
    --remember last error to calculate error'
    lastError = currentError
    
    --more info values
    info.offset = offset
    --save info data
    data.info=info
  end
  function data:start()
    --avoid multiple timers running for one pid controller
    self:stop()
    --calculate dt in seconds
    dt = 1.0 / self.frequency
    --start timer
    running[self] = event.timer(dt, callback, math.huge)
  end
  function data:isRunning()
    return running[self] ~= nil
  end
  function data:stop()
    local timerID = running[self]
    if timerID then
      --timer is running
      --stopping...
      event.cancel(timerID)
      running[self] = nil
    end
  end

  --checking data contents (errors during execution are hidden in event.log)
  values.checkTable(data.actuator,        "actuator")
  values.checkCallable(data.actuator.set, "actuator.set")
  values.checkNumber(data.actuator.get,   "actuator.get", true)
  values.checkNumber(data.actuator.min,   "actuator.min", true)
  values.checkNumber(data.actuator.max,   "actuator.max", true)
  values.checkTable(data.factors,         "factors")
  values.checkNumber(data.factors.p,      "factors.p",    true)
  values.checkNumber(data.factors.i,      "factors.i",    true)
  values.checkNumber(data.factors.d,      "factors.d",    true)
  --The library wouldn't have trouble without those factors.
  --But it wouldn't make sense to use it that way.
  assert((data.factors.p or data.factors.i or data.factors.d) ~= nil, "All factors are nil!")
  values.checkNumber(data.target,         "target")
  values.checkNumber(data.sensor,         "sensor")
  values.checkNumber(data.frequency,      "frequency")
  --PID registry
  return pid.set(data, id, enable)
end
--registers the PID controller for the given id
function pid.set(controller, id, enable)
  if id == nil then
    id = controller.id
  elseif controller == nil then
    controller = registry[id]
  end
  assert(type(controller) == "table", "Expected controller table!")
  if id ~= nil then
    pid.remove(id)
    registry[id] = controller
  end
  if enable then
    controller:start()
  end
  return controller
end
--gets the PID controller for the given id
function pid.get(id)
  return registry[id]
end
--stops and removes the pid controller with the given id
function pid.remove(id)
  local oldController = registry[id]
  if oldController then
    oldController:stop()
  end
  registry[id] = nil
  return oldController
end

return pid
