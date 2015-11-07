-----------------------------------------------------
--name       : bin/gpid.lua
--description: starting, debugging and stopping PID controllers
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/558-pid-pid-controllers-for-your-reactor-library-included/
-----------------------------------------------------
--
--<<<  reactor.pid                  >>>  [Add New]
----Settings--
--Status           ID               Frequency
-- Enabled          reactor.pid      +12345678.12
--Target           Current          Error
-- +12345678.12  -  +12345678.12  =  +12345678.12
--Proportional     Integral         Derivative
-- +12345678.12     +12345678.12     +12345678.12
--Minimum          Maxmimum         Default
-- +12345678.12     +12345678.12     +12345678.12
----Calculation--               |    |    |           <- "|" gibt den ursprünglichen Wertebereich an
--offset +12345678.12    -[ <<<<<<<<<<          ]+
--P      +12345678.12    -[ >>>                 ]+
--D      +12345678.12    -[   >>>>>>>>>>>       ]+
--sum    +12345678.12     /-----/         \-----\
--output +12345678.12     [                   X ]
--


local component = require("component")
local event     = require("event")
local shell     = require("shell")
local term      = require("term")

local libarmor = require("mpm.libarmor")
local values   = require("mpm.values")

local qui      = require("mpm.qui")
local quidgets = require("mpm.quidgets")
local qselect  = require("mpm.qselect")
local qevent   = require("mpm.qevent")

local pid = require("pid")


local uiObject

local function onError(msg)
  local w, h = component.gpu.getResolution()
  local oldForeground = component.gpu.setForeground(0xFF0000)
  local oldBackground = component.gpu.setBackground(0x000000)
  component.gpu.fill(1, 1, w, 1, " ")
  term.setCursor(1, 1)
  print(msg)
  component.gpu.setForeground(oldForeground)
  component.gpu.setBackground(oldBackground)
  os.sleep(3)
  uiObject:redraw(1, 1, nil, 1)
end

local CURRENT_PID

local function setPID(id)
  --find pid for the given id
  local newPID = pid.get(id)
  if newPID then
    --found one: changing view...
    CURRENT_PID = newPID
  end
end

local function getSortedIDs()
  --get copy of pid registry
  local registry = pid.registry()
  --create list of string ids
  local ids = {n = 0}
  for k, v in pairs(registry) do
    --TODO: allow all other types by adding a custom sorting method
    if type(k) == "string" then
      ids.n = ids.n + 1
      ids[ids.n] = k
    end
  end
  --sort ids
  table.sort(ids)
  --create inverse table
  local inv = {}
  for k, v in ipairs(ids) do
    inv[v] = k
  end
  return ids, inv
end

local function nextPID()
  local ids, inv = getSortedIDs()
  if ids.n > 0 then
    --move to next element in list
    local index = (inv[pid.getID(CURRENT_PID or {})] or 0) % ids.n + 1
    CURRENT_PID = pid.get(ids[index])
  else
    --empty list, select nil
    CURRENT_PID = nil
  end
end
local function previousPID()
  local ids, inv = getSortedIDs()
  if ids.n > 0 then
    --move to previous element in list
    local index = ((inv[pid.getID(CURRENT_PID or {})] or 1) - 2) % ids.n + 1
    CURRENT_PID = pid.get(ids[index])
  else
    --empty list, select nil
    CURRENT_PID = nil
  end
end

local function removePID()
  if CURRENT_PID then
    local oldPID = CURRENT_PID
    --select next PID controller
    nextPID()
    --remove old controller
    pid.remove(oldPID, true)
    if CURRENT_PID == oldPID then
      --It looks like we removed the last controller.
      CURRENT_PID = nil
    end
  end
end
local function newPID(file, ...)
  --create controller
  local controller, id = pid.loadFile(file, false, ...)
  if controller and id then
    --change view
    CURRENT_PID = controller
  end
end
local function changeID(newID)
  --change pid.id
  CURRENT_PID.id = newID
  --adding new registry entry
  pid.register(CURRENT_PID, true)
end

nextPID()

local function numberLabel(keys)
  local obj = {}
  function obj.text()
    if CURRENT_PID then
      return tostring(values.get(CURRENT_PID, nil, table.unpack(keys)))
    else
      return ""
    end
  end
  return obj
