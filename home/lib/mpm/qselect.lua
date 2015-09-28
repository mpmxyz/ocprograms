-----------------------------------------------------
--name       : lib/qselect.lua
--description: qselect - a selection utility to add keyboard navigation to qui applications
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

--TODO: test tree traversal
--TODO: add user override for selection
--TODO: add select[Up,Down,Left,Right]
local stack = require("mpm.stack")

local qselect = {}


function qselect.new(parentObject)
  local obj = {
    parentObject = parentObject,
    indexStack = stack.new{},
    parentStack = stack.new{parentObject},
  }
  function obj:mark(marked)
    self.markedObject = marked
    if not marked.marked then
      marked.marked = true
      marked:redraw()
    end
  end
  function obj:unmark()
    local marked = self.markedObject
    self.markedObject = nil
    if marked and marked.marked then
      marked.marked = nil
      marked:redraw()
    end
  end
  function obj:moveNext()
    local topParent = self.parentStack:top()
    --1st: add stack layer
    --2nd: increase index
    --3rd: remove stack layer, repeat 2nd step
    if topParent[1] ~= nil  then
      --add new stack layer
      local newIndex = 1
      self.indexStack:push(newIndex)
      self.parentStack:push(topParent[newIndex])
    elseif not self.indexStack:isEmpty() then
      repeat
        --remove current leaf object and advance index
        self.parentStack:pop()
        local newIndex = self.indexStack:pop() + 1
        --get new leaf object
        local newParent = self.parentStack:top()[newIndex]
        if newParent then
          --if new leaf object exists: reinsert index and leaf object
          self.indexStack:push(newIndex)
          self.parentStack:push(newParent)
        end
        --else: repeat, one stack layer has been removed
      until newParent or self.indexStack:isEmpty()
    end
    return self.parentStack:top()
  end
  function obj:movePrevious()
    --1st: decrease index, add all stack layers
    --2nd: remove one stack layer
    --remove current leaf object and advance index
    local newIndex
    if self.indexStack:isEmpty() then
      newIndex = #self.parentStack:top()
    else
      --remove one stack layer
      self.parentStack:pop()
      newIndex = self.indexStack:pop() - 1
    end
    --get new leaf object
    local newParent = self.parentStack:top()[newIndex]
    while newParent do
      --while new leaf object exists: reinsert index and leaf object and fill stack with sub objects
      self.indexStack:push(newIndex)
      self.parentStack:push(newParent)
      newIndex = #newParent
      newParent = newParent[newIndex]
    end
    return self.parentStack:top()
  end
  
  function obj:selectFirst()
    self.indexStack = stack.new{}
    self.parentStack = stack.new{self.parentObject}
    self:selectNext()
  end
  function obj:selectLast()
    self.indexStack = stack.new{}
    self.parentStack = stack.new{self.parentObject}
    self:selectPrevious()
  end
  function obj:select(continue)
    --unmark old object
    self:unmark()
    
    --find next valid object
    local current = continue(self)
    local breakAt = current
    --skip invalid entries
    while (not current.onClick and not current.onScroll) do
      current = continue(self)
      if current == breakAt then
        --full tree traversal and no valid object found
        return
      end
    end
    
    --mark new object
    self:mark(current)
    return self.markedObject
  end
  function obj:selectNext()
    return obj:select(self.moveNext)
  end
  function obj:selectPrevious()
    return obj:select(self.movePrevious)
  end
  
  function obj:click(button)
    if self.markedObject and self.markedObject.onClick then
      self.markedObject:onClick(self.markedObject.x_draw, self.markedObject.y_draw, button)
    end
  end
  function obj:scroll(direction)
    if self.markedObject and self.markedObject.onScroll then
      self.markedObject:onScroll(self.markedObject.x_draw, self.markedObject.y_draw, direction)
    end
  end
  obj:selectNext()
  return obj
end

return qselect
