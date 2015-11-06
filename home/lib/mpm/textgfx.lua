-----------------------------------------------------
--name       : home/lib/textgfx.lua
--description: gfx library for text based graphics
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

local unicode = require("unicode")

local textgfx = {}

local linePattern = "([^\r\n]*)(\r?\n?)"

--clamp(value:number, size:number, [minimum:number, maximum:number]) -> [clampedValue:number, clampedSize:number, offset:number]
--takes an integer range [value:value + size - 1] and cuts off all parts exceeding the given minimum and maximum
--The return values consist of the new range and an offset value telling how much has been removed from the lower part.
local function clamp(value, size, minimum, maximum)
  local offset = 0
  --cutting off the lower part
  if minimum and value < minimum then
    offset = minimum - value
    size = size - offset
    value = minimum
  end
  --cutting off the upper part
  if maximum and value + size - 1 > maximum then
    size = maximum - value + 1
  end
  if size > 0 then
    return value, size, offset
  end
end

--textgfx.checkView(x, y, width, height, [viewXmin, viewYmin, viewXmax, viewYmax]) -> visible:boolean
--returns true if the given rectange is not completely clipped by the given boundaries
function textgfx.checkView(x, y, width, height, viewXmin, viewYmin, viewXmax, viewYmax)
  checkArg(1, x     , "number")
  checkArg(2, y     , "number")
  checkArg(3, width , "number")
  checkArg(4, height, "number")
  checkArg(5, viewXmin, "number", "nil")
  checkArg(6, viewYmin, "number", "nil")
  checkArg(7, viewXmax, "number", "nil")
  checkArg(8, viewYmax, "number", "nil")
  --TODO: checkargs
  local offsetX, offsetY
  x, width,  offsetX = clamp(x, width,  viewXmin, viewXmax)
  y, height, offsetY = clamp(y, height, viewYmin, viewYmax)
  return (width and height) ~= nil
end

--textgfx.draw(gpu:table, text:string, x:int, y:int, width:int, height:int, [viewYmin:int, viewYmin:int, viewXmax:int, viewYmax:int, vertical:boolean]) -> visible:boolean
--draws the given multiline string to the given target gpu and area
--The drawing area can be further limitted by the given boundaries.
--Vertical drawing mode flips x and y in the string. (Each line in the string equals to a column drawn.)
--Returns true if something has been drawn.
function textgfx.draw(gpu, text, x, y, width, height, viewXmin, viewYmin, viewXmax, viewYmax, vertical)
  checkArg( 1, gpu     , "table")
  checkArg( 2, text    , "string")
  checkArg( 3, x       , "number")
  checkArg( 4, y       , "number")
  checkArg( 5, width   , "number")
  checkArg( 6, height  , "number")
  checkArg( 7, viewXmin, "number", "nil")
  checkArg( 8, viewYmin, "number", "nil")
  checkArg( 9, viewXmax, "number", "nil")
  checkArg(10, viewYmax, "number", "nil")
  checkArg(11, vertical, "boolean", "nil")
  --draw(x, y, text): orders the gpu to do its work
  local draw
  if vertical then
    --swap x and y to support vertical drawing
    x, y = y, x
    width, height = height, width
    viewXmin, viewYmin = viewYmin, viewXmin
    viewXmax, viewYmax = viewYmax, viewXmax
    draw = function(x, y, line)
      gpu.set(y, x, line, true)
    end
  else
    draw = gpu.set
  end
  --apply clipping
  local offsetX, offsetY
  x, width,  offsetX = clamp(x, width,  viewXmin, viewXmax)
  y, height, offsetY = clamp(y, height, viewYmin, viewYmax)
  
  --Is the object visible?
  if width and height then
    --Yes it is; remember the last drawn character of a line for later
    local offsetWidth = width + offsetX
    --draw line by line
    for line, lineBreak in text:gmatch(linePattern) do
      if offsetY > 0 then
        --skip clipped lines
        offsetY = offsetY - 1
      else
        ---adjusting line length
        local lineWidth = unicode.wlen(line)
        --adjusting ending
        if lineWidth < offsetWidth then
          line = line .. (" "):rep(offsetWidth - lineWidth)
        elseif lineWidth > offsetWidth then
          line = unicode.wtrunc(line, offsetWidth + 1)
        end
        --adjusting beginning
        line = unicode.sub(line, 1 + offsetX, -1)
        
        --drawing operation
        draw(x, y, line)
        
        --go to next line
        y = y + 1
        --check if we reached the end
        height = height - 1
        if height <= 0 then
          break
        end
      end
    end
    --draw missing lines
    if height > 0 then
      local line = (" "):rep(width)
      while height > 0 do
        draw(x, y, line)
        --go to next line
        y = y + 1
        height = height - 1
      end
    end
    --something has been drawn
    return true
  end
  ----nothing has been drawn
  return false
