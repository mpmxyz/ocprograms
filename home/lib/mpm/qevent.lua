-----------------------------------------------------
--name       : lib/qevent.lua
--description: qevent - a small event processing helper for qui
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

local component = require("component")
local keyboard  = require("keyboard")

local qevent = {}

--qevent.new(root:table, selection:table, gpu:table) -> event processor:table
--Takes a root ui object, a selection object and a gpu proxy to create an event processing helper.
--You can use its only method "onEvent" on wrap around a event.pull call:
-->local event, source = processor:onEvent(event.pull())
function qevent.new(root, selection, gpu)
  local processor = {
    root = root,
    selection = selection,
    gpu = gpu,
  }
  --processor:onEvent(event, ...) -> event, ... or "qui_event", event, ...
  --takes event data, does qui actions if applicable
  --It returns all arguments if nothing happened. If something happened it returns the string "qui_event" followed by all arguments.
  function processor:onEvent(...)
    --get event data
    local event, source, x, y, direction = ...
    --get component information
    local screenAddress = self.gpu.getScreen()
    local isValidKeyboard = false
    for _, address in ipairs(component.invoke(screenAddress, "getKeyboards")) do
      isValidKeyboard = isValidKeyboard or (address == source)
    end
    --do event processing
    if event == "touch" and source == screenAddress then
      self.root:click(x, y, 1)
    elseif event == "scroll" and source == screenAddress then
      self.root:scroll(x, y, direction)
    elseif event == "key_down" and isValidKeyboard then
      local key = y
      if key == keyboard.keys.enter then
        self.selection:click(1)
      elseif key == keyboard.keys.left then
        self.selection:selectPrevious()
      elseif key == keyboard.keys.right then
        self.selection:selectNext()
      elseif key == keyboard.keys.up then
        self.selection:selectUp()
      elseif key == keyboard.keys.down then
        self.selection:selectDown()
      elseif key == keyboard.keys.home then
        self.selection:selectFirst()
      elseif key == keyboard.keys["end"] then
        self.selection:selectLast()
      elseif key == keyboard.keys.pageUp then
        self.selection:scroll(1)
      elseif key == keyboard.keys.pageDown then
        self.selection:scroll(-1)
      else
        return ...
      end
    else
      return ...
    end
    return "qui_event", ...
  end
  return processor
end

return qevent
