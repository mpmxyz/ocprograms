--[[
  auto_progress 
  allows you to create an object that displays a nice progress bar when things take a long time
  example code:
  
--load library
local auto_progress = require 'auto_progress'
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
  pbar:update(1)
end
--tell progress bar that the action has been finished
pbar:finish()
]]

local component = require("component")
local computer = require("computer")
local term = require("term")

--CONSTANTS--
--the time that has to pass before the progress bar is first displayed
local TRIGGER_TIME = 1
--do not trigger drawing if the progress bar is above this percentage before TRIGGER_TIME is finished
--avoids 'last minute' triggering of operations that are almost finished
local TRIGGER_PROGRESS = 0.5 --0.5 = 50%
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
  auto_progress.new(size) -> {update(),finish(),draw()}
  creates an object that you have to update with the status of you operation
  'size' is a measure of the total size of your operation.
  It can be bytes or items to process, distance to travel or whatever you like.
  The returned object has the following contents:
  
  obj:update(progressAdded)
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
  
  obj.size
  defines the size of the operation (in your own unit)
  This value is set when creating the object.
  Change it if you have to update your operation size.
  
  obj.progress
  defined as how much work has already been done.
  This value is updated automaticly when using the methods above.
  But you can still change it if you really want to.
  
  obj.triggered
  is set to true when the progress bar has been drawn at least once.
]]
function auto_progress.new(size)
  local creationTime = computer.uptime()
  local triggerTime = creationTime + TRIGGER_TIME
  
  return {
    x = nil, y = nil,
    width = nil,
    progress = 0,
    size = size,
    triggered = false,
    update = function(self, progressAdded)
      self.progress = self.progress + progressAdded
      local currentTime = computer.uptime()
      if currentTime > triggerTime then
        if self.triggered then
          self:draw()
        elseif self.progress < self.size * TRIGGER_PROGRESS then
          self:draw()
        end
      end
    end,
    finish = function(self)
      self.progress = self.size
      if self.triggered then
        self:draw()
        print() --next line
      end
    end,
    draw = function(self)
      self.triggered = true
      triggerTime = computer.uptime() + REFRESH_TIME
      if component.isAvailable("gpu") then
        local relativeProgress = math.max(math.min(self.progress / self.size, 1), 0)
        --get drawing position: custom position or move to the beginning of the current line
        local term_x, term_y = term.getCursor()
        local x, y = self.x or 1, self.y or term_y
        --get drawing dimensions
        local gpu = component.gpu
        local screen_width, screen_height = gpu.getResolution()
        local width = self.width or (screen_width - x + 1)
        --calculate progress bar size
        local barWidth = math.floor((width - 2) * relativeProgress + 0.5)
        --calculate time to finish
        local eta = nil
        if relativeProgress > 0 and relativeProgress < 1 then
          local speed = relativeProgress / (computer.uptime() - creationTime)
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
        --do actual drawing
        term.setCursor(x, y)
        term.write(line)
      end
    end,
  }
end

return auto_progress
