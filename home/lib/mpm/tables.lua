-----------------------------------------------------
--name       : lib/mpm/tables.lua
--description: drawing formatted tables
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

local unicode = require("unicode")
local values = require("mpm.values")

local tables = {}

function tables.create(tab)
  tab = tab or {}
  --layout:
  --  dynamic width given with positive weight values
  --  constant width given with negative values
  function tab.setLayout(newLayout)
    tab.layout = newLayout or {1}
    tab.totalWeight = 0
    tab.sumConstWidth = 0
    for i, width in ipairs(tab.layout) do
      if width > 0 then
        tab.totalWeight = tab.totalWeight + width
      elseif width < 0 then
        tab.sumConstWidth = tab.sumConstWidth - width
      else
        error("Zero column width!")
      end
    end
  end
  function tab.setColor(foreground, background)
    tab.foreground = foreground or 0xFFFFFF
    tab.background = background or 0x000000
  end
  function tab.setAlignment(alignment, padding)
    tab.alignment = alignment or "l"
    tab.padding   = padding or " "
  end
  function tab.setSeparator(separator)
    tab.separator = separator or ""
  end
  function tab.add(line)
    tab[#tab + 1] = line
  end
  function tab.getColumnWidths(totalWidth)
    --calculate column sizes...
    local ncolumns = #tab.layout
    local variableWidth = totalWidth - tab.sumConstWidth - unicode.len(tab.separator) * (ncolumns - 1)
    local widthPerWeight = tab.totalWeight > 0 and (variableWidth / tab.totalWeight) or 0
    if widthPerWeight < 0 then
      --not enough space to draw...
      return nil, tab.sumConstWidth
    end
    local columnWidths = {}
    local carriedWidth = 0
    for column, width in ipairs(tab.layout) do
      if width > 0 then
        local rawWidth = width * widthPerWeight
        carriedWidth = carriedWidth + (rawWidth % 1)
        if carriedWidth >= 1 then
          --if there is a chance for carriedWidth to become 0.999... instead of one
          --change carriedWidth >= 1 to carriedWidth >= 0.999
          rawWidth = rawWidth + 1
          carriedWidth = carriedWidth - 1
        end
        columnWidths[column] = math.floor(rawWidth)
      else
        columnWidths[column] = - width
      end
    end
    return columnWidths, tab.sumConstWidth
  end
  --x_relative is 0 based (x_relative == 0 -> tested x == table x)
  function tab.getColumn(x_relative, width)
    local columnWidths, minimumWidth = tab.getColumnWidths(width)
    if columnWidths == nil then
      return nil
    end
    if x_relative < 0 then
      return nil
    end
    for column, columnWidth in ipairs(columnWidths) do
      x_relative = x_relative - columnWidth
      if x_relative < 0 then
        return column
      end
      x_relative = x_relative - unicode.len(tab.separator)
    end
    return nil
  end
  --y_relative is 0 based (y_relative == 0 -> tested x == table x)
  function tab.getRow(y_relative, height, scrollY)
    if y_relative < 0 or y_relative >= height then
      return nil
    end
    local index = y_relative + scrollY + 1
    if tab[index] ~= nil then
      return index
    end
  end
  function tab.getFormattedCellContent(line, column, columnWidth)
    local cellContent = line[column] or ""
    local alignment  = values.get(line.alignment, false, column) or values.get(tab.alignment, false, column)
    local padding    = values.get(line.padding  , false, column) or values.get(tab.padding  , false, column)
    
    local extendingAlignment, shorteningAlignment = alignment:match("([lrc])([alr]?)")
    assert(extendingAlignment, "Invalid Alignment!")
    if shorteningAlignment == "" then
      assert(extendingAlignment ~= "c", "Can't use 'c' alignment for shortening!")
      shorteningAlignment = extendingAlignment
    end
    
    local autoScroller
    --adjust content to perfectly fit
    if unicode.len(cellContent) > columnWidth then
      --content too long: shorten it
      if shorteningAlignment == "a" then
        local originalContent = cellContent
        autoScroller = function(gpu, x,y, foreground, background)
          local scrollX = 0
          local maxScrollX = unicode.len(originalContent) - columnWidth
          local scrollXStep = math.min(math.max(math.floor(columnWidth / 2), 1), 5)
          return function()
            if scrollX < maxScrollX then
              scrollX = math.min(scrollX + scrollXStep, maxScrollX)
            else
              scrollX = 0
            end
            gpu.setForeground(foreground)
            gpu.setBackground(background)
            gpu.set(x, y, unicode.sub(originalContent, 1 + scrollX, columnWidth + scrollX))
          end
        end
      end
      --shorten it
      if shorteningAlignment == "l" or shorteningAlignment == "a" then
        cellContent = unicode.sub(cellContent, 1, columnWidth)
      elseif shorteningAlignment == "r" then
        cellContent = unicode.sub(cellContent, -columnWidth, -1)
      end
    elseif unicode.len(cellContent) < columnWidth then
      --content too large: add padding
      local addition = columnWidth - unicode.len(cellContent)
      if extendingAlignment == "l" then
        cellContent = cellContent .. padding:rep(addition)
      elseif extendingAlignment == "r" then
        cellContent = padding:rep(addition) .. cellContent
      elseif extendingAlignment == "c" then
        cellContent = padding:rep(math.floor(addition / 2)) .. 
                      cellContent ..
                      padding:rep(math.ceil(addition / 2))
      end
    end
    return cellContent, autoScroller
  end
  function tab.draw(gpu, x, y, width, height, scrollY)
    --assuming that a table is never drawn twice, we can delete known scrolling updaters
    tab.autoScrollers = {}
    --how much space is each column going to have?
    local columnWidths, minimumWidth = tab.getColumnWidths(width)
    if columnWidths == nil then
      gpu.setForeground(tab.foreground)
      gpu.setBackground(tab.background)
      gpu.fill(x, y,width, height, tab.padding)
      local msg = ""
      for draw_y = y, y + height - 1 do
        if msg == "" then
          msg = ("width>"..minimumWidth.."!")
        end
        gpu.set(x, draw_y, msg:sub(1, width))
        msg = msg:sub(width + 1, - 1)
      end
      return
    end
    --drawing loop
    local separatorSpaces = (" "):rep(unicode.len(tab.separator)) --draw_buffer optimization: connecting spaces
    local draw_y = y
    scrollY = scrollY or 0
    for index = scrollY + 1, scrollY + height do
      local line = tab[index]
      if line then
        local draw_x = x
        for column, columnWidth in ipairs(columnWidths) do
          if columnWidth > 0 then
            --get colors and formatting
            local foreground = values.get(line.foreground, false, column) or values.get(tab.foreground, false, column)
            local background = values.get(line.background, false, column) or values.get(tab.background, false, column)
            gpu.setForeground(foreground)
            gpu.setBackground(background)
            --gets displayed string and a callback generator
            local cellContent, autoScroller = tab.getFormattedCellContent(line, column, columnWidth)
            --draw_buffer optimization: create connecting spaces
            if columnWidths[column + 1] and tab.separator ~= "" then
              cellContent = cellContent .. separatorSpaces
            end
            --draw
            gpu.set(draw_x, draw_y, cellContent)
            --remember scrolling callback
            if autoScroller then
              table.insert(tab.autoScrollers, autoScroller(gpu, draw_x, draw_y, foreground, background))
            end
            --move right
            draw_x = draw_x + columnWidth + unicode.len(tab.separator)
          end
        end
      else
        --simple background
        local draw_x = x
        for column, columnWidth in ipairs(columnWidths) do
          gpu.setForeground(values.get(tab.foreground, false, column))
          gpu.setBackground(values.get(tab.background, false, column))
          local padding = values.get(tab.empty or tab.padding, false, column)
          gpu.fill(draw_x, draw_y, columnWidth, height - (draw_y - y), padding)
          draw_x = draw_x + columnWidth + unicode.len(tab.separator)
        end
        break
      end
      draw_y = draw_y + 1
    end
    --draw separators last to allow combining rows to a single drawing call
    if tab.separator ~= "" then
      local draw_x = x
      for column, columnWidth in ipairs(columnWidths) do
        gpu.setForeground(values.get(tab.foreground, false, column))
        gpu.setBackground(values.get(tab.background, false, column))
        if column > 1 then
          for char in tab.separator:gmatch("[\0-\x7F\xC2-\xF4][\x80-\xBF]*") do
            gpu.fill(draw_x, y,1, height, char)
            draw_x = draw_x + 1
          end
        end
        draw_x = draw_x + columnWidth
      end
    end
  end
  function tab.updateScrollingCallbacks()
    if tab.autoScrollers then
      for _, callback in ipairs(tab.autoScrollers) do
        callback()
      end
    end
  end
  --add convenience to the constructor
  tab.setLayout(tab.layout)
  tab.setColor(tab.foreground, tab.background)
  tab.setAlignment(tab.alignment, tab.padding)
  tab.setSeparator(tab.separator)
  return tab
end

return tables