end
local function numberBox(keys, setter)
  local obj = numberLabel(keys)
  function obj:onEdit(text)
    local value = tonumber(text)
    if value and CURRENT_PID then
      if setter then
        setter(value)
      else
        values.set(CURRENT_PID, value, false, table.unpack(keys))
      end
    end
  end
  return quidgets.textbox(obj)
end

local GRAPH_LINES = {}
local function newGraphLine(lineName)
  return {init = function(self)
    GRAPH_LINES[lineName] = self
    function self:fill(from, to, minimum, maximum, char, reversedChar)
      local width = self.width
      --from ? to
      if from > to then
        from, to = to, from
        char = reversedChar or char
      end
      --from <= to
      from = math.min(math.max(from, minimum), maximum)
      to   = math.min(math.max(to  , minimum), maximum)
      --minimum <= from <= to <= maximum
      
      -- minimum -> 0
      -- maximum -> 1
      from = (from - minimum) / (maximum - minimum)
      to   = (to   - minimum) / (maximum - minimum)
      
      --interpolation within 1..width
      local indexFrom = math.floor(from * (width - 1) + 1.5)
      local indexTo   = math.floor(to   * (width - 1) + 1.5)
      
      --calculate size of all pieces
      local prefixLength = indexFrom - 1
      local infixLength = indexTo - indexFrom + 1
      local suffixLength = width - indexTo
      
      --combine all pieces
      self.text = (" "):rep(prefixLength) .. char:rep(infixLength) .. (" "):rep(suffixLength)
    end
  end}
end
local function updateGraph()
  --clear
  for _, v in pairs(GRAPH_LINES) do
    v.text = ("#"):rep(v.width)
  end
  --debug output available?
  local info = CURRENT_PID and CURRENT_PID.info
  if info then
    local minOutput, maxOutput = info.controlMin, info.controlMax
    local output = info.output
    if minOutput and maxOutput and output then
      local rawP, rawI, rawD = info.rawP, info.rawI, info.rawD
      local rawSum = info.rawSum
      if rawP and rawI and rawD and rawSum then
        local rawPI = rawP + rawI
        --TODO: zoom to highlight rawI, rawPI and rawSum?
        GRAPH_LINES.offset:fill(0,     rawI,   minOutput, maxOutput, ">", "<")
        GRAPH_LINES.p     :fill(rawI,  rawPI,  minOutput, maxOutput, ">", "<")
        GRAPH_LINES.d     :fill(rawPI, rawSum, minOutput, maxOutput, ">", "<")
        --TODO: transition?
        GRAPH_LINES.transition:fill(info.output, info.output, minOutput, maxOutput, "|")
      end
      GRAPH_LINES.output:fill(output, output, minOutput, maxOutput, "X")
    end
  end
end

local function confirm(obj)
  return true
end

local ui = [[
*l* *selection************ *r*  [*new***] [*rem**]
--Settings--
Status           ID               Frequency
 *toggle**        *changeid***     *frequency**
Target           Current          Error
 *target*****  -  *current****  =  *error******
Proportional     Integral         Derivative
 *p**********     *i**********     *d**********
Minimum          Maxmimum         Default
 *min********     *max********     *default****
--Calculation--
offset *valOffset**    -[*imageOffset***********]+
P      *valP*******    -[*imageP****************]+
D      *valD*******    -[*imageD****************]+
sum    *valSum*****      *imageTransition*******
output *valOutput**     [*imageOutput***********]
]]

