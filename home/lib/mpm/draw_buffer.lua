-----------------------------------------------------
--name       : lib/mpm/draw_buffer.lua
--description: speeds up drawing by combining multiple drawing calls
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------


--[[
****DRAW BUFFER****
--
--it's a simple buffer, which only remembers everything that can be combined into one call
--speeds up drawing if you draw strings from left to right, without distance in between
--(that is often the case with formatted texts if you explicitly draw space characters)
]]
--returns true if the given text is only made of space characters
local function isSpace(text)
  return text:match("^ *$") ~= nil
end

local flushingFunctions = {
  bind = true,          --prevent drawing after target change
  copy = true,          --avoid reading old contents
  fill = true,          --uses a 2D shape, the buffer is 1D only
  get = true,           --avoid reading old contents
  getBackground = true, --avoid reading old contents
  getForeground = true, --avoid reading old contents
  setResolution = true, --buffer has to be cleared, else it is drawn after resolution change
}

local draw_buffer = {}
--wraps a gpu proxy to buffer its operations for increased speed
function draw_buffer.new(gpu)
  assert(gpu~=nil,"GPU required!")
  
  --user side object
  local object = {}
  --internal buffer object
  local buffer = {text="",x=1,y=1}
  --now following: functions working like their gpu counterparts
  --But buffered!
  function object.setForeground(foreground,background)
    buffer.next_foreground = math.floor(foreground)
  end
  function object.setBackground(background)
    buffer.next_background = math.floor(background)
  end
  --an axis independent token pasting function
  local function insertToken(relative_position, pastedText)
    local text = buffer.text
    local remove_from = math.max(1 + relative_position,1)
    local remove_to   = math.max(#pastedText + relative_position,0)
    buffer.text = text:sub(1, remove_from - 1) .. pastedText .. text:sub(remove_to + 1, -1)
  end
  function object.set(x,y,text,vertical)
    --ist: prepare arguments
    x = math.floor(x)
    y = math.floor(y)
    text = tostring(text)
    local size = #text
    local nextSpace = isSpace(text)
    if size == 0 then
      return true --?
    end
    if size > 1 then
      vertical = (not not vertical) -->force boolean
    else
      vertical = nil                -->don't care
    end
    local next_foreground
    if nextSpace then
      next_foreground = nil         -->don't care
    else
      next_foreground = buffer.next_foreground
    end
    local next_background = buffer.next_background
    
    --2nd: Is flushing necessary?
    --check orientation: flush if unequal unless at least one does not care
    --(uses a three values logic: nil == "don't care")
    if buffer.vertical ~= nil and vertical ~= nil then
      if buffer.vertical ~= vertical then
        object.flush()
      end
    end
    --check color: flush if unequal unless next_<color> is nil
    --next_<color> indicates the color that should be applied to the given text
    --The foreground can be ignored for parts only containing space characters.
    --->The foreground check can be ignored if either text or the buffer are full of spaces.
    --buffer.next_<color> is the color set by the user, nil when not yet set (nil == "not yet set")
    --local next_color the same as above, but nil when text does not need it (nil == "don't care")
    --buffer.<color> is the color value used by the buffered operation, nil == "don't care" (spaces) or "not yet set" (empty buffer)
    --buffer.current_<color> is the color that has been set by gpu.set<color>, it assumes no interference by the user
    
    --foreground: flushing when already set and the next foreground is different
    if buffer.foreground and next_foreground then
      if buffer.foreground ~= next_foreground then
        object.flush()
      end
    end
    --background: flushing when already set and the next background is different
    if buffer.background and next_background then
      if buffer.background ~= next_background then
        object.flush()
      end
    end
    --check position
    if #buffer.text > 0 then
      local dx = x - buffer.x
      local dy = y - buffer.y
      --check that there isn't a diagonal connection
      if dx ~= 0 and dy ~= 0 then
        object.flush()
      elseif dx ~= 0 then
        --check compatibility with orientation
        if buffer.vertical == true or vertical == true then
          object.flush()
          --check that the next token connects to the buffer
        elseif dx < -size or dx > #buffer.text then
          object.flush()
        end
      elseif dy ~= 0 then
        --check compatibility with orientation
        if buffer.vertical == false or vertical == false then
          object.flush()
          --check that the next token connects to the buffer
        elseif dy < -size or dy > #buffer.text then
          object.flush()
        end
      end
    end
    
    --3rd: add information to buffer
    if vertical ~= nil then
      buffer.vertical = vertical
    end
    local dx = x - buffer.x
    local dy = y - buffer.y
    if #buffer.text > 0 and (dx ~= 0 or dy ~= 0) then
      if dx ~= 0 then
        --force horizontal
        buffer.vertical = false
        insertToken(dx, text)
        buffer.x = math.min(buffer.x, x)
      elseif dy ~= 0 then
        --force vertical
        buffer.vertical = true
        insertToken(dy, text)
        buffer.y = math.min(buffer.y, y)
      end
    else
      --first entry / overwrite (starting at single character in buffer)
      buffer.text = text
      buffer.x = x
      buffer.y = y
    end
    --Checks: Only spaces?
    buffer.allSpace = buffer.allSpace and nextSpace
    --combine color information, the or operation only receives one non nil argument or two equal arguments
    buffer.background = buffer.background or next_background
    buffer.foreground = buffer.foreground or next_foreground
    return true
  end
  --forces clearing the buffer
  function object.flush(all)
    if buffer.foreground and buffer.current_foreground ~= buffer.foreground then
      gpu.setForeground(buffer.foreground)
      --current_<color> remembers the last color set to avoid even more calls
      buffer.current_foreground = buffer.foreground
      buffer.foreground = nil
    end
    if buffer.background and buffer.current_background ~= buffer.background then
      gpu.setBackground(buffer.background)
      buffer.current_background = buffer.background
      buffer.background = nil
    end
    if #buffer.text > 0 then
      if buffer.allSpace then
        if buffer.vertical then
          gpu.fill(buffer.x,buffer.y,1,#buffer.text," ")
        else
          gpu.fill(buffer.x,buffer.y,#buffer.text,1," ")
        end
      else
        gpu.set(buffer.x,buffer.y,buffer.text,buffer.vertical or false)
      end
      --clear buffer
      buffer.text = ""
      buffer.vertical = nil
      buffer.allSpace = true
      buffer.background = nil
      buffer.foreground = nil
    end
    if all then
      --force setting all colors
      buffer.foreground = buffer.next_foreground
      buffer.background = buffer.next_background
      object.flush()
    end
  end
  --to be called when the stored color state might be wrong
  function object.dirty()
    buffer.current_foreground = nil
    buffer.current_background = nil
  end
  --copy other gpu methods to make this a perfect drop-in replacement
  for k,v in pairs(gpu) do
    if object[k] == nil then
      if flushingFunctions[k] then
        object[k] = function(...)
          object.flush(true)
          return v(...)
        end
      else
        object[k] = v
      end
    end
  end
  return object
end
return draw_buffer
