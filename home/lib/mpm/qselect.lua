-----------------------------------------------------
--name       : lib/qselect.lua
--description: qselect - a selection utility to add keyboard navigation to qui applications
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : http://oc.cil.li/index.php?/topic/
-----------------------------------------------------

--TODO: test tree traversal
local stack = require("mpm.stack")

local qselect = {}

--qselect.new(root:table) -> selection:table
--creates a selection object that is used to manage selections for the given root object
function qselect.new(root)
  checkArg(1, root, "table")
  local obj = {
    root = root,
  }
  --selection:_resetStack()
  --internal: function that resets the internal stack to the root
  function obj:_resetStack()
    self.indexStack = stack.new{}
    self.parentStack = stack.new{self.root}
  end
  --selection:_setStack(new)
  --internal: moves to the given object
  function  obj:_setStack(new)
    --find path
    local reversedIndices = stack.new()
    local reversedChildren = stack.new()
    function find(node, target)
      if node == target then
        return true
      else
        for i, subNode in ipairs(node) do
          if find(subNode, target) then
            reversedIndices:push(i)
            reversedChildren:push(subNode)
            return true
          end
        end
      end
    end
    assert(find(self.root, new), "New selected object isn't part of root element.")
    --update stack
    self:_resetStack()
    for i = #reversedIndices, 1, -1 do
      self.indexStack:push(reversedIndices[i])
      self.parentStack:push(reversedChildren[i])
    end
    return new
  end
  
  --selection:_mark(obj)
  --internal: marks the given object
  --It is redrawn and is now receiving events.
  function obj:_mark(marked)
    if self.markedObject and self.markedObject ~= marked then
      self:_unmark()
    end
    self.markedObject = marked
    if not marked.marked then
      marked.marked = true
      marked:redraw()
    end
  end
  --selection:_unmark()
  --internal: reverts the previous function
  function obj:_unmark()
    local marked = self.markedObject
    self.markedObject = nil
    if marked and marked.marked then
      marked.marked = nil
      marked:redraw()
    end
  end
  
  --selection:sortByPosition()
  --sorts all ui elements using their upper left corner in a "how you read" order
  --Sub elements are grouped by their parent.
  function obj:sortByPosition(root)
    checkArg(1, root, "table", "nil")
    root = root or self.root
    table.sort(root, function(a, b)
      return (a.y == b.y and a.x < b.x) or a.y < b.y
    end)
    for _, child in ipairs(root) do
      self:sortByPosition(child)
    end
  end
  
  --selection:initVertical([beNiceButSlow])
  --fills the ui elements' up and down fields
  --This function expects all children to be sorted by position.
  --Sub elements are grouped by their parent.
  --Use beNiceButSlow == true for layouts that don't follow a strict grid.
  function obj:initVertical(beNiceButSlow)
    checkArg(1, beNiceButSlow, "boolean", "nil")
    --create columns
    local columns = {}
    local root = self.root
    for x = 1, root.width do
      columns[x] = stack.new()
    end
    --fill columns
    function fillColumns(root)
      if root:isInteractive() then
        if beNiceButSlow then
          for x = root.x_draw, root.x_draw + root.width_draw - 1 do
            assert(columns[x], "Invalid x value! (outside drawing area)"):push(root)
          end
        else
          assert(columns[root.x_draw], "Invalid x value! (outside drawing area)"):push(root)
        end
      end
      for _, child in ipairs(root) do
        fillColumns(child)
      end
    end
    fillColumns(root)
    --find neighbors
    for x = 1, root.width do
      local above
      for _, object in ipairs(columns[x]) do
        if above then
          --prioritize going left
          object.up  = object.up  or above
          above.down = above.down or object
        end
        above = object
      end
    end
  end
  
  --selection:_moveNext()
  --internal: moves the selection stack to the next object
  function obj:_moveNext()
    local current = self.parentStack:top()
    --try user override
    if current.next then
      return self:_setStack(current.next)
    end
    --1st: add stack layer
    --2nd: increase index
    --3rd: remove stack layer, repeat 2nd step
    local topParent = self.parentStack:top()
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
  --selection:_movePrevious()
  --internal: moves the selection stack to the previous object
  function obj:_movePrevious()
    local current = self.parentStack:top()
    --try user override
    if current.previous then
      return self:_setStack(current.previous)
    end
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
  --selection:moveUp()
  --internal: moves the selection stack to the next object above
  function obj:_moveUp()
    local current = self.parentStack:top()
    --try user override
    if current.up then
      return self:_setStack(current.up)
    end
    --else: noop
    return current
  end
  --selection:moveDown()
  --internal: moves the selection stack to the next object below
  function obj:_moveDown()
    local current = self.parentStack:top()
    --try user override
    if current.down then
      return self:_setStack(current.down)
    end
    --else: noop
    return self.parentStack:top()
  end

  
  --selection:selectFirst() -> new marked object or nil
  --marks and returns the first valid object
  function obj:selectFirst()
    self:_resetStack()
    return self:selectNext()
  end
  --selection:selectLast() -> new marked object or nil
  --selects and returns the last valid object
  function obj:selectLast()
    self:_resetStack()
    return self:selectPrevious()
  end
  --selection:_select(continue(selection) -> next) -> new marked object or nil
  --internal: marks the 'next' valid object by using an iterator method
  function obj:_select(continue)
    --unmark old object
    self:_unmark()
    
    --find next valid object
    local current = continue(self)
    local breakAt = current
    --skip invalid entries
    while not current:isInteractive() do
      current = continue(self)
      if current == breakAt then
        --full tree traversal and no valid object found
        return
      end
    end
    
    --mark new object
    self:_mark(current)
    return self.markedObject
  end
  --obj:selectNext() -> new marked object or nil
  --selects and returns the next valid object
  function obj:selectNext()
    return obj:_select(self._moveNext)
  end
  --obj:selectPrevious() -> new marked object or nil
  --selects and returns the previous valid object
  function obj:selectPrevious()
    return obj:_select(self._movePrevious)
  end
  --obj:selectUp() -> new marked object or nil
  --selects and returns the next valid object above
  function obj:selectUp()
    return obj:_select(self._moveUp)
  end
  --obj:selectDown() -> new marked object or nil
  --selects and returns the next valid object below
  function obj:selectDown()
    return obj:_select(self._moveDown)
  end
  --obj:select(object) -> new marked object or nil
  --selects the given object
  function obj:select(obj)
    checkArg(1, obj, "table")
    obj:__unmark()
    if obj and obj.onClick or obj.onScroll then
      obj:__setStack(obj)
      obj:__mark(obj)
      return obj
    end
  end
  
  --obj:click(button)
  --sends a click event to the currently marked object
  function obj:click(button)
    checkArg(1, button, "number")
    if self.markedObject and self.markedObject.onClick then
      self.markedObject:onClick(self.markedObject.x_draw, self.markedObject.y_draw, button)
    end
  end
  --obj:scroll(direction)
  --sends a scroll event to the currently marked object
  function obj:scroll(direction)
    checkArg(1, direction, "number")
    if self.markedObject and self.markedObject.onScroll then
      self.markedObject:onScroll(self.markedObject.x_draw, self.markedObject.y_draw, direction)
    end
  end
  
  obj:selectFirst()
  return obj
end

return qselect