uiObject = qui.load(ui, {
  l = {
    text = "<<<",
    onClick = previousPID,
  },
  selection = quidgets.textbox{
    text = function()
      return CURRENT_PID and tostring(pid.getID(CURRENT_PID)) or ""
    end,
    onEdit = function(self, id)
      setPID(id)
    end,
  },
  r = {
    text = ">>>",
    onClick = nextPID,
  },
  new = {
    text = "Add New",
    onClick = function(self)
      local function read(what, ...)
        local w, h = self.lastGPU.getResolution()
        self.lastGPU.fill(1, 1, w, 1, " ")
        term.setCursor(1, 1)
        term.write(what)
        local value = term.read(...)
        uiObject:redraw(1, 1, nil, 1)
        return value and value:match("^[^\r\n]*")
      end
      --get file path, TODO: autocomplete
      local file = read("file: ")
      if file and file ~= "" then
        local args, maxn = {}, 2
        while true do
          --get arguments, TODO: autocomplete/history
          local text = read("args: ")
          if text == nil then
            return
          end
          local f, err = load("return " .. text, nil, libarmor.protect(_ENV))
          if f then
            args = {pcall(f)}
            if not args[1] then
              return onError(args[2])
            end
            for k in pairs(args) do
              maxn = math.max(maxn, k)
            end
            break
          else
            return onError(f)
          end
        end
        local ok, err = pcall(newPID, shell.resolve(file), table.unpack(args, 2, maxn))
        if not ok then
          onError(err)
        end
        uiObject:redraw()
      end
    end,
  },
  rem = {
    text = "Remove",
    onClick = function(self)
      if confirm(self) then
        removePID()
      end
    end,
  },
  toggle = {
    text = function()
      return CURRENT_PID and (CURRENT_PID:isRunning() and " enabled" or "disabled") or ""
    end,
    fgColor = function()
      return CURRENT_PID and (CURRENT_PID:isRunning() and 0x44FF44 or 0xFF4444) or 0xFFFFFF
    end,
    bgColor = 0x000000,
    onClick = function()
      if CURRENT_PID then
        if CURRENT_PID:isRunning() then
          CURRENT_PID:stop()
        else
          CURRENT_PID:start()
        end
      end
    end,
  },
  changeid = quidgets.textbox{
    text = function()
      return CURRENT_PID and tostring(pid.getID(CURRENT_PID)) or ""
    end,
    onEdit = function(self, newID)
      if CURRENT_PID then
        changeID(newID)
      end
    end,
  },
  frequency = numberBox{"frequency"},
  target  = numberBox{"target"},
  current = numberLabel{"sensor"},
  error   = numberLabel{"info", "error"},
  p = numberBox{"factors", "p"},
  i = numberBox{"factors", "i"},
  d = numberBox{"factors", "d"},
  min = numberBox{"actuator", "min"},
  max = numberBox{"actuator", "max"},
  default = numberBox{"actuator", "initial"},
  valOffset = numberBox(
    {"info", "offset"},
    function(value)
      if CURRENT_PID and CURRENT_PID.forceOffset then
        CURRENT_PID:forceOffset(value)
      end
    end
  ),
  valP      = numberLabel{"info", "rawP"},
  valD      = numberLabel{"info", "rawD"},
  valSum    = numberLabel{"info", "rawSum"},
  valOutput = numberLabel{"info", "output"},
  
  imageOffset = newGraphLine("offset"),
  imageP = newGraphLine("p"),
  imageD = newGraphLine("d"),
  imageTransition = newGraphLine("transition"),
  imageOutput = newGraphLine("output"),
  
})
uiObject.onScroll = function(self, x, y, direction)
  if direction < 0 then
    --scroll down
    nextPID()
  else
    --scroll up
    previousPID()
  end
end


--one update is enough (nothing will be moved after that)
uiObject:update()

--keyboard only interface--
local selection = qselect.new(uiObject)
selection:initVertical(true)

--get gpu and current graphics settings for later use
local gpu, screen = component.gpu, component.screen
local oldResolutionWidth, oldResolutionHeight = gpu.getResolution()
local oldDepth = gpu.getDepth()

--setup graphics
gpu.setResolution(uiObject.width, uiObject.height)
gpu.setDepth(gpu.maxDepth())
uiObject:draw(gpu)

--create event processor
local eventProcessor = qevent.new(uiObject, selection, gpu)

--main loop--
while true do
  local event, source, x, y, direction = eventProcessor:onEvent(event.pull(1.0))
  if event == nil then
    --redraw every second
    updateGraph()
    uiObject:redrawChildren()
  elseif event == "interrupted" then
    break
  end
end

--restore old graphics options
gpu.setResolution(oldResolutionWidth, oldResolutionHeight)
gpu.setDepth(oldDepth)
--clear screen
term.setCursor(1, 1)
term.clear()
