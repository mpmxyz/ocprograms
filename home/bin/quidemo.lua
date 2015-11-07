-----------------------------------------------------
--name       : bin/quidemo.lua
--description: a small program to highlight how easy it is to create an ui using "mpm.qui"
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : TODO
-----------------------------------------------------

local component = require("component")
local event = require("event")
local keyboard = require("keyboard")
local qui = require("mpm.qui")
local quidgets = require("mpm.quidgets")
local qselect = require("mpm.qselect")


local ui = [[
*label*    *b* #
               s
 *slider*      l
               i
 *input********d
               e
               r
               #]]     

local uiObject = qui.load(ui, {
  label = {
    text = "Test123",
    fgColor = 0xFFAA55,
    bgColor = 0x000000,
  },
  b = {
    text = "0/1",
    fgColor = 0xFFFFFF,
    bgColor = 0x000000,
    state = false,
    onClick = function(self)
      self.state = not self.state
      if self.state then
        self.text = "on "
        self.fgColor = 0x33FF33
        self.bgColor = 0x003300
      else
        self.text = "off"
        self.fgColor = 0xFF3333
        self.bgColor = 0x330000
      end
      self:redraw(self.x_draw, self.y_draw, self.x_draw + self.width - 1, self.y_draw)
    end,
  },
  slider = quidgets.slider{
    gpu = component.gpu,
    vertical = false,
    view = 1,
    text = "",
  },
  input = quidgets.textbox{
    text = "Test!",
  }
})
selection = qselect.new(uiObject)

while true do
  uiObject:update()
  uiObject:draw(component.gpu)
  local ev, src, x, y = event.pull()
  if ev == "touch" and src == component.screen.address then
    uiObject:click(x, y)
  elseif ev == "scroll" and src == component.screen.address then
    uiObject:scroll(x, y, direction)
  elseif ev == "key_down" and src == component.keyboard.address then
    local key = y
    if key == keyboard.keys.enter then
      selection:click()
    elseif key == keyboard.keys.left then
      selection:selectPrevious()
    elseif key == keyboard.keys.right then
      selection:selectNext()
    elseif key == keyboard.keys.home then
      selection:selectFirst()
    elseif key == keyboard.keys.ende then
      selection:selectLast()
    end
  elseif ev == "interrupted" then
    break
  end
end
