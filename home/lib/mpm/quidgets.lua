-----------------------------------------------------
--name       : lib/quidgets.lua
--description: quidgets - adds commonly used widgets to qui
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------


local component = require("component")
local computer  = require("computer")
local term      = require("term")
local unicode   = require("unicode")
local values    = require("mpm.values")
local qui       = require("mpm.qui")
local textgfx   = require("mpm.textgfx")

local quidgets = {}

function quidgets.bar(obj)
  obj = obj or {}
  function obj:set(from, to, minimum, maximum)
    --get dimensions
    local size = self.vertical and self.height or self.width
    local thickness = self.vertical and self.width or self.height
    --get characters
    local char = self.char
    local reversedChar = self.reversedChar
    local bgLeft = self.bgLeft
    local bgRight = self.bgRight
    --update text
    self.text = textgfx.bar(size, from, to, minimum, maximum, char, reversedChar, bgLeft, bgRight, thickness)
  end
  if obj.from and obj.to and obj.minimum and obj.maximum then
    obj:set(from, to, minimum, maximum)
  end
  return obj 
end


function quidgets.slider(obj)
  obj = obj or {}
  --TODO: add click and scroll listeners
  --TODO: initial values
  --TODO: check args
  --TODO: call slider event function
  function obj:setRange(min, max, size)
    --1, 3, 1 -> slider with the values 1, 2, 3 and a single character knob
    --1, 10, 5 -> scroll bar with the values 1, ..., 6 and a 50% size knob
    self.size = size
    self.min = min
    self.max = max
    self:updateBar()
  end
  function obj:setValue(value)
    self.value = value
    self:updateBar()
  end
  function obj:updateBar()
    self:set(self.value, self.value + self.size - 1, self.min, self.max)
    self:redraw()
  end
  function obj:onClick(x, y)
    
  end
  function obj:onScroll(x, y, direction)
    
  end
  return obj
end

function quidgets.textbox(obj)
  obj = obj or {}
  
  function obj:onClick()
    --TODO: term options
    --TODO: react on click
    self:edit()
  end
  
  function obj:edit(...)
    local text = values.get(self.text)
    local gpu = self.lastGPU
    assert(gpu, "Textbox has to be drawn before editing!")
    --prepare writing area
    local w, h = gpu.getResolution()
    component.gpu.fill(self.x_draw, self.y_draw, w, 1, " ")
    --prepare cursor
    term.setCursor(self.x_draw, self.y_draw)
    --add current text to term.read, TODO: make the content adjustable
    computer.pushSignal("clipboard", component.keyboard.address, text:match("^[^\r\n]*"))
    --read input
    local input = term.read(...)
    --trigger events
    if input then
      input = input:match("^[^\r\n]*")
      if self.onEdit then
        self:onEdit(input)
      else
        self.text = input
      end
    end
    --redraw user interface
    local top = self
    while top.parent do
      top = top.parent 
    end
    top:redraw(self.x_draw, self.y_draw, nil, self.y_draw)
    return input
  end
  return obj
end

return quidgets