end

--TODO: viewport vs. drawing window? (moved origin (y/n))
--textgfx.createCanvas([canvas:table]) -> canvas:table
--TODO: description
function textgfx.createCanvas(canvas)
  checkArg(1, canvas, "table", "nil")
  canvas = canvas or {}
  function canvas:checkView(x, y, width, height)
    local maxX, maxY = self.x + self.width - 1, self.y + self.height - 1
    return textgfx.checkView(x, y, width, height, self.x, self.y, maxX, maxY)
  end
  function canvas.set()
    --TODO: reimplement gpu a bit...
  end
  function canvas:draw(text, x, y, width, height, vertical)
    local maxX, maxY = self.x + self.width - 1, self.y + self.height - 1
    return textgfx.draw(self.gpu, text, x, y, width, height, self.x, self.y, maxX, maxY, vertical)
  end
  --TODO: validation method
  return canvas
end

--TODO: add a function to make the bar transform available

--textgfx.bar(size:int, from:number, to:number, minimum:number, maximum:number, [char:string, reversedChar:string, bgLeft:string, bgRight:string, thickness:number]) -> bar:string
--creates a string used for progress bars, sliders etc.
--"size" and "thickness" determine the dimensions of the bar ("size" being the length of a line in the direction of the bar's movement)
--"reversedChar" is used for the bar when "from" is bigger than "to".
--"bgLeft" and "bgRight" are the background characters left and right of the bar.
--If you are using a "thickness" you have to supply an equivalent amount of characters to the string parameters.
--The first characters are used for the first line, the second ones for the second line and so on.
function textgfx.bar(size, from, to, minimum, maximum, char, reversedChar, bgLeft, bgRight, thickness)
  checkArg( 1, size   , "number")
  checkArg( 2, from   , "number")
  checkArg( 3, to     , "number")
  checkArg( 4, minimum, "number")
  checkArg( 5, maximum, "number")
  checkArg( 6, char        , "string", "nil")
  checkArg( 7, reversedChar, "string", "nil")
  checkArg( 8, bgLeft      , "string", "nil")
  checkArg( 9, bgRight     , "string", "nil")
  checkArg(10, thickness   , "number", "nil")
  --optional parameters
  char = char or ("\xE2\x96\x88"):rep(thickness or 1) --full block
  reversedChar = reversedChar or char
  bgLeft = bgLeft or (" "):rep(thickness or 1)
  bgRight = bgRight or bgLeft
  thickness = thickness or math.min(unicode.wlen(char), unicode.wlen(reversedChar), unicode.wlen(bgLeft), unicode.wlen(bgRight))
  
  --from ? to
  if from > to then
    from, to = to, from
    char = reversedChar
  end
  --from <= to
  from = math.min(math.max(from, minimum), maximum)
  to   = math.min(math.max(to  , minimum), maximum)
  --minimum <= from <= to <= maximum
  
  -- minimum -> 0
  -- maximum -> 1
  from = (from - minimum) / (maximum - minimum)
  to   = (to   - minimum) / (maximum - minimum)
  
  --interpolation within 1..size
  local indexFrom = math.floor(from * (size - 1) + 1.5)
  local indexTo   = math.floor(to   * (size - 1) + 1.5)
  
  --create string buffer
  local buffer = {}
  local offset = 0
  for j = 1, thickness do
    local currentBGLeft  = unicode.sub(bgLeft,  j, j)
    local currentChar    = unicode.sub(char,    j, j)
    local currentBGRight = unicode.sub(bgRight, j, j)
    for i = 1, indexFrom - 1 do
      buffer[offset + i] = currentBGLeft
    end
    for i = indexFrom, indexTo do
      buffer[offset + i] = currentChar
    end
    for i = indexTo + 1, size do
      buffer[offset + i] = currentBGRight
    end
    if j < thickness then
      offset = offset + size + 1
      buffer[offset] = "\n"
    end
  end
  --create string
  return table.concat(buffer)
end

return textgfx
