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

local quidgets = {}

function quidgets.slider(obj)
  obj = obj or {}
  --TODO: add click and scroll listeners
  --TODO: update slider graphics (requires gpu)
  --TODO: call slider event function
  return obj
end

function quidgets.textbox(obj)
  obj = obj or {}
  
  function obj:onClick()
    self:edit()
  end
  
  function obj:edit(...)
    local text = values.get(self.text)
    --prepare writing area
    local w, h = component.gpu.getResolution()
    component.gpu.fill(self.x, self.y, w, 1, " ")
    --prepare cursor
    term.setCursor(self.x, self.y)
    --add current text to term.read
    computer.pushSignal("clipboard", component.keyboard.address, text:match("^[^\r\n]*"))
    --read input
    local input = term.read(...)
    --redraw user interface
    local top = self
    while top.parent do
      top = top.parent 
    end
    top:redraw(self.x, self.y)
    --trigger events
    if input then
      if self.onEdit then
        self:onEdit(input)
      else
        self.text = input
      end
    end
    return input
  end
  return obj
end

return quidgets
