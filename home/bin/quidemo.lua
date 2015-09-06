-----------------------------------------------------
--name       : bin/quidemo.lua
--description: a small program to highlight how easy it is to create an ui using "mpm.qui"
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : TODO
-----------------------------------------------------

local qui = require("mpm.qui")
local quidgets = require("mpm.quidgets")
local component = require("component")
local event = require("event")

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
  h = "%*+(%a*)%**",
  v = "%#+(%a*)%#*",
}, {
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
      self:redraw(self.x, self.y)
    end,
  },
  slider = quidgets.slider{
    gpu = component.gpu,
    vertical = false,
    view = 1,
  },
  input = quidgets.textbox{
    text = "Test!",
  }
})
while true do
  uiObject:update()
  uiObject:draw(component.gpu)
  local ev, src, x, y = event.pull("touch")
  if ev == "touch" then
    uiObject:click(x, y)
  end
end
