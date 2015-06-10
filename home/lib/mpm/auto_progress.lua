-----------------------------------------------------
--name       : lib/mpm/auto_progress.lua
--description: display progress bars while your program is doing something
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/420-mpmauto-progress-a-console-progress-bar-for-impatient-users/
-----------------------------------------------------

--[[
  auto_progress 
  allows you to create an object that displays a nice progress bar when things take a long time
  example code:
  
--load library
local auto_progress = require 'mpm.auto_progress'
--generate a list of actions
local todo = {}
for i=1, 30 do
  todo[i] = math.random() * 2
end
--create progress bar: initialize it with the amount of work to do
local pbar = auto_progress.new(#todo)
for _, duration in pairs(todo) do
  --simulate an action
  os.sleep(duration)
  --update progress bar: 1 step done
  pbar.update(1)
end
--tell progress bar that the action has been finished
pbar.finish()
]]

local component = require("component")
local computer = require("computer")
local term = require("term")

--CONSTANTS--
--the time that has to pass before the progress bar is first displayed
local DRAWING_DELAY = 1
--do not trigger drawing if the progress bar is above this percentage before TRIGGER_TIME is finished
--avoids 'last minute' triggering of operations that are almost finished
local INHIBITING_PROGRESS = 0.5 --0.5 = 50%
--the time between two drawing operations (limits how often the progress bar is updated)
local REFRESH_TIME = 0.25

--TIME -> STRING--
local timeUnits = {
--format string; divisor for next step
  {"<1s",     1},
  {"%.0fs",  60},
  {"%.0fm",  60},
  {"%.0fh",  24},
  {"%.1fd", 365.25},
  {"%.1fy",  10},
  {">10y"},
}
local function secondsToTime(timeInUnits)
  for _,unit in ipairs(timeUnits) do
    local fmt = unit[1]
    local divisor = unit[2]
    if not divisor or timeInUnits < divisor then
      return fmt:format(timeInUnits)
    else
      timeInUnits = timeInUnits / divisor
    end
  end
end

--THE LIBRARY--
local auto_progress = {}
--[[
  auto_progress.new(totalWork) -> {update(),finish(),draw()}
  creates an object that you have to update with the status of you operation
  'size' is a measure of the total size of your operation.
  It can be bytes or items to process, distance to travel or whatever you like.
  The returned object has the following contents:
  
  obj:update(workAdded)
  should be called whenever you have finished a part of your work.
  'progressAdded' is how much has been done since the last call.
  (Negative values will remove progress.)
  It will draw and update the progress bar if necessary.
  
  obj:finish()
  should be called when your application finished the operation.
  It will draw a full progress bar and move to the next line when a progress bar has been drawn previously.
  
  obj:draw()
  is normally called by update() and finish().
  It can be called manually to avoid the delay before the progress bar is drawn.
  
  obj.x, obj.y
  can be set to specify where the progress bar is drawn.
  The default is the beginning of the current line.
  
  obj.width
  can be set to limit the width of the progress bar.
  The default is drawing to the end of the line.
  
  obj.drawing
  setting this to true cancels the drawing delay.
  
  obj.disabled
  true disables automatic drawing; manual drawing is still possible though.
  
  obj.totalWork
  defines the size of the operation (in your own unit)
  This value is set when creating the object.
  Change it if you have to update your operation size.
  
  obj.doneWork
  defined as how much work has already been done.
  This value is updated automaticly when using the methods above.
  But you can still change it if you really want to.
  
  obj.creationTime
  the computer.uptime() when the object was created
  
  obj.lastUpdate
  the computer.uptime() from the last obj.draw() call
]]
function auto_progress.new(self)
  
  --force self to be a table
  if type(self) == "number" or self == nil then
    --create a new table
    self = {totalWork = self}
  end
  assert(type(self) == "table", "Parameter has to be a table, a number or nil!")
  
  --make default values
  self.doneWork  = self.doneWork or 0
  self.totalWork = self.totalWork or 1
  self.disabled  = self.disabled or false
  self.drawing   = self.drawing  or false
  
  self.creationTime = computer.uptime()
  self.lastUpdate = self.creationTime
  
  --check types
  assert(self.x     == nil or type(self.x)     == "number", "progress_state.x has to be nil or a number!")
  assert(self.y     == nil or type(self.y)     == "number", "progress_state.y has to be nil or a number!")
  assert(self.width == nil or type(self.width) == "number", "progress_state.width has to be nil or a number!")
  assert(type(self.doneWork)  == "number", "progress_state.doneWork has to be nil or a number!")
  assert(type(self.totalWork) == "number", "progress_state.totalWork has to be nil or a number!")
  assert(type(self.disabled)  == "boolean", "progress_state.disabled has to be nil or a boolean!")
  assert(type(self.drawing)   == "boolean", "progress_state.drawing has to be nil or a boolean!")
  
  --add methods
  --updates the progress bar, adds workAdded to the progress counter
  function self.update(workAdded)
    self.doneWork = self.doneWork + (workAdded or 0)
    local currentTime = computer.uptime()
    local triggerTime = self.lastUpdate + (self.drawing and REFRESH_TIME or DRAWING_DELAY)
    if currentTime > triggerTime and (not self.disabled) then
      if self.drawing then
        self.draw()
      elseif (self.doneWork < self.totalWork * INHIBITING_PROGRESS) then
        self.draw()
      end
    end
  end
  --draws a final progress bar if necessary
  function self.finish()
    self.doneWork = self.totalWork
    if self.drawing and (not self.disabled) then
      self.draw()
    end
  end
  --used for drawing the progress bar
  function self.draw()
    self.drawing = true
    self.lastUpdate = computer.uptime()
    if term.isAvailable() then
      --get drawing dimensions
      local gpu = component.gpu
      local screen_width, screen_height = gpu.getResolution()
      if screen_width == nil then
        --gpu not bound to screen
        return
      end
      --get drawing position: custom position or move to the beginning of the current line
      if self.x == nil or self.y == nil then
        local term_x, term_y = term.getCursor()
        if term_x > 1 and self.x == nil and self.y == nil then
          --finish line
          print()
        end
        --move cursor to the next line
        print()
        --get progress bar position
        term_x, term_y = term.getCursor()
        self.x, self.y = self.x or term_x, self.y or (term_y - 1)
      end
      local relativeProgress = math.max(math.min(self.doneWork / self.totalWork, 1), 0)
      local x, y = self.x, self.y
      if x <= 0 or x > screen_width or y <= 0 or y > screen_height then
        --don't draw outside the screen
        return
      end
      local width = math.min(self.width or math.huge, (screen_width - x + 1))
      --calculate progress bar size
      local barWidth = math.floor((width - 2) * relativeProgress + 0.5)
      --calculate time to finish
      local eta = nil
      if relativeProgress > 0 and relativeProgress < 1 then
        local speed = relativeProgress / (computer.uptime() - self.creationTime)
        eta = (1 - relativeProgress) / speed
      end
      --create background
      local line = "[" .. ("-"):rep(barWidth) .. (" "):rep(width - 2 - barWidth) .. "]"
      --create text
      local text = ("%i%%"):format(100 * relativeProgress)
      if eta then
        text = text .. " ETA: " .. secondsToTime(eta)
      end
      --combine text with background
      local textPosition = math.floor((width - #text) / 2)
      line = line:sub(1, textPosition) .. text .. line:sub(textPosition + #text + 1, -1)
      --drawing...
      gpu.set(x, y, line)
    end
  end
  return self
end

return auto_progress
